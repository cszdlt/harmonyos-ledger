import test, { beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import { DatabaseSync } from 'node:sqlite';

let db, plans, calendars, excluded, allowed, remindersEnabled, failWrite, failExclude, nextId, busy, legacyCancelled;
const monday = new Date(2026, 10, 2, 18).getTime();
const config = { enabled: true, bundleName: 'com.example.clock', keyword: '下班打卡成功',
  startMinute: 1020, deadlineMinute: 1200 };

// 仅替代设备日历API，持久化、事务、匹配和协调使用实际代码。
function calendar(account) {
  return {
    id: 1, getAccount: () => account,
    getConfig: () => ({ enableReminder: remindersEnabled }),
    setConfig: async value => { remindersEnabled = value.enableReminder; },
    getEvents: async (_filter, fields) => {
      assert.equal(_filter?.title, '下班打卡提醒', '真实日历运行时要求明确的筛选条件');
      assert.ok(fields.includes('recurrenceRule'));
      return structuredClone(plans);
    },
    addEvent: async event => {
      const id = nextId++;
      plans.push({ ...structuredClone(event), id });
      return id;
    },
    deleteEvent: async id => { plans = plans.filter(item => item.id !== id); },
    updateEvent: async event => {
      if (failExclude) throw new Error('更新日程失败');
      excluded.push(structuredClone(event));
      plans = plans.map(item => item.id === event.id ? structuredClone(event) : item);
    }
  };
}
globalThis.reminderTestKit = {
  reminderAgentManager: { cancelReminder: async id => { legacyCancelled.push(id); } },
  calendarManager: {
    CalendarType: { LOCAL: 0 }, EventType: { NORMAL: 0 }, RecurrenceFrequency: { WEEKLY: 2 },
    EventFilter: { filterByTitle: title => ({ title }) },
    getCalendarManager: () => ({
      getAllCalendars: async () => {
        if (!allowed) throw Object.assign(new Error('日历权限未授权'), { code: 201 });
        return calendars;
      },
      createCalendar: async account => {
        assert.equal(account.type, 0);
        const value = calendar(account);
        calendars.push(value);
        return value;
      }
    })
  },
  relationalStore: {
    SecurityLevel: { S1: 1 }, TransactionType: { IMMEDIATE: 1 },
    getRdbStore: async () => ({
      close: async () => {},
      createTransaction: async () => {
        if (busy-- > 0) throw Object.assign(new Error('locked'), { code: 14800024 });
        db.exec('BEGIN IMMEDIATE');
        return {
          execute: async (sql, args = []) => {
            if (failWrite && sql.startsWith('INSERT')) { failWrite = false; throw new Error('disk full'); }
            db.prepare(sql).run(...args);
          },
          querySql: async sql => {
            const row = db.prepare(sql).get();
            return { goToFirstRow: () => row !== undefined, getString: () => row.value, close() {} };
          },
          commit: async () => db.exec('COMMIT'), rollback: async () => db.exec('ROLLBACK')
        };
      }
    })
  }
};
registerHooks({ resolve(specifier, context, nextResolve) {
  if (!specifier.startsWith('@kit.')) return nextResolve(specifier, context);
  const code = ['common', 'BusinessError', 'calendarManager', 'notificationManager', 'reminderAgentManager', 'relationalStore']
    .map(name => `export const ${name} = globalThis.reminderTestKit.${name} ?? {};`).join('\n');
  return { url: 'data:text/javascript,' + encodeURIComponent(code), shortCircuit: true };
} });
const { NotificationReminderService } = await import('../entry/src/main/ets/services/NotificationReminderService.ets');
const { CalendarReminderGateway } = await import('../entry/src/main/ets/services/CalendarReminderGateway.ets');
beforeEach(() => {
  db?.close(); db = new DatabaseSync(':memory:');
  plans = []; calendars = []; excluded = []; legacyCancelled = [];
  allowed = true; remindersEnabled = true; failWrite = false; failExclude = false; nextId = 1; busy = 0;
});
after(() => db.close());

test('仅在专用本地日历安排周一至周五的日程，不访问其他日历和无关日程', async () => {
  calendars.push({ getAccount: () => ({ name: 'personal', type: 0 }),
    getEvents: () => { throw new Error('不得查询用户其他日历'); } });
  plans.push({ id: 99, identifier: 'unrelated' });
  const service = new NotificationReminderService();
  const saved = await service.save({}, config);
  assert.equal(saved.error, '');
  const event = plans.find(item => item.id === saved.reminderId);
  assert.deepEqual(event.recurrenceRule.daysOfWeek, [1, 2, 3, 4, 5]);
  assert.equal(event.recurrenceRule.recurrenceFrequency, 2);
  assert.deepEqual(event.reminderTime, [0]);
  assert.equal(new Date(event.startTime).getHours(), 20);
  assert.equal(new Date(event.startTime).getMinutes(), 0);
  assert.match(event.description, /尚未收到/);
  await service.save({}, { ...config, enabled: false });
  assert.deepEqual(plans.map(item => item.id), [99]);
});

test('日历排除法定节假日，并为调休周末创建单日提醒', async () => {
  const gateway = new CalendarReminderGateway({});
  const now = new Date(2026, 0, 1, 17).getTime();
  const id = await gateway.publish(config, now);
  const event = plans.find(item => item.id === id);
  const atEight = date => {
    const [year, month, day] = date.split('-').map(Number);
    return new Date(year, month - 1, day, 20).getTime();
  };
  assert.equal(new Date(event.startTime).getDay(), 1);
  assert.deepEqual(event.recurrenceRule.excludedDates, [
    '2026-01-01', '2026-01-02', '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
    '2026-02-20', '2026-02-23', '2026-04-06', '2026-05-01', '2026-05-04', '2026-05-05',
    '2026-06-19', '2026-09-25', '2026-10-01', '2026-10-02', '2026-10-05', '2026-10-06',
    '2026-10-07'
  ].map(atEight));
  assert.deepEqual(plans.filter(item => item.identifier.includes('.makeup.'))
    .map(item => new Date(item.startTime).toISOString().slice(0, 10)), [
      '2026-01-04', '2026-02-14', '2026-02-28', '2026-05-09', '2026-09-20', '2026-10-10'
    ]);
});

test('调休周末收到打卡后只删除当天单日提醒', async () => {
  const gateway = new CalendarReminderGateway({});
  const id = await gateway.publish(config, new Date(2026, 0, 1, 17).getTime());
  await gateway.exclude(id, new Date(2026, 0, 4, 18));
  assert.equal(plans.some(item => item.identifier.endsWith('.2026-01-04')), false);
  assert.equal(plans.filter(item => item.identifier.includes('.makeup.')).length, 5);
  assert.equal(plans.some(item => item.id === id), true);
});

test('刷新会补回缺失的调休日程，但不重复创建', async () => {
  const originalNow = Date.now;
  Date.now = () => new Date(2026, 0, 1, 17).getTime();
  try {
    const service = new NotificationReminderService();
    const saved = await service.save({}, config);
    const originalId = saved.reminderId;
    assert.equal(plans.filter(item => item.identifier.includes('.makeup.')).length, 6);
    const missing = plans.find(item => item.identifier.endsWith('.2026-01-04'));
    plans = plans.filter(item => item.id !== missing.id);
    await new NotificationReminderService().refresh({});
    assert.equal(plans.filter(item => item.identifier.includes('.makeup.')).length, 6);
    assert.equal(plans.filter(item => item.identifier === 'com.gyg.harmonyledger.attendance.reminder.v1').length, 1);
    assert.equal(plans.find(item => item.identifier === 'com.gyg.harmonyledger.attendance.reminder.v1').id, originalId);
  } finally {
    Date.now = originalNow;
  }
});

test('未授权时保留配置，授权后重试；关闭日历提醒时提示但仍允许停用', async () => {
  allowed = false;
  const service = new NotificationReminderService();
  const failed = await service.save({}, config);
  assert.match(failed.error, /201/);
  assert.match(failed.error, /日历/);
  assert.equal(failed.config.enabled, true);
  assert.equal(failed.reminderId, -1);
  allowed = true;
  assert.equal((await new NotificationReminderService().refresh({})).error, '');
  assert.equal(plans.length, 1);
  remindersEnabled = false;
  assert.match((await service.refresh({})).error, /日历.*提醒/);
  assert.equal((await service.save({}, { ...config, enabled: false })).error, '');
  assert.equal(plans.length, 0);
});

test('排除时间必须对齐当天日程20点，保留其他日期并避免重复更新', async () => {
  const service = new NotificationReminderService();
  await service.save({}, config);
  const past = new Date(2026, 9, 30, 20).getTime();
  plans[0].recurrenceRule.excludedDates = [past];
  const input = { bundleName: config.bundleName, title: '', body: config.keyword,
    deliveryTime: monday, receivedAt: monday };
  await service.receive({}, input);
  await new NotificationReminderService().receive({}, input);
  assert.equal(excluded.length, 1);
  assert.deepEqual(plans[0].recurrenceRule.excludedDates, [past, new Date(2026, 10, 2, 20).getTime()]);
  const changed = await service.save({}, { ...config, keyword: '签退成功' });
  assert.equal(changed.matchedDate, '');
  assert.equal(plans.length, 1);
  assert.equal(plans[0].recurrenceRule.excludedDates?.length ?? 0, 0);
});

test('日历更新失败保留完成记录，重复通知能重试排除当天', async () => {
  const service = new NotificationReminderService();
  await service.save({}, config);
  const input = { bundleName: config.bundleName, title: config.keyword, body: '', receivedAt: monday };
  failExclude = true;
  await assert.rejects(service.receive({}, input), /更新日程失败/);
  const failed = JSON.parse(db.prepare('SELECT value FROM reminder_state').get().value);
  assert.equal(failed.matchedDate, '2026-11-02');
  assert.equal(failed.excludedDate, '');
  failExclude = false;
  await service.receive({}, input);
  assert.equal(excluded.length, 1);
  assert.deepEqual(plans[0].recurrenceRule.excludedDates, [new Date(2026, 10, 2, 20).getTime()]);
});

test('并发恢复与通知处理不重复创建，也不丢失完成状态', async () => {
  await new NotificationReminderService().save({}, config);
  busy = 1;
  await Promise.all([new NotificationReminderService().refresh({}),
    new NotificationReminderService().receive({}, {
      bundleName: config.bundleName, title: config.keyword, body: '', receivedAt: monday
    })]);
  assert.equal(plans.length, 1);
  assert.equal(excluded.length, 1);
  assert.equal(JSON.parse(db.prepare('SELECT value FROM reminder_state').get().value).matchedDate, '2026-11-02');
});

test('首次启用写入失败后，恢复会撤销中断遗留日程', async () => {
  const service = new NotificationReminderService();
  await service.refresh({}); failWrite = true;
  await assert.rejects(service.save({}, config), /disk full/);
  assert.equal(plans.length, 1);
  assert.equal((await service.refresh({})).config.enabled, false);
  assert.equal(plans.length, 0);
});

test('旧代理提醒ID迁移时独立撤销，不能误删相同编号的日历日程', async () => {
  await new NotificationReminderService().refresh({});
  const old = JSON.parse(db.prepare('SELECT value FROM reminder_state').get().value);
  delete old.backend; old.config = config; old.reminderId = 99; old.scheduledMinute = 1200;
  db.prepare('UPDATE reminder_state SET value = ?').run(JSON.stringify(old));
  plans.push({ id: 99, identifier: 'unrelated' });
  const migrated = await new NotificationReminderService().refresh({});
  assert.equal(migrated.backend, 'calendar');
  assert.deepEqual(legacyCancelled, [99]);
  assert.ok(plans.some(item => item.id === 99));
  assert.notEqual(migrated.reminderId, 99);
});

test('升级后首条无关通知也要恢复已启用的日程，不能只撤销旧提醒', async () => {
  const service = new NotificationReminderService();
  await service.refresh({});
  const old = JSON.parse(db.prepare('SELECT value FROM reminder_state').get().value);
  delete old.backend; old.config = config; old.reminderId = 88; old.scheduledMinute = 1200;
  db.prepare('UPDATE reminder_state SET value = ?').run(JSON.stringify(old));
  await service.receive({}, { bundleName: 'unrelated.app', title: '', body: '', receivedAt: monday });
  const saved = JSON.parse(db.prepare('SELECT value FROM reminder_state').get().value);
  assert.deepEqual(legacyCancelled, [88]);
  assert.equal(saved.backend, 'calendar');
  assert.equal(saved.error, '');
  assert.ok(saved.reminderId > 0);
  assert.equal(plans.length, 1);
});

test('停用时无效时间不妨碍撤销日程，仍保留原有效时间', async () => {
  const service = new NotificationReminderService();
  await service.save({}, config);
  const disabled = await service.save({}, { ...config, enabled: false, startMinute: -1, deadlineMinute: -1 });
  assert.equal(disabled.error, ''); assert.equal(plans.length, 0);
  assert.equal(disabled.config.startMinute, 1020); assert.equal(disabled.config.deadlineMinute, 1200);
});
