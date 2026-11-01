import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { backNotificationRoute } from '../entry/src/main/ets/model/MainTabNavigation.ts';

const pageUrl = new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url);
const Index = loadPageMethods(pageUrl, ['onBackPress'], { backNotificationRoute });

function createIndex(route) {
  return Object.assign(new Index(), {
    settingsBusy: false,
    creditHistoryRule: undefined,
    creditHistorySaving: false,
    pendingDeleteId: '',
    screen: 'ledger',
    shareImportMode: false,
    mainTabNavigation: { activeTab: 'notifications', notificationRoute: route },
    notificationHistoryOverlayOpen: false,
    notificationHistoryBackRequestRevision: 0,
    notificationSettingsBackRequestRevision: 0,
    statisticsEditorOpen: false
  });
}

test('system back from notification history returns to the ledger instead of exiting', () => {
  const index = createIndex('history');

  assert.equal(index.onBackPress(), true);
  assert.equal(index.mainTabNavigation.activeTab, 'ledger');
});

test('system back from notification settings delegates to its local back handler', () => {
  const index = createIndex('settings');

  assert.equal(index.onBackPress(), true);
  assert.equal(index.notificationSettingsBackRequestRevision, 1);
  assert.equal(index.mainTabNavigation.notificationRoute, 'settings');
});
