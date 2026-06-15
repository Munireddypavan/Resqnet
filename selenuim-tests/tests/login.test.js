import { Builder, By, until } from 'selenium-webdriver';
import chrome from 'selenium-webdriver/chrome.js';
import assert from 'assert';

describe('ResQNet Web Dashboard E2E Tests', function() {
  let driver;

  before(async function() {
    // Set up Chrome options for automated browser simulation
    const options = new chrome.Options();
    options.addArguments('--headless=new'); // Run headlessly in testing environment
    options.addArguments('--no-sandbox');
    options.addArguments('--disable-dev-shm-usage');
    options.addArguments('--window-size=1280,800');

    driver = await new Builder()
      .forBrowser('chrome')
      .setChromeOptions(options)
      .build();
  });

  after(async function() {
    if (driver) {
      await driver.quit();
    }
  });

  it('should load the dashboard and verify header elements', async function() {
    // Open frontend React application on Vite local dev server port
    await driver.get('http://localhost:5173');

    // Wait for the app brand header logo/text to render
    const logoTextElement = await driver.wait(
      until.elementLocated(By.css('.logo-text')),
      10000
    );
    const brandText = await logoTextElement.getText();
    assert.strictEqual(brandText, 'ResQNet Web');

    // Verify system status indicators are operational
    const statusBadge = await driver.findElement(By.css('.status-badge'));
    const statusText = await statusBadge.getText();
    assert.ok(statusText.includes('ACTIVE') || statusText.includes('CONNECTING'));
  });

  it('should test Secure Mesh Chat functionality', async function() {
    await driver.get('http://localhost:5173');

    // Find chat input box using placeholder
    const chatInput = await driver.wait(
      until.elementLocated(By.css('input[placeholder="Message mesh network..."]')),
      10000
    );

    // Enter message payload
    const testMessage = 'Hello from automated E2E Selenium Test!';
    await chatInput.sendKeys(testMessage);

    // Find and click the send/submit button
    const submitBtn = await driver.findElement(By.css('form button[type="submit"]'));
    await submitBtn.click();

    // Verify chat bubble with our text was added to the secure terminal log
    const lastBubble = await driver.wait(
      until.elementLocated(By.xpath(`//div[contains(@class, 'chat-bubble')]//div[text()='${testMessage}']`)),
      5000
    );
    assert.ok(lastBubble, 'Message was not displayed in the chat interface.');
  });

  it('should test Global SOS emergency broadcast and alert response', async function() {
    await driver.get('http://localhost:5173');

    // Find broadcast details textarea input
    const broadcastArea = await driver.wait(
      until.elementLocated(By.css('textarea[placeholder="Enter urgent broadcast message details..."]')),
      10000
    );

    // Input warning info
    const broadcastMessage = 'Selenium Test: Major Power Outage Near Quadrant B';
    await broadcastArea.sendKeys(broadcastMessage);

    // Locate the Global SOS broadcast hold button
    const sosButton = await driver.findElement(
      By.xpath("//button[contains(@class, 'hold-button')][.//span[contains(text(), 'GLOBAL SOS')]]")
    );

    // Simulate mouse click-and-hold for 3.5s to trigger the emergency SOS broadcast
    const actions = driver.actions({ async: true });
    await actions.move({ origin: sosButton }).press().pause(3500).release().perform();

    // Triggering broadcast raises window.alert(), wait for it to display
    await driver.wait(until.alertIsPresent(), 5000);
    const alert = await driver.switchTo().alert();
    const alertText = await alert.getText();
    
    // Check for success alert content
    assert.ok(alertText.includes('broadcast alert successfully dispatched'));
    
    // Accept browser alert
    await alert.accept();

    // Confirm that the SOS warning details bubble is appended to the UI
    const sosBubble = await driver.wait(
      until.elementLocated(By.xpath(`//div[contains(@class, 'chat-bubble')]//div[contains(text(), '*** SOS ***')]`)),
      5000
    );
    assert.ok(sosBubble, 'SOS broadcast message bubble was not found in the feed.');
  });
});
