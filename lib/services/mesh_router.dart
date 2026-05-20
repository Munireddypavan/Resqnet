import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'mesh_database.dart';
import 'mesh_network_manager.dart';
import '../providers/chat_provider.dart';

class MeshRouter {
  static final MeshRouter instance = MeshRouter._init();
  MeshRouter._init();

  late ChatProvider _chatProvider;
  late String localDeviceId;
  
  // Basic Encryption setup
  final key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
  final iv = encrypt.IV.fromUtf8('my16lengthsuper1'); // Fixed IV for basic P2P sync
  late encrypt.Encrypter encrypter;

  void init(String deviceId, ChatProvider chatProvider) {
    localDeviceId = deviceId;
    _chatProvider = chatProvider;
    MeshNetworkManager.instance.onPayloadReceived = _onPayloadReceived;
    encrypter = encrypt.Encrypter(encrypt.AES(key));
  }

  // Incoming Payload Handler
  Future<void> _onPayloadReceived(String endpointId, Payload payload) async {
    try {
      if (payload.bytes == null || payload.type != PayloadType.BYTES) {
        print("Skipping non-bytes payload from $endpointId (type: ${payload.type})");
        return;
      }
      final String jsonStr = utf8.decode(payload.bytes!);
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      
      // Basic ACK handling: if message is an ACK, update status
      if (data['type'] == 'ACK') {
        final ackMsgId = data['messageId'];
        await MeshDatabase.instance.updateMessageStatus(ackMsgId, 'Delivered');
        await _chatProvider.loadMessages(_chatProvider.currentPeerId);
        return;
      }
      
      final String messageId = data['messageId'];
      
      // 1. Check if seen before
      final bool seen = await MeshDatabase.instance.messageExists(messageId);
      if (seen) return; // Drop it
      
      // 2. Decrypt Content
      String decryptedContent = data['content'];
      try {
         decryptedContent = encrypter.decrypt64(data['content'], iv: iv);
      } catch (e) {
         print("Decryption failed: $e \nRaw content: ${data['content']}");
         decryptedContent = "ENCRYPTED_MESSAGE";
      }
      
      // 3. Not seen: Save it
      data['status'] = 'Received';
      data['content'] = decryptedContent; // Save decrypted locally
      await MeshDatabase.instance.insertMessage(data);
      
      // 4. Update Chat Provider so UI updates if it's the receiver or broadcast
      _chatProvider.addMessageLocally(data);

      final String receiverId = data['receiverId'];
      final int ttl = data['ttl'] ?? 0;

      // --- GATEWAY NODE LOGIC FOR INCOMING MESH MESSAGES ---
      if (receiverId == 'AUTHORITIES') {
        bool hasInternet = false;
        try {
          final connectivityResult = await Connectivity().checkConnectivity();
          hasInternet = !connectivityResult.contains(ConnectivityResult.none);
        } catch (e) {
          print("Connectivity check failed: $e");
        }

        if (hasInternet) {
          try {
             final response = await http.post(
               Uri.parse('https://jsonplaceholder.typicode.com/posts'),
               body: jsonEncode({'payload': decryptedContent, 'sender': data['senderId']}),
               headers: {'Content-Type': 'application/json'},
             );
             if (response.statusCode == 201 || response.statusCode == 200) {
                print("GATEWAY SUCCESS: Relayed node message to Authorities via Internet!");
                await MeshDatabase.instance.updateMessageStatus(messageId, 'Gateway Delivered');
                return; // Delivered to authorities! Stop propagating on the limited mesh network.
             }
          } catch(e) {
             print("Gateway HTTP forward failed: $e");
          }
        }
      }
      // -----------------------------------------------------

      // 5. If memory is me, send ACK back and don't forward payload.
      if (receiverId == localDeviceId) {
        _sendAck(data['senderId'], messageId);
        return;
      }
      
      // 6. If BROADCAST or not me: Forward it if TTL > 0
      if (ttl > 0 && data['senderId'] != localDeviceId) {
         // Re-encrypt before forwarding
         data['content'] = encrypter.encrypt(decryptedContent, iv: iv).base64;
         data['ttl'] = ttl - 1;
         data['hops'] = (data['hops'] as int? ?? 0) + 1; // Track hop count
         data['status'] = 'Relayed';
         await MeshDatabase.instance.updateMessageStatus(messageId, 'Relayed');
         final updatedBytes = utf8.encode(jsonEncode(data));
         final forwardPayload = Payload(id: DateTime.now().millisecondsSinceEpoch, bytes: Uint8List.fromList(updatedBytes), type: PayloadType.BYTES);
         
         // Broadcast to all peers except the sender
         await MeshNetworkManager.instance.broadcastPayload(forwardPayload, excludeEndpoint: endpointId);
      }
    } catch (e) {
      print("Error routing payload: \$e");
    }
  }

  Future<void> _sendAck(String originalSender, String messageId) async {
     final ackData = {
       'type': 'ACK',
       'messageId': messageId,
       'senderId': localDeviceId,
       'receiverId': originalSender,
       'timestamp': DateTime.now().millisecondsSinceEpoch,
     };
     final bytes = utf8.encode(jsonEncode(ackData));
     final payload = Payload(id: DateTime.now().millisecondsSinceEpoch, bytes: Uint8List.fromList(bytes));
     await MeshNetworkManager.instance.broadcastPayload(payload);
  }

  // Send a new message
  Future<void> sendMessage(String receiverId, String content, {bool isBroadcast = false, int initialTtl = 5}) async {
    final messageId = const Uuid().v4();
    final encryptedContent = encrypter.encrypt(content, iv: iv).base64;
    
    final messageData = {
      'messageId': messageId,
      'senderId': localDeviceId,
      'receiverId': receiverId,
      'content': encryptedContent,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'ttl': initialTtl,
      'hops': 0, // Starts at 0; incremented by each relay node
      'status': 'Sent',
    };

    // --- GATEWAY NODE LOGIC FOR LOCAL MESSAGES ---
    if (receiverId == 'AUTHORITIES') {
      bool hasInternet = false;
      try {
        final connectivityResult = await Connectivity().checkConnectivity();
        hasInternet = !connectivityResult.contains(ConnectivityResult.none);
      } catch (e) { print(e); }
      
      if (hasInternet) {
         try {
           await http.post(
             Uri.parse('https://jsonplaceholder.typicode.com/posts'),
             body: jsonEncode({'payload': content, 'sender': localDeviceId}),
             headers: {'Content-Type': 'application/json'},
           );
           messageData['status'] = 'Gateway Delivered';
           print("GATEWAY SUCCESS: Local authorities alert sent directly to internet.");
         } catch (e) {
            print("HTTP post failed, falling back to offline mesh: $e");
         }
      }
    }
    // ---------------------------------------------

    // Save decrypted to local DB & UI
    final localData = Map<String, dynamic>.from(messageData);
    localData['content'] = content;
    await MeshDatabase.instance.insertMessage(localData);
    _chatProvider.addMessageLocally(localData);

    // Send encrypted payload
    final bytes = utf8.encode(jsonEncode(messageData));
    final payload = Payload(id: DateTime.now().millisecondsSinceEpoch, bytes: Uint8List.fromList(bytes), type: PayloadType.BYTES);
    await MeshNetworkManager.instance.broadcastPayload(payload);
  }
}
