import test from 'node:test';
import assert from 'node:assert/strict';
import {
  backNotificationRoute,
  initialMainTabNavigationState,
  navigateNotificationTo,
  selectMainTab
} from '../entry/src/main/ets/model/MainTabNavigation.ts';

test('navigation starts on the ledger tab with notification history as its root', () => {
  assert.deepEqual(initialMainTabNavigationState(), {
    activeTab: 'ledger',
    notificationRoute: 'history'
  });
});

test('switching tabs returns notification navigation to its home page', () => {
  const notificationSettings = {
    activeTab: 'notifications',
    notificationRoute: 'settings'
  };

  const ledger = selectMainTab(notificationSettings, 'ledger');
  assert.deepEqual(ledger, {
    activeTab: 'ledger',
    notificationRoute: 'history'
  });
  assert.deepEqual(selectMainTab(ledger, 'notifications'), {
    activeTab: 'notifications',
    notificationRoute: 'history'
  });
});

test('notification back navigation returns from settings and rules to their parent', () => {
  const history = {
    activeTab: 'notifications',
    notificationRoute: 'history'
  };
  const rules = navigateNotificationTo('rules');

  assert.deepEqual(rules, {
    activeTab: 'notifications',
    notificationRoute: 'rules'
  });
  const settings = backNotificationRoute(rules);
  assert.deepEqual(settings, {
    activeTab: 'notifications',
    notificationRoute: 'settings'
  });
  assert.deepEqual(backNotificationRoute(settings), history);
  assert.deepEqual(backNotificationRoute(history), {
    activeTab: 'ledger',
    notificationRoute: 'history'
  });
});
