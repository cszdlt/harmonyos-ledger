import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const pagePath = new URL('../entry/src/main/ets/pages/notifications/NotificationSettingsPage.ets', import.meta.url);
const pageSource = existsSync(fileURLToPath(pagePath)) ? readFileSync(fileURLToPath(pagePath), 'utf8') : '';
const includes = (pattern, message) => assert.ok(pattern.test(pageSource), message);

test('NotificationSettingsPage exposes its revision and route callbacks', () => {
  assert.notEqual(pageSource, '', 'NotificationSettingsPage.ets must exist');
  includes(/export\s+struct\s+NotificationSettingsPage/, 'the settings page must be exported');
  includes(/@Watch\('[^']+'\)[\s\S]{0,100}\bprobeRevision\s*:/,
    'probe revisions must refresh the page');
  includes(/onBack\s*:/, 'the page must receive a back callback');
  includes(/onOpenRules\s*:/, 'the page must receive a rules callback');
});

test('NotificationSettingsPage owns settings state and connects the existing view', () => {
  includes(/NotificationSettingsView\s*\(/, 'the page must compose the existing settings view');
  for (const stateName of ['permissionStatus', 'subscriptionStatus', 'probe', 'pairedDevices', 'advancedHelp']) {
    includes(new RegExp(`@State\\s+private\\s+${stateName}\\s*:`), `${stateName} must belong to the page`);
  }
  includes(/aboutToAppear\(\)[\s\S]{0,120}refreshProbeForRevision\(\)/,
    'the page must check its revision when it appears');
  includes(/private refreshProbeForRevision\(\): void[\s\S]{0,180}refreshNotificationProbe\(\)/,
    'a new probe revision must refresh settings state');
  for (const api of [
    'openSubscriptionSettingsWithResult', 'requestPermissionsFromUser', 'getPairedDevices',
    'getRemoteDeviceName', 'notificationExtensionSubscription.subscribe', 'loadNotificationProbe',
    'getSubscribeInfo', 'isUserGranted', 'getUserGrantedEnabledBundles', 'clearNotificationProbe'
  ]) {
    assert.ok(pageSource.includes(api), `${api} must remain available`);
  }
  includes(/showDialog\(/, 'recent notification details must stay in the local dialog');
});