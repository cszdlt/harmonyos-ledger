import test from 'node:test';
import assert from 'node:assert/strict';
import { createDefaultNotificationRules } from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';
import { loadPageMethods } from './helpers/page-methods.mjs';

const timestamp = new Date(2026, 9, 20, 12, 3).getTime();
const rule = { ...createDefaultNotificationRules()[0], isCreditCard: true };
const notice = { appName: '工商银行', bundleName: 'com.icbc.mobile',
  body: '尾号1234卡10月20日12:03支出（消费午餐）18.50元', receivedAt: timestamp };
function entry(id, overrides = {}) {
  return { id, happenedAt: timestamp, hasTime: true, amountFen: 1850, direction: 'expense',
    source: 'icbc', merchant: '午餐', category: '餐饮', note: '', accountingType: 'normal', ...overrides };
}
const serviceUrl = '../entry/src/main/ets/services/CreditHistory.ets';

test('通知唯一匹配可关联首次保留的支付平台来源，同来源候选仍需人工勾选', async () => {
  const { CreditHistoryMatcher, parseCreditHistoryFilter } = await import(serviceUrl);
  const entries = [entry('verified', { source: 'alipay', happenedAt: timestamp + 30000 }),
    entry('candidate', { happenedAt: timestamp + 3600000 }),
    entry('income', { direction: 'income' }), entry('repayment', { accountingType: 'credit-repayment',
      happenedAt: timestamp + 7200000 }), entry('already-credit', { accountingType: 'credit-card',
        happenedAt: timestamp + 10800000 })];
  const matcher = new CreditHistoryMatcher(entries, 'icbc');
  matcher.scan([notice, notice], { ...rule, enabled: false });
  const preview = matcher.preview(parseCreditHistoryFilter('', '', '', ''));
  assert.deepEqual(preview.candidates.map((item) => [item.entry.id, item.matched]),
    [['verified', true], ['candidate', false]]);
});

test('多条账目同分钟同金额时不自动关联，日期精度不足和规则未命中也不自动勾选', async () => {
  const { CreditHistoryMatcher, parseCreditHistoryFilter } = await import(serviceUrl);
  const matcher = new CreditHistoryMatcher([entry('one'), entry('two'),
    entry('date-only', { hasTime: false }), entry('wrong-amount', { amountFen: 1900 })], 'icbc');
  matcher.scan([notice, notice, { ...notice, appName: '其他', bundleName: 'other' }], rule);
  const preview = matcher.preview(parseCreditHistoryFilter('', '', '', ''));
  assert.equal(preview.ambiguousCount, 1);
  assert.ok(preview.candidates.every((item) => !item.matched));
});

test('手动来源、日期与关键词筛选使用账目自身信息，非法日期拒绝预览', async () => {
  const { CreditHistoryMatcher, parseCreditHistoryFilter } = await import(serviceUrl);
  const matcher = new CreditHistoryMatcher([entry('match', { source: 'manual', note: '尾号 1234' }),
    entry('wrong-source'), entry('next-day', { source: 'manual', happenedAt: timestamp + 86400000 }),
    entry('wrong-keyword', { source: 'manual' })], 'icbc');
  const preview = matcher.preview(parseCreditHistoryFilter('manual', '2026-10-20', '2026-10-20', '1234'));
  assert.deepEqual(preview.candidates.map((item) => item.entry.id), ['match']);
  assert.equal(preview.candidates[0].matched, false);
  assert.throws(() => parseCreditHistoryFilter('', '2026-02-30', '', ''));
  assert.throws(() => parseCreditHistoryFilter('', '2026-11-01', '2026-10-01', ''));
});

test('批量确认锁定重复提交，失败保留选择，成功清空预览避免再次保存', async () => {
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/ledger/CreditHistoryPage.ets', import.meta.url),
    ['applySelection', 'selectedEntries']);
  const page = new Page();
  page.previewData = { candidates: [{ entry: entry('selected'), matched: false }], ambiguousCount: 0 };
  page.selectedIds = ['selected'];
  let finish;
  let calls = 0;
  page.onApply = () => { calls++; return new Promise((resolve) => { finish = resolve; }); };
  const pending = page.applySelection();
  await page.applySelection();
  assert.equal(calls, 1);
  assert.equal(page.saving, true);
  finish(1);
  await pending;
  assert.equal(page.saving, false);
  assert.deepEqual(page.selectedIds, []);
  assert.equal(page.previewData.candidates.length, 0);
  page.previewData = { candidates: [{ entry: entry('selected'), matched: false }], ambiguousCount: 0 };
  page.selectedIds = ['selected'];
  page.onApply = async () => { throw new Error('写入失败'); };
  await page.applySelection();
  assert.deepEqual(page.selectedIds, ['selected']);
  assert.equal(page.saving, false);
});

async function previewPage() {
  const { CreditHistoryMatcher, parseCreditHistoryFilter } = await import(serviceUrl);
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/ledger/CreditHistoryPage.ets', import.meta.url),
    ['previewHistory', 'invalidatePreview'], { CreditHistoryMatcher, parseCreditHistoryFilter });
  const page = new Page();
  Object.assign(page, { rule: { name: rule.name, source: 'icbc', notificationRule: rule }, requestId: 0,
    sourceFilter: '', startDate: '', endDate: '', keyword: '', saving: false, loading: false });
  page.onListEntries = async () => [entry('verified')];
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  return page;
}

test('预览按游标扫描后续归档页，不在预览阶段写账本', async () => {
  const page = await previewPage();
  let calls = 0;
  page.onApply = async () => { throw new Error('预览不得写入'); };
  page.archiveRepository = { open: async () => {}, listPage: async (_filter, cursor) => {
    calls++;
    if (cursor === undefined) return { entries: [], nextCursor: { id: 1, eventTime: timestamp } };
    return { entries: [{ ...notice, title: '', deliveryTime: 0 }], nextCursor: undefined };
  } };
  await page.previewHistory();
  assert.equal(calls, 2);
  assert.equal(page.hasPreview, true);
  assert.deepEqual(page.selectedIds, ['verified']);
});

test('归档读取失败时保留人工筛选能力，取消中的请求不会覆盖后续预览状态', async () => {
  const page = await previewPage();
  page.archiveRepository = { open: async () => { throw new Error('归档不可用'); } };
  await page.previewHistory();
  assert.equal(page.hasPreview, true);
  assert.equal(page.previewData.candidates.length, 1);
  assert.equal(page.previewData.candidates[0].matched, false);
  assert.deepEqual(page.selectedIds, []);
  let finish;
  page.onListEntries = () => new Promise((resolve) => { finish = resolve; });
  const pending = page.previewHistory();
  page.invalidatePreview();
  finish([entry('cancelled')]);
  await pending;
  assert.equal(page.hasPreview, false);
  assert.equal(page.previewData.candidates.length, 0);
  assert.equal(page.loading, false);
});
