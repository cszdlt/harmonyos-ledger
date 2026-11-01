import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { defaultReminderState, parseReminderMinute, formatReminderMinute, reminderDateKey }
  from '../entry/src/main/ets/services/NotificationReminderEngine.ets';

const pageUrl = new URL('../entry/src/main/ets/pages/notifications/NotificationSettingsPage.ets', import.meta.url);
function harness(service, authResults = [0, 0]) {
  const Page = loadPageMethods(pageUrl, ['saveReminderSettings', 'refreshReminderSettings',
    'applyReminderState', 'changeReminderDraft', 'requestReminderCalendarAccess', 'authorizeReminderCalendar'], {
    parseReminderMinute, formatReminderMinute, reminderDateKey,
    abilityAccessCtrl: { createAtManager: () => ({ requestPermissionsFromUser: async (_context, permissions) => {
      assert.deepEqual(permissions, ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
      return { authResults };
    } }) }
  });
  const page = new Page();
  page.reminderService = service;
  page.reminderBusy = false;
  page.reminderDraft = { enabled: true, bundleName: 'com.example.clock', keyword: '下班打卡成功',
    startTime: '17:00', deadlineTime: '20:00' };
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  return page;
}

test('保存把时间转换为分钟并显示系统登记失败，不假报启用成功', async () => {
  let saved;
  const state = defaultReminderState();
  state.error = '提醒未就绪：权限未开通';
  const page = harness({ save: async (_context, config) => { saved = config; return state; } });
  await page.saveReminderSettings();
  assert.equal(saved.startMinute, 1020);
  assert.equal(saved.deadlineMinute, 1200);
  assert.equal(page.reminderStatus, state.error);
  assert.equal(page.reminderBusy, false);
});

test('保存启用前申请日历读写，任一项拒绝时保留草稿且不登记', async () => {
  const page = harness({ save: async () => { assert.fail('拒绝日历权限时不得登记'); } }, [0, -1]);
  await page.saveReminderSettings();
  assert.match(page.reminderStatus, /日历/);
  assert.equal(page.reminderDraft.enabled, true);
  assert.equal(page.reminderBusy, false);
});

test('手动授权日历成功后刷新已有计划，拒绝时提示设置入口', async () => {
  let refreshed = 0;
  const service = { refresh: async () => { refreshed++; return defaultReminderState(); } };
  const page = harness(service);
  await page.authorizeReminderCalendar();
  assert.equal(refreshed, 1);
  const denied = harness(service, [-1, -1]);
  await denied.authorizeReminderCalendar();
  assert.equal(refreshed, 1);
  assert.match(denied.reminderStatus, /系统设置/);
});

test('刷新同步系统状态但不会覆盖未保存的草稿', async () => {
  const page = harness({ refresh: async () => defaultReminderState() });
  page.reminderLoaded = true;
  page.changeReminderDraft('keyword', '自定义关键词');
  await page.refreshReminderSettings();
  assert.equal(page.reminderDraft.keyword, '自定义关键词');
  assert.equal(page.reminderStatus, '未启用');
});

test('保存抛错保留草稿并恢复按钮', async () => {
  const page = harness({ save: async () => { throw new Error('时间不合法'); } });
  await page.saveReminderSettings();
  assert.match(page.reminderStatus, /时间不合法/);
  assert.equal(page.reminderDraft.enabled, true);
  assert.equal(page.reminderBusy, false);
});
