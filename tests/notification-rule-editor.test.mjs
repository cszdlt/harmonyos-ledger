import test from 'node:test';
import assert from 'node:assert/strict';
import { createDefaultNotificationRules } from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';
import { loadPageMethods } from './helpers/page-methods.mjs';

test('通知规则经过列表和编辑器复制后保留标题限制', () => {
  const rule = { ...createDefaultNotificationRules()[3], requiredTitle: '微信支付' };
  for (const path of [
    '../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets',
    '../entry/src/main/ets/components/notifications/NotificationRuleEditor.ets'
  ]) {
    const Page = loadPageMethods(new URL(path, import.meta.url), ['copyRule']);
    const copied = new Page().copyRule(rule);
    assert.equal(copied.requiredTitle, '微信支付', path);
  }
});
