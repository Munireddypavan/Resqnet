import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../providers/mesh_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentPosition;
  bool _isLoading = true;
  String _errorMessage = '';
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Location services are disabled.';
          _isLoading = false;
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Location permissions are denied';
            _isLoading = false;
          });
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Location permissions are permanently denied, we cannot request permissions.';
          _isLoading = false;
        });
      }
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final meshProvider = context.watch<MeshProvider>();
    
    return Container(
      color: AppTheme.surfaceContainerLowest,
      child: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.redAccent, fontFamily: 'Inter', fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentPosition!,
                          initialZoom: 16.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.resqnet.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _currentPosition!,
                                width: 80,
                                height: 80,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 16, height: 16,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: const [
                                          BoxShadow(color: AppTheme.primaryContainer, blurRadius: 4),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceContainer.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'LOCAL_NODE',
                                        style: TextStyle(fontFamily: 'Inter', fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.primary, letterSpacing: 1.0),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
          ),
          Positioned(
            top: 24, left: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHudPanel('Network Status', 'MESH: ON', '${meshProvider.connectedNodesCount} NODES'),
                const SizedBox(height: 8),
                _buildHudPanel('Signal Strength', 'GOOD', '', icon: Icons.signal_cellular_alt),
              ],
            ),
          ),
          Positioned(
            bottom: 24, right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryContainer,
                    foregroundColor: AppTheme.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    // Optional: re-center map on user location
                    if (_currentPosition != null) {
                      _mapController.move(_currentPosition!, 16.0);
                    }
                  },
                  icon: const Icon(Icons.my_location, size: 20),
                  label: const Text('RE-CENTER MESH', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 14)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Auto-scan: 30s interval', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceVariant, letterSpacing: 1.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHudPanel(String title, String value, String subValue, {IconData? icon}) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: AppTheme.primary, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.primary, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (icon != null) ...[Icon(icon, color: AppTheme.secondary, size: 24), const SizedBox(width: 8)],
              Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (subValue.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(subValue, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceVariant))
              ],
            ],
          ),
        ],
      ),
    );
  }
}
