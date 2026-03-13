// =============================================================================
// iOS Setup Validation
// =============================================================================
// Three checks — confirms Appium + simulator are working:
//   1. Session opens and reports iOS
//   2. Settings app is in the foreground (launched via wdio.ios.conf.js bundleId)
//   3. UI interaction works (tap menu item, go back)
//
// iOS-specific notes:
//   • activateApp()      → not implemented in XCUITest; use mobile: activateApp
//   • getCurrentPackage() → Android-only; use mobile: activeAppInfo on iOS
// =============================================================================

// Helper — launch an app on iOS
async function launchApp(bundleId) {
  await driver.execute('mobile: activateApp', { bundleId });
}

// Helper — get the bundle ID of the foreground app on iOS
async function getForegroundBundleId() {
  const info = await driver.execute('mobile: activeAppInfo');
  return info.bundleId || '';
}

describe('iOS Setup Validation', () => {

  it('should connect and report iOS as the platform', async () => {
    const caps = await driver.getSession();
    console.log(`  ▶ Platform: ${caps.platformName}  Device: ${caps.deviceName || 'simulator'}`);
    expect(caps.platformName.toLowerCase()).toBe('ios');
  });

  it('should have the Settings app in the foreground', async () => {
    // Settings is launched automatically by the bundleId capability in wdio.ios.conf.js
    await driver.pause(2000);
    const bundleId = await getForegroundBundleId();
    console.log(`  ▶ Foreground bundle: ${bundleId}`);
    expect(bundleId).toBe('com.apple.Preferences');
  });

  it('should tap General and go back', async () => {
    // Ensure we're on main Settings page by restarting the app
    await driver.execute('mobile: terminateApp', { bundleId: 'com.apple.Preferences' });
    await launchApp('com.apple.Preferences');
    await driver.pause(1500);

    // Tap on "General"
    const menuItem = await driver.$('~General');
    await menuItem.click();
    await driver.pause(1500);

    // Verify we navigated (should see a back button or "General" as title)
    const navBar = await driver.$('~General');
    const exists = await navBar.isDisplayed();
    console.log(`  ▶ After tap: General screen visible = ${exists}`);
    expect(exists).toBe(true);

    // Go back to main Settings by tapping the back button
    const backButton = await driver.$('-ios class chain:**/XCUIElementTypeButton[`label CONTAINS "Settings"`]');
    await backButton.click();
    await driver.pause(1500);

    // Verify we're back (General menu item should be visible again)
    const generalCell = await driver.$('~General');
    const backVisible = await generalCell.isDisplayed();
    console.log(`  ▶ After back: General menu item visible = ${backVisible}`);
    expect(backVisible).toBe(true);
  });

});
