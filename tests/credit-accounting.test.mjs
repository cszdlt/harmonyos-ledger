import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLedgerHomeData } from '../entry/src/main/ets/services/LedgerHomeData.ets';
import { buildLedgerStatistics, statisticsRange } from '../entry/src/main/ets/services/LedgerStatistics.ets';
import { createDefaultNotificationRules, decodeNotificationRuleStore, parseNotificationEntry, validateNotificationRule }
  from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';
import { createDefaultOcrRules } from '../entry/src/main/ets/services/ocrRules/OcrRuleEngine.ets';
import { OcrImportCoordinator } from '../entry/src/main/ets/services/OcrImportCoordinator.ets';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { accountingTypeOf, formatDateOnly, formatDateTime, formatMoney, hasClockTime,
  makeId, parseAmountFen, parseDateTime } from '../entry/src/main/ets/model/LedgerModels.ets';
import { parseRuleImport } from '../entry/src/main/ets/services/ruleImport/RuleImportEngine.ets';
import { createNotificationRule } from '../entry/src/main/ets/services/ruleImport/NotificationRuleImportAdapter.ets';

const cursor = new Date(2026, 9, 20).getTime();
function entry(id, amountFen, direction, accountingType, month = 9) {
  return { id, amountFen, direction, accountingType, happenedAt: new Date(2026, month, 20, 12).getTime(),
    hasTime: true, source: 'manual', merchant: id, category: '购物', note: '' };
}

test('首页和详情使用同一现金口径，还款不进入支出、趋势和排行', () => {
  const entries = [entry('工资', 1000000, 'income'), entry('现金消费', 200000, 'expense'),
    entry('刷卡', 300000, 'expense', 'credit-card'), entry('还上期款', 100000, 'expense', 'credit-repayment'),
    entry('下期还款', 300000, 'expense', 'credit-repayment', 10)];
  const home = buildLedgerHomeData(entries, cursor, 15);
  const stats = buildLedgerStatistics(entries, statisticsRange('month', cursor, 0, 0, 15), 'month');
  assert.equal(home.incomeTotalFen, 1000000);
  assert.equal(home.expenseTotalFen, 500000);
  assert.equal(home.creditCardTotalFen, 300000);
  assert.equal(home.balanceTotalFen, 700000);
  assert.equal(home.dayGroups[0].expenseTotalFen, 500000);
  assert.equal(stats.expenseFen, 500000);
  assert.equal(stats.creditCardFen, 300000);
  assert.equal(stats.creditRepaymentFen, 100000);
  assert.equal(stats.netFen, 700000);
  assert.equal(stats.trend.reduce((sum, item) => sum + item.expenseFen, 0), 500000);
  assert.equal(stats.categories[0].amountFen, 500000);
  assert.ok(!stats.merchants.some((item) => item.key === '还上期款'));
  const next = buildLedgerHomeData(entries, new Date(2026, 10, 20).getTime(), 15);
  assert.equal(next.expenseTotalFen, 0);
  assert.equal(next.balanceTotalFen, -300000);
});

test('信用卡通知规则仅标记消费，规则保存后保留信用卡属性并拒绝错误类型', () => {
  const rule = { ...createDefaultNotificationRules()[0], isCreditCard: true };
  const input = { appName: '工商银行', bundleName: 'com.icbc.mobile',
    body: '尾号1234卡10月20日12:03支出（消费午餐）18.50元', receivedAt: cursor };
  const saved = decodeNotificationRuleStore(JSON.stringify({ version: 2, rules: [rule] })).rules;
  assert.equal(parseNotificationEntry(input, saved).accountingType, 'credit-card');
  const income = parseNotificationEntry({ ...input, body: input.body.replace('支出', '收入') }, saved);
  assert.ok(income.accountingType === undefined || income.accountingType === 'normal');
  assert.ok(validateNotificationRule({ ...rule, isCreditCard: 'true' }));
});

test('OCR 信用卡规则的草稿经复核后保留类型，更新已有分类也保留原类型', () => {
  const rule = { ...createDefaultOcrRules()[0], source: 'wallet', sourceName: '钱包',
    layoutStrategy: 'generic', record: { mode: 'row' }, isCreditCard: true,
    amountPattern: { pattern: '金额[:：]([\\d.]+)', groupIndex: 1 },
    datePattern: { pattern: '日期[:：](20\\d{2}-\\d{1,2}-\\d{1,2})', groupIndex: 1 },
    timePattern: undefined, directionPattern: { pattern: '(支出|收入)', groupIndex: 1 },
    merchantPattern: { pattern: '商户[:：]([^\\s]+)', groupIndex: 1 }, dateFormat: 'auto' };
  const text = '日期：2026-10-20 商户：午餐 支出 金额：18.50';
  const drafts = OcrImportCoordinator.parsePage([{ text, left: 0, right: 500, top: 0, bottom: 20,
    centerY: 10, height: 20 }], 'wallet', [], [rule]);
  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].accountingType, 'credit-card');
  const plan = OcrImportCoordinator.prepareConfirmation(drafts, []);
  assert.equal(plan.validationErrors.length, 0);
  assert.equal(plan.additions[0].accountingType, 'credit-card');
  const existing = { ...plan.additions[0], hasTime: true, category: '其他', accountingType: 'credit-repayment' };
  const timedDraft = { ...drafts[0], dateText: '2026-10-20 00:00', hasTime: true, category: '餐饮' };
  assert.equal(OcrImportCoordinator.prepareConfirmation([timedDraft], [existing])
    .categoryUpdates[0].accountingType, 'credit-repayment');
});

test('长按标记保存到仓库并刷新；保存失败时保留操作面板', async () => {
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url),
    ['setPendingAccountingType']);
  const page = new Page();
  const original = entry('还款', 50000, 'expense');
  let saved;
  page.pendingDeleteId = original.id;
  page.findEntry = () => original;
  page.repository = { updateEntry: async (value) => { saved = value; } };
  page.reloadEntries = async () => {};
  page.showToast = () => {};
  await page.setPendingAccountingType('credit-repayment');
  assert.equal(saved.accountingType, 'credit-repayment');
  assert.equal(saved.category, '购物');
  assert.equal(page.pendingDeleteId, '');
  page.pendingDeleteId = original.id;
  page.repository.updateEntry = async () => { throw new Error('写入失败'); };
  await page.setPendingAccountingType('credit-repayment');
  assert.equal(page.pendingDeleteId, original.id);
});

test('编辑还款的日期或摘要后仍保留还款类型，收入不能使用信用卡类型', async () => {
  const Editor = loadPageMethods(new URL('../entry/src/main/ets/pages/ledger/LedgerEditorPage.ets', import.meta.url),
    ['startSessionForRevision', 'saveEditor'], { accountingTypeOf, formatDateOnly, formatDateTime,
      hasClockTime, makeId, parseAmountFen, parseDateTime });
  const editor = new Editor();
  editor.sessionRevision = 1;
  editor.editingEntry = entry('还款', 20000, 'expense', 'credit-repayment');
  editor.startSessionForRevision();
  editor.formMerchant = '修改后的摘要';
  editor.onBack = () => {};
  let saved;
  editor.onSave = async (value) => { saved = value; return true; };
  await editor.saveEditor();
  assert.equal(saved.accountingType, 'credit-repayment');
  assert.equal(saved.merchant, '修改后的摘要');
  assert.equal(accountingTypeOf({ ...saved, direction: 'income' }), 'normal');
});

test('规则经列表和编辑器复制后仍把新的支出识别为信用卡消费', () => {
  const rule = { ...createDefaultNotificationRules()[0], isCreditCard: true };
  for (const path of ['pages/notifications/NotificationRuleSettingsView.ets',
    'components/notifications/NotificationRuleEditor.ets']) {
    const Page = loadPageMethods(new URL('../entry/src/main/ets/' + path, import.meta.url), ['copyRule']);
    const copied = new Page().copyRule(rule);
    const parsed = parseNotificationEntry({ appName: '工商银行', bundleName: 'com.icbc.mobile',
      body: '尾号1234卡10月20日12:03支出（消费午餐）18.50元', receivedAt: cursor }, [copied]);
    assert.equal(parsed.accountingType, 'credit-card');
  }
});

test('导入规则的信用卡标记进入实际解析流程，错误的标记类型被拒绝', () => {
  const rule = { name: '信用卡示例', isCreditCard: true, sourceKeywords: ['CreditBank'],
    bodyPattern: '(?<direction>收入|支出)(?<amount>[\\d.]+)元', incomeText: '收入', expenseText: '支出',
    dateFormat: '', dateStrategy: 'delivery-time', defaultMerchant: '午餐', defaultCategory: '餐饮' };
  const payload = { schemaVersion: 1, kind: 'notification', rule, examples: [] };
  const imported = parseRuleImport(JSON.stringify(payload), 'notification');
  assert.equal(imported.valid, true);
  const parsed = parseNotificationEntry({ appName: 'CreditBank', bundleName: 'bank',
    body: '支出18.50元', receivedAt: cursor }, [createNotificationRule(imported.rule, [])]);
  assert.equal(parsed.accountingType, 'credit-card');
  assert.equal(parseRuleImport(JSON.stringify({ ...payload, rule: { ...rule, isCreditCard: 'true' } }),
    'notification').valid, false);
});

test('现金结余为负时金额显示正确', () => {
  assert.equal(formatMoney(-150), '-¥1.50');
  assert.equal(formatMoney(150), '¥1.50');
});
