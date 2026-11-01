import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { filterNotificationSources } from '../entry/src/main/ets/model/NotificationArchiveModels.ets';

const pageUrl = new URL('../entry/src/main/ets/pages/notifications/NotificationSettingsPage.ets', import.meta.url);
const sources = [{ bundleName: 'com.example.clock', appName: '考勤助手' },
  { bundleName: 'com.tencent.mm', appName: '微信' }];

function harness(listSources = async () => sources) {
  const Page = loadPageMethods(pageUrl, ['openReminderSourcePicker', 'loadReminderSources',
    'closeReminderSourcePicker', 'selectReminderSource', 'filteredReminderSources',
    'reminderSourceLabel', 'changeReminderDraft'], { filterNotificationSources });
  const page = new Page();
  page.reminderSourceRepository = { open: async () => {}, listSources };
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  page.reminderBusy = false;
  page.reminderSourceRequest = 0;
  page.reminderSourcePickerOpen = false;
  page.reminderSourceLoading = false;
  page.reminderSources = [];
  page.reminderSourceQuery = '';
  page.reminderSourceError = '';
  page.reminderDraft = { enabled: false, bundleName: '', keyword: '下班成功',
    startTime: '17:00', deadlineTime: '20:00' };
  return page;
}

test('打开选择器读取归档来源，并沿用筛选页的应用名或包名搜索', async () => {
  const page = harness();
  page.reminderSourceQuery = '旧搜索';
  await page.openReminderSourcePicker();
  assert.equal(page.reminderSourcePickerOpen, true);
  assert.equal(page.reminderSourceLoading, false);
  assert.equal(page.reminderSourceQuery, '');
  assert.deepEqual(page.filteredReminderSources(), sources);
  page.reminderSourceQuery = ' 考勤 ';
  assert.deepEqual(page.filteredReminderSources(), [sources[0]]);
  page.reminderSourceQuery = 'TENCENT';
  assert.deepEqual(page.filteredReminderSources(), [sources[1]]);
});

test('点击应用仅更新来源草稿和显示名称，关闭面板，不保存提醒', async () => {
  const page = harness();
  await page.openReminderSourcePicker();
  page.selectReminderSource('com.example.clock');
  assert.equal(page.reminderDraft.bundleName, 'com.example.clock');
  assert.equal(page.reminderDraft.keyword, '下班成功');
  assert.equal(page.reminderSourceLabel(), '考勤助手');
  assert.equal(page.reminderSourcePickerOpen, false);
  page.selectReminderSource('unlisted');
  assert.equal(page.reminderDraft.bundleName, 'com.example.clock');
});

test('取消加载中的选择后迟到结果不能重开面板或修改来源', async () => {
  let complete;
  const page = harness(() => new Promise(resolve => { complete = resolve; }));
  const opening = page.openReminderSourcePicker();
  await new Promise(setImmediate);
  page.closeReminderSourcePicker();
  complete(sources);
  await opening;
  assert.equal(page.reminderSourcePickerOpen, false);
  assert.equal(page.reminderSourceLoading, false);
  assert.deepEqual(page.reminderSources, []);
  assert.equal(page.reminderDraft.bundleName, '');
});

test('快速关闭重开时，旧请求不能覆盖新请求的应用列表', async () => {
  let complete;
  let calls = 0;
  const page = harness(() => ++calls === 1 ? new Promise(resolve => { complete = resolve; }) :
    Promise.resolve([sources[1]]));
  const first = page.openReminderSourcePicker();
  await new Promise(setImmediate);
  page.closeReminderSourcePicker();
  await page.openReminderSourcePicker();
  complete([sources[0]]);
  await first;
  assert.deepEqual(page.reminderSources, [sources[1]]);
  assert.equal(page.reminderSourcePickerOpen, true);
});

test('读取失败与空记录区分，重试后恢复，旧保存来源不被清空', async () => {
  let fail = true;
  const page = harness(async () => {
    if (fail) throw new Error('归档不可用');
    return [];
  });
  page.reminderDraft.bundleName = 'old.saved.app';
  await page.openReminderSourcePicker();
  assert.match(page.reminderSourceError, /归档不可用/);
  assert.match(page.reminderSourceLabel(), /old.saved.app/);
  fail = false;
  await page.loadReminderSources();
  assert.equal(page.reminderSourceError, '');
  assert.deepEqual(page.reminderSources, []);
  assert.equal(page.reminderDraft.bundleName, 'old.saved.app');
});
