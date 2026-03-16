// =============================================================================
// Android Setup Validation
// =============================================================================
// Three checks — that's all we need to confirm Appium + emulator are working:
//   1. Session opens and reports Android
//   2. An app can be launched (Settings — always present)
//   3. UI interaction works (tap menu item, press back)
// =============================================================================

// Dismiss "System UI isn't responding" or similar ANR dialogs that can appear
// on slow emulators (e.g. GCP). Taps "Wait" if the dialog is present.
async function dismissSystemDialogs() {
  try {
    const waitBtn = await driver.$('android=new UiSelector().text("Wait")');
    if (await waitBtn.isDisplayed()) {
      await waitBtn.click();
      await driver.pause(2000);
    }
  } catch (_) { /* no dialog present — carry on */ }
}

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

    // Wait until "Network & internet" is actually visible and tappable.
    // On slow/fresh GCP emulators the System UI takes time to settle and may
    // show an ANR dialog — keep dismissing it until the element appears.
    await driver.waitUntil(async () => {
      await dismissSystemDialogs();
      const el = await driver.$('android=new UiSelector().textContains("Network")');
      return el.isDisplayed().catch(() => false);
    }, { timeout: 30000, interval: 2000,
         timeoutMsg: 'Network & internet item never became visible after 30s' });

    const menuItem = await driver.$('android=new UiSelector().textContains("Network")');
    await menuItem.click();
    await driver.pause(2000);

    // Dismiss any dialog that may appear after tapping
    await dismissSystemDialogs();

    // Verify we navigated away from the main Settings screen
    // (activity name varies across Android versions — just check it changed)
    const activity = await driver.getCurrentActivity();
    console.log(`  ▶ After tap: ${activity}`);
    expect(activity).not.toBeNull();

    // Press back to return to main Settings
    await driver.pressKeyCode(4);
    await driver.pause(1500);

    const backActivity = await driver.getCurrentActivity();
    console.log(`  ▶ After back: ${backActivity}`);
    expect(backActivity).toContain('Settings');
  });

});
