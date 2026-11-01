import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';

const Page = loadPageMethods(
  new URL('../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets', import.meta.url),
  ['selectRuleSection']
);

test('规则页面可在样例配置和已有规则间切换，只接受有效分区', () => {
  const page = Object.assign(new Page(), { activeRuleSection: 'setup' });

  page.selectRuleSection('rules');
  assert.equal(page.activeRuleSection, 'rules');

  page.selectRuleSection('invalid');
  assert.equal(page.activeRuleSection, 'rules');

  page.selectRuleSection('setup');
  assert.equal(page.activeRuleSection, 'setup');
});
