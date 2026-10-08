import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const indexSource = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const includes = (pattern, message) => assert.ok(pattern.test(indexSource), message);
const excludes = (pattern, message) => assert.equal(pattern.test(indexSource), false, message);

test('Index delegates notification settings and signals refreshes to the page', () => {
  includes(/import\s+\{[^}]*\bNotificationSettingsPage\b[^}]*\}\s+from\s+['"]\.\/notifications\/NotificationSettingsPage['"]/,
    'Index must import NotificationSettingsPage');
  includes(/NotificationSettingsPage\s*\(\s*\{/, 'the settings route must render NotificationSettingsPage');
  includes(/@State\s+private\s+notificationProbeRefreshRevision\s*:\s*number/, 'Index must own the refresh revision');
  const refreshSignals = indexSource.match(/notificationProbeRefreshRevision\+\+/g) ?? [];
  assert.equal(refreshSignals.length, 3, 'screen, route, and ledger observers must signal page refreshes');

  for (const stateName of [
    'notificationProbe', 'notificationPermissionStatus', 'notificationSubscriptionStatus',
    'pairedBluetoothDevices', 'showNotificationAdvancedHelp'
  ]) {
    excludes(new RegExp(`private\\s+${stateName}\\s*:`), `${stateName} must move to NotificationSettingsPage`);
  }
  for (const methodName of [
    'openNotificationSubscriptionSettings', 'loadPairedBluetoothDevices', 'subscribeToPairedDevice',
    'refreshNotificationProbe', 'showNotificationProbeDetails', 'clearNotificationProbeState'
  ]) {
    excludes(new RegExp(`private\\s+async\\s+${methodName}\\s*\\(`), `${methodName} must move to NotificationSettingsPage`);
  }
});