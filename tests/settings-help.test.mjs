import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';

const settingsUrl = new URL('../entry/src/main/ets/pages/ledger/LedgerSettingsPage.ets', import.meta.url);
const tabUrl = new URL('../entry/src/main/ets/pages/ledger/LedgerTabPage.ets', import.meta.url);

test('从设置打开帮助并返回时保留周期及操作提示，重开从入门主题开始', () => {
  const Page = loadPageMethods(settingsUrl, ['openHelp', 'closeHelp']);
  const page = new Page();
  Object.assign(page, { busy: false, helpOpen: false, helpTopicId: 'backup', cycleStartDay: 15,
    operationMessage: '完整备份已导出' });
  page.openHelp();
  assert.equal(page.helpOpen, true);
  assert.equal(page.helpTopicId, 'start');
  page.helpTopicId = 'notifications';
  page.closeHelp();
  assert.equal(page.helpOpen, false);
  assert.equal(page.cycleStartDay, 15);
  assert.equal(page.operationMessage, '完整备份已导出');
  page.openHelp();
  assert.equal(page.helpTopicId, 'start');
});

test('备份等设置操作正在执行时不能打开帮助', () => {
  const Page = loadPageMethods(settingsUrl, ['openHelp']);
  const page = new Page();
  Object.assign(page, { busy: true, helpOpen: false, helpTopicId: 'start' });
  page.openHelp();
  assert.equal(page.helpOpen, false);
});

test('系统返回键先关闭帮助留在设置，再次返回才回到账本', () => {
  const Page = loadPageMethods(tabUrl, ['onBackRequestChanged']);
  const page = new Page();
  Object.assign(page, { screen: 'settings', helpOpen: true });
  page.onBackRequestChanged();
  assert.equal(page.helpOpen, false);
  assert.equal(page.screen, 'settings');
  page.onBackRequestChanged();
  assert.equal(page.screen, 'ledger');
});
