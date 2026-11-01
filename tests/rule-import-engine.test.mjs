import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildNotificationRulePrompt,
  buildOcrRulePrompt,
  parseRuleImport
} from '../entry/src/main/ets/services/ruleImport/RuleImportEngine.ets';

function ocrRule(overrides = {}) {
  return {
    name: '示例钱包',
    source: { id: 'example-wallet', name: '示例钱包', patterns: ['Example Wallet'] },
    record: { mode: 'row' },
    fields: {
      amount: '金额[:：]\\s*([+-]?\\s*[¥￥]?\\s*[\\d,.]+)',
      date: '日期[:：]\\s*((?:20\\d{2}[-/.年])?\\d{1,2}[-/.月]\\d{1,2}日?)',
      direction: '(收入|支出)',
      merchant: '商户[:：]\\s*(.+)'
    },
    incomeKeywords: ['收入'],
    expenseKeywords: ['支出'],
    defaultCategory: '其他',
    ...overrides
  };
}

function notificationRule(overrides = {}) {
  return {
    name: '示例支付',
    sourceKeywords: ['ExamplePay'],
    bodyPattern: '(?<direction>收入|支出).*?(?<amount>[¥￥]?[\\d,.]+)(?:元)?',
    incomeText: '收入',
    expenseText: '支出',
    dateFormat: '',
    dateStrategy: 'delivery-time',
    defaultMerchant: '示例支付',
    defaultCategory: '其他',
    ...overrides
  };
}

function envelope(kind, rule, examples = []) {
  return JSON.stringify({ schemaVersion: 1, kind, rule, examples });
}

test('parses OCR row rules and keeps sample expectations transiently available to the preview adapter', () => {
  const parsed = parseRuleImport(envelope('ocr', ocrRule(), [
    { input: 'Example Wallet\n日期：2026-10-03\n商户：午餐\n金额：1,031.10 支出',
      expected: { amount: '1,031.10', direction: 'expense' } }
  ]), 'ocr');

  assert.equal(parsed.valid, true);
  assert.equal(parsed.rule.source.id, 'example-wallet');
  assert.deepEqual(parsed.examples[0].expected, { amount: '1,031.10', direction: 'expense' });
});

test('requires an anchor expression when OCR records use anchored blocks', () => {
  const parsed = parseRuleImport(envelope('ocr', ocrRule({ record: { mode: 'anchor' } })), 'ocr');

  assert.equal(parsed.valid, false);
  assert.ok(parsed.issues.some((issue) => issue.field === 'rule.record.anchor'));
});

test('rejects malformed JSON, unsupported versions, and imports of the wrong rule kind', () => {
  const malformed = parseRuleImport('{', 'ocr');
  const futureVersion = parseRuleImport(JSON.stringify({ schemaVersion: 2, kind: 'ocr', rule: ocrRule() }), 'ocr');
  const wrongKind = parseRuleImport(envelope('notification', notificationRule()), 'ocr');

  assert.equal(malformed.valid, false);
  assert.ok(malformed.issues.some((issue) => issue.field === '$'));
  assert.equal(futureVersion.valid, false);
  assert.ok(futureVersion.issues.some((issue) => issue.field === 'schemaVersion'));
  assert.equal(wrongKind.valid, false);
  assert.ok(wrongKind.issues.some((issue) => issue.field === 'kind'));
});

test('rejects invalid OCR expressions, missing capture 1, and out-of-range columns', () => {
  const invalidRegex = parseRuleImport(envelope('ocr', ocrRule({
    fields: { ...ocrRule().fields, amount: '(' }
  })), 'ocr');
  const missingCapture = parseRuleImport(envelope('ocr', ocrRule({
    fields: { ...ocrRule().fields, date: '2026-10-03' }
  })), 'ocr');
  const invalidColumn = parseRuleImport(envelope('ocr', ocrRule({
    columns: { amount: { left: 0.9, right: 1.1 } }
  })), 'ocr');

  assert.ok(invalidRegex.issues.some((issue) => issue.field === 'rule.fields.amount'));
  assert.ok(missingCapture.issues.some((issue) => issue.field === 'rule.fields.date'));
  assert.ok(invalidColumn.issues.some((issue) => issue.field === 'rule.columns.amount'));
});

test('requires unique semantic amount and direction notification captures', () => {
  const missingAmount = parseRuleImport(envelope('notification', notificationRule({
    bodyPattern: '(?<direction>收入|支出).*?([\\d,.]+)'
  })), 'notification');
  const unknownCapture = parseRuleImport(envelope('notification', notificationRule({
    bodyPattern: '(?<direction>收入|支出).*?(?<amount>[\\d,.]+)(?<reference>\\w+)'
  })), 'notification');
  const unnamedCapture = parseRuleImport(envelope('notification', notificationRule({
    bodyPattern: '(收入|支出).*?(?<amount>[\\d,.]+)'
  })), 'notification');

  assert.equal(missingAmount.valid, false);
  assert.ok(missingAmount.issues.some((issue) => issue.field === 'rule.bodyPattern'));
  assert.equal(unknownCapture.valid, false);
  assert.ok(unknownCapture.issues.some((issue) => issue.field === 'rule.bodyPattern'));
  assert.equal(unnamedCapture.valid, false);
  assert.ok(unnamedCapture.issues.some((issue) => issue.field === 'rule.bodyPattern'));
});

test('notification import accepts valid exclusion patterns and rejects invalid ones', () => {
  const accepted = parseRuleImport(envelope('notification', notificationRule({
    excludeBodyPatterns: [String.raw`系统摘要\s*[:：]`]
  })), 'notification');
  assert.equal(accepted.valid, true);
  assert.deepEqual(accepted.rule.excludeBodyPatterns, [String.raw`系统摘要\s*[:：]`]);

  const rejected = parseRuleImport(envelope('notification', notificationRule({ excludeBodyPatterns: ['['] })), 'notification');
  assert.equal(rejected.valid, false);
  assert.ok(rejected.issues.some((issue) => issue.field === 'rule.excludeBodyPatterns[0]'));
});

test('builds separate OCR and notification prompts with the compact schema rather than runtime group indexes', () => {
  const ocrPrompt = buildOcrRulePrompt();
  const notificationPrompt = buildNotificationRulePrompt();

  assert.notEqual(ocrPrompt, notificationPrompt);
  assert.match(ocrPrompt, /"schemaVersion"\s*:\s*1/);
  assert.match(ocrPrompt, /record\.mode.*anchor/);
  assert.match(notificationPrompt, /\?<amount>/);
  assert.match(notificationPrompt, /\?<direction>/);
  assert.doesNotMatch(notificationPrompt, /amountGroup|directionGroup|groupIndex/);
});

test('通知导入拒绝缺少年月日的日期格式并允许推断年份', () => {
  const base = notificationRule({
    bodyPattern: String.raw`(?<date>.+) (?<direction>收入|支出) (?<amount>\d+)`,
    dateStrategy: 'format'
  });
  for (const dateFormat of ['MM-dd HH:mm', 'yyyy-dd HH:mm', 'yyyy-MM HH:mm', 'HH:mm']) {
    const parsed = parseRuleImport(envelope('notification', { ...base, dateFormat }), 'notification');
    assert.equal(parsed.valid, false, dateFormat);
    assert.ok(parsed.issues.some((issue) => issue.field === 'rule.dateFormat'));
  }
  const inferred = parseRuleImport(envelope('notification', {
    ...base, dateStrategy: 'infer-year', dateFormat: 'M月d日 HH:mm'
  }), 'notification');
  assert.equal(inferred.valid, true);
});
