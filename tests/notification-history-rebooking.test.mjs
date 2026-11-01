import test from 'node:test';
import assert from 'node:assert/strict';
import { createDefaultNotificationRules } from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';
import { findHistoricalNotificationCandidates, NotificationHistoryRebookingMatcher } from '../entry/src/main/ets/services/NotificationHistoryRebooking.ets';
import { formatMoney } from '../entry/src/main/ets/model/LedgerModels.ets';
import { loadPageMethods } from './helpers/page-methods.mjs';

const timestamp = new Date(2026, 9, 20, 12, 3).getTime();
const rule = createDefaultNotificationRules()[0];

function notice(id, body = '尾号1234卡10月20日12:03支出（消费午餐）18.50元', overrides = {}) {
  return { id, hashCode: String(id), slotType: 1, bundleName: 'com.icbc.mobile', appName: '工商银行',
    deliveryTime: timestamp, groupName: '', appIndex: 0, title: '', body, receivedAt: timestamp,
    eventTime: timestamp, ...overrides };
}

function ledgerEntry(id, overrides = {}) {
  return { id, happenedAt: timestamp, hasTime: true, amountFen: 1850, direction: 'expense',
    source: 'manual', merchant: '午餐', category: '餐饮', note: '', ...overrides };
}

test('历史通知只按指定规则解析，并保留解析结果供预览入账', () => {
  const candidates = findHistoricalNotificationCandidates([notice(1)], rule, []);

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].archive.id, 1);
  assert.equal(candidates[0].entry.amountFen, 1850);
  assert.equal(candidates[0].entry.direction, 'expense');
  assert.equal(candidates[0].entry.merchant, '午餐');
  assert.equal(candidates[0].entry.category, '消费');
  assert.equal(candidates[0].duplicate, false);
});

test('历史排除样例与失败通知不会进入候选', () => {
  const excludedRule = { ...rule, excludeBodyPatterns: ['摘要通知'] };
  const candidates = findHistoricalNotificationCandidates([
    notice(1, '摘要通知：尾号1234卡10月20日12:03支出（消费午餐）18.50元'),
    notice(2, '尾号1234卡10月20日12:03支出（消费午餐）18.50元 交易失败')
  ], excludedRule, []);

  assert.deepEqual(candidates, []);
});

test('查重按同分钟、金额、方向及有时间精度判定，并识别归档内重复通知', () => {
  const candidates = findHistoricalNotificationCandidates([
    notice(1),
    notice(2),
    notice(3, '尾号1234卡10月20日12:03支出（消费午餐）19.00元'),
    notice(4, '尾号1234卡10月20日12:04支出（消费午餐）18.50元')
  ], rule, [
    ledgerEntry('same-minute', { happenedAt: timestamp + 25000 }),
    ledgerEntry('date-only', { happenedAt: timestamp + 60000, hasTime: false }),
    ledgerEntry('different-direction', { direction: 'income' })
  ]);

  assert.deepEqual(candidates.map((candidate) => [candidate.archive.id, candidate.duplicate]), [
    [1, true], [2, true], [3, false], [4, false]
  ]);
});

test('历史归档可逐页解析，跨页重复仍只保留一个可补记候选', () => {
  const matcher = new NotificationHistoryRebookingMatcher(rule, []);

  matcher.scan([notice(1)]);
  assert.equal(matcher.preview()[0].duplicate, false);
  matcher.scan([notice(2)]);

  assert.deepEqual(matcher.preview().map((candidate) => [candidate.archive.id, candidate.duplicate]), [
    [1, false], [2, true]
  ]);
});

const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/notifications/NotificationRebookingPage.ets', import.meta.url),
  ['previewHistory', 'availableCandidates', 'allAvailableSelected', 'toggleAllAvailable', 'toggleCandidate',
    'selectedCandidates', 'selectedTotalFen', 'applySelection'],
  { NotificationHistoryRebookingMatcher, formatMoney });
const SettingsPage = loadPageMethods(
  new URL('../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets', import.meta.url),
  ['openRebooking', 'copyRule']);
const relationalStore = { TransactionType: { IMMEDIATE: 'immediate' },
  ConflictResolution: { ON_CONFLICT_IGNORE: 'ignore' }, RdbPredicates: class { equalTo() {} } };
const accountingTypeOf = (entry) => entry.direction === 'expense' && entry.accountingType === 'credit-card'
  ? 'credit-card' : 'normal';
const LedgerRepository = loadPageMethods(
  new URL('../entry/src/main/ets/data/LedgerRepository.ets', import.meta.url),
  ['addNotificationEntry', 'acquireNotificationEntryTransaction'], { relationalStore, accountingTypeOf });

function page() {
  return Object.assign(new Page(), { rule, loading: false, saving: false, scannedCount: 0, hasPreview: false,
    candidates: [], selectedIds: [], message: '', requestId: 0 });
}

test('启用规则可打开自己的历史补记页，停用规则不能启动补记', () => {
  const settings = Object.assign(new SettingsPage(), { rules: [{ ...rule, excludeBodyPatterns: ['摘要通知'] }],
    rebookingRule: undefined });

  settings.openRebooking(0);

  assert.notEqual(settings.rebookingRule, settings.rules[0]);
  assert.deepEqual(settings.rebookingRule.excludeBodyPatterns, ['摘要通知']);
  settings.rules[0] = { ...settings.rules[0], enabled: false };
  settings.rebookingRule = undefined;
  settings.openRebooking(0);
  assert.equal(settings.rebookingRule, undefined);
});

test('历史预览按页扫描并默认不勾选，预览阶段不写账本', async () => {
  const instance = page();
  let pageCalls = 0;
  instance.getUIContext = () => ({ getHostContext: () => ({}) });
  instance.archiveRepository = { open: async () => {}, listPage: async (_filter, cursor) => {
    pageCalls++;
    return cursor === undefined
      ? { entries: [notice(1)], nextCursor: { eventTime: timestamp, id: 1 } }
      : { entries: [notice(2)], nextCursor: undefined };
  } };
  instance.ledgerRepository = { open: async () => {}, listEntries: async () => [],
    addNotificationEntry: async () => { throw new Error('预览不能写账本'); } };

  await instance.previewHistory();

  assert.equal(pageCalls, 2);
  assert.equal(instance.scannedCount, 2);
  assert.equal(instance.hasPreview, true);
  assert.deepEqual(instance.selectedIds, []);
  assert.equal(instance.candidates.length, 2);
  assert.equal(instance.candidates[1].duplicate, true);
});

test('全选只选择无重复候选，手动选择金额汇总正确', () => {
  const instance = page();
  instance.candidates = findHistoricalNotificationCandidates([notice(1), notice(2)], rule, []);

  instance.toggleAllAvailable();
  assert.deepEqual(instance.selectedIds, ['1']);
  assert.equal(instance.selectedTotalFen(), 1850);
  assert.equal(instance.allAvailableSelected(), true);
  instance.toggleAllAvailable();
  assert.deepEqual(instance.selectedIds, []);
  instance.toggleCandidate(instance.candidates[1], true);
  assert.deepEqual(instance.selectedIds, []);
});

test('确认弹窗取消不入账，确认后按顺序写入并清除旧预览', async () => {
  const instance = page();
  instance.candidates = findHistoricalNotificationCandidates([notice(1)], rule, []);
  instance.selectedIds = ['1'];
  let writes = 0;
  let dialogIndex = 0;
  instance.getUIContext = () => ({ getPromptAction: () => ({ showDialog: async () => ({ index: dialogIndex }) }) });
  instance.ledgerRepository = { addNotificationEntry: async () => { writes++; } };

  await instance.applySelection();
  assert.equal(writes, 0);
  assert.deepEqual(instance.selectedIds, ['1']);

  dialogIndex = 1;
  await instance.applySelection();
  assert.equal(writes, 1);
  assert.equal(instance.hasPreview, false);
  assert.deepEqual(instance.selectedIds, []);
  assert.match(instance.message, /已处理 1 条/);
});

test('批量补记中途失败保留选择以便安全重试', async () => {
  const instance = page();
  instance.candidates = findHistoricalNotificationCandidates([notice(1)], rule, []);
  instance.selectedIds = ['1'];
  instance.getUIContext = () => ({ getPromptAction: () => ({ showDialog: async () => ({ index: 1 }) }) });
  instance.ledgerRepository = { addNotificationEntry: async () => { throw new Error('写入失败'); } };

  await instance.applySelection();

  assert.deepEqual(instance.selectedIds, ['1']);
  assert.equal(instance.saving, false);
  assert.match(instance.message, /可安全重试/);
});

test('并发通知入账通过立即事务串行查重，避免不同规则 ID 重复写账', async () => {
  const rows = [];
  const transactions = [];
  let transactionLocked = false;
  const resultFor = (args) => {
    const [minuteStart, minuteEnd, amountFen, direction] = args;
    const row = rows.find((candidate) => candidate.happenedAt >= minuteStart && candidate.happenedAt < minuteEnd &&
      candidate.amountFen === amountFen && candidate.direction === direction && candidate.hasTime);
    return {
      goToNextRow: () => row !== undefined,
      getColumnIndex: (name) => name,
      getString: (name) => row[name],
      close: () => {}
    };
  };
  const wait = () => new Promise((resolve) => setTimeout(resolve, 30));
  const store = {
    querySql: async (_sql, args) => {
      const result = resultFor(args);
      await wait();
      return result;
    },
    insert: async (_table, values) => { rows.push(values.mockEntry); return rows.length; },
    update: async () => 0,
    executeSql: async () => {},
    createTransaction: async (options) => {
      transactions.push(options);
      if (transactionLocked) {
        const failure = new Error('database locked');
        failure.code = 14800024;
        throw failure;
      }
      transactionLocked = true;
      return {
        querySql: async (_sql, args) => {
          const result = resultFor(args);
          await wait();
          return result;
        },
        insert: async (_table, values) => { rows.push(values.mockEntry); return rows.length; },
        update: async () => 0,
        execute: async () => {},
        commit: async () => { transactionLocked = false; },
        rollback: async () => { transactionLocked = false; }
      };
    }
  };
  function repository() {
    const instance = new LedgerRepository();
    instance.requireStore = () => store;
    instance.toValues = (entry) => ({ mockEntry: entry });
    instance.emitLedgerEntriesChanged = () => {};
    return instance;
  }
  const first = { id: 'rule-a-notice', happenedAt: timestamp, hasTime: true, amountFen: 1850,
    direction: 'expense', source: 'icbc', merchant: '午餐', category: '餐饮', note: '' };
  const second = { ...first, id: 'rule-b-notice', source: 'bank-copy', merchant: '消费午餐' };

  await Promise.all([repository().addNotificationEntry(first), repository().addNotificationEntry(second)]);

  assert.equal(rows.length, 1);
  assert.equal(transactions.length, 3);
  assert.ok(transactions.every((options) => options.transactionType === 'immediate'));
});
