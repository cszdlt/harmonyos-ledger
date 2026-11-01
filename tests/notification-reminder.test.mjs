import test from 'node:test';
import assert from 'node:assert/strict';
import {
  defaultReminderState, validateReminderConfig, matchesReminderNotification,
  reconcileReminder, recordReminderNotification, parseReminderMinute, formatReminderMinute
} from '../entry/src/main/ets/services/NotificationReminderEngine.ets';

const monday = (hour, minute = 0) => new Date(2026, 10, 2, hour, minute).getTime();
function state() {
  const value = defaultReminderState();
  value.config = { enabled: true, bundleName: 'com.example.clock', keyword: '下班打卡成功',
    startMinute: 17 * 60, deadlineMinute: 20 * 60 };
  return value;
}
function input(overrides = {}) {
  return { bundleName: 'com.example.clock', title: '考勤', body: '下班打卡成功',
    deliveryTime: monday(18), receivedAt: monday(18), ...overrides };
}
// 系统 API 无法在 Node 执行；替身保留已登记计划和排除日期，核对真实协调逻辑的结果。
class SystemReminders {
  reminders = [];
  excluded = [];
  nextId = 1;
  failPublish = false;
  failExclude = false;
  async list() { return this.reminders; }
  async publish(config, now) {
    if (this.failPublish) throw new Error('权限未开通');
    const id = this.nextId++;
    this.reminders.push({ id });
    return id;
  }
  async cancel(id) { this.reminders = this.reminders.filter(item => item.id !== id); }
  async exclude(id, date) {
    if (this.failExclude) throw new Error('系统暂不可用');
    this.excluded.push({ id, date });
  }
}

test('规则必须指定包名、成功关键词以及同日内有序的合法时间', () => {
  const config = state().config;
  assert.equal(validateReminderConfig(config), '');
  for (const change of [{ bundleName: '' }, { keyword: ' ' }, { startMinute: -1 },
    { deadlineMinute: 1440 }, { deadlineMinute: NaN }, { startMinute: 1200 },
    { startMinute: 1020.5 }]) {
    assert.notEqual(validateReminderConfig({ ...config, ...change }), '');
  }
});

test('时间文本只接受合法的二十四小时 HH:mm 格式', () => {
  assert.equal(parseReminderMinute('20:00'), 1200);
  assert.equal(parseReminderMinute(' 00:00 '), 0);
  assert.equal(parseReminderMinute('23:59'), 1439);
  for (const value of ['24:00', '20:60', '8:00', '', '20', '20:00:00']) {
    assert.equal(parseReminderMinute(value), -1);
  }
  assert.equal(formatReminderMinute(0), '00:00');
  assert.equal(formatReminderMinute(1205), '20:05');
});

test('截止后才收到的通知不算按时收到，也不能误报已经跳过提醒', async () => {
  const value = state();
  const system = new SystemReminders();
  const late = input({ deliveryTime: monday(19, 59), receivedAt: monday(20, 1) });
  assert.equal(matchesReminderNotification(value.config, late), false);
  await recordReminderNotification(value, system, late);
  assert.equal(value.matchedDate, '');
  assert.deepEqual(system.excluded, []);
});

test('仅精确来源、包含成功关键词、同一工作日时间窗内的通知才算完成', () => {
  const config = state().config;
  assert.equal(matchesReminderNotification(config, input()), true);
  assert.equal(matchesReminderNotification(config, input({ title: '下班打卡成功', body: '' })), true);
  for (const change of [{ bundleName: 'other' }, { body: '上班打卡成功' },
    { deliveryTime: monday(16, 59) }, { deliveryTime: monday(20) },
    { deliveryTime: monday(18) - 86400000 }, { deliveryTime: monday(18) + 86400000 },
    { receivedAt: new Date(2026, 10, 7, 18).getTime(), deliveryTime: undefined }]) {
    assert.equal(matchesReminderNotification(config, input(change)), false);
  }
  assert.equal(matchesReminderNotification({ ...config, enabled: false }, input()), false);
  assert.equal(matchesReminderNotification(config, input({ deliveryTime: undefined })), true);
  assert.equal(matchesReminderNotification(config, input({ deliveryTime: monday(17) })), true);
});

test('重复同步只创建一个计划，收到通知只排除当天并保留后续提醒', async () => {
  const value = state();
  const system = new SystemReminders();
  await reconcileReminder(value, system, monday(17));
  await reconcileReminder(value, system, monday(17));
  assert.equal(system.reminders.length, 1);
  await recordReminderNotification(value, system, input());
  await recordReminderNotification(value, system, input());
  assert.equal(system.reminders.length, 1);
  assert.equal(system.excluded.length, 1);
  assert.equal(system.excluded[0].date.getDate(), 2);
  assert.equal(value.matchedDate, '2026-11-02');
  await reconcileReminder(value, system, monday(17) + 86400000);
  assert.equal(system.reminders.length, 1);
  assert.equal(system.excluded.length, 1);
});

test('停用会撤销本功能全部计划，包括中断后未保存的登记', async () => {
  const value = state();
  const system = new SystemReminders();
  system.reminders = [{ id: 7 }, { id: 8 }];
  value.config.enabled = false;
  await reconcileReminder(value, system, monday(18));
  assert.deepEqual(system.reminders, []);
  assert.equal(value.reminderId, -1);
});

test('计划丢失或时间变更后重建；已完成当天仍被排除', async () => {
  const value = state();
  const system = new SystemReminders();
  await recordReminderNotification(value, system, input());
  const oldId = value.reminderId;
  value.config.deadlineMinute = 21 * 60;
  await reconcileReminder(value, system, monday(19));
  assert.notEqual(value.reminderId, oldId);
  assert.equal(system.reminders.length, 1);
  assert.equal(system.excluded.at(-1).id, value.reminderId);
  system.reminders = [];
  await reconcileReminder(value, system, monday(19));
  assert.equal(system.reminders.length, 1);
  assert.equal(system.excluded.at(-1).id, value.reminderId);
});

test('排除失败仍保留完成记录，恢复时重试；发布失败不会标记安排成功', async () => {
  const value = state();
  const system = new SystemReminders();
  system.failPublish = true;
  await assert.rejects(reconcileReminder(value, system, monday(17)), /权限/);
  assert.equal(value.reminderId, -1);
  system.failPublish = false;
  system.failExclude = true;
  await assert.rejects(recordReminderNotification(value, system, input()), /系统/);
  assert.equal(value.matchedDate, '2026-11-02');
  assert.equal(value.excludedDate, '');
  system.failExclude = false;
  await reconcileReminder(value, system, monday(19));
  assert.equal(value.excludedDate, '2026-11-02');
});
