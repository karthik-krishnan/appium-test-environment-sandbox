// =============================================================================
// Android Setup Validation
// =============================================================================
// Three checks — that's all we need to confirm Appium + emulator are working:
//   1. Session opens and reports Android
//   2. An app can be launched (Settings — always present)
//   3. UI interaction works (tap menu item, press back)
// =============================================================================

describe('Android Setup Validation', () => {

  it('should connect and report Android as the platform', async () => {
    const caps = await driver.getSession();
    console.log(`  ▶ Platform: ${caps.platformName}  Device: ${caps.deviceName || 'emulator'}`);
    expect(caps.platformName.toLowerCase()).toBe('android');
  });

  it('should launch the Settings app', async () => {
    await driver.activateApp('com.android.settings');
    await driver.pause(2000);
    const pkg = await driver.getCurrentPackage();
    console.log(`  ▶ Foreground package: ${pkg}`);
    expect(pkg).toBe('com.android.settings');
  });

  it('should tap Network & internet and go back', async () => {
    // Ensure we're on main Settings page by restarting the app
    await driver.terminateApp('com.android.settings');
    await driver.activateApp('com.android.settings');
    await driver.pause(1500);

    // Tap on "Network & internet"
    const menuItem = await driver.$('android=new UiSelector().textContains("Network")');
    await menuItem.click();
    await driver.pause(1500);

    // Verify we navigated to a sub-menu
    const activity = await driver.getCurrentActivity();
    console.log(`  ▶ After tap: ${activity}`);
    expect(activity).toBe('.SubSettings');

    // Press back to return to main Settings
    await driver.pressKeyCode(4);
    await driver.pause(1500);

    const backActivity = await driver.getCurrentActivity();
    console.log(`  ▶ After back: ${backActivity}`);
    expect(backActivity).toContain('Settings');
  });

});
