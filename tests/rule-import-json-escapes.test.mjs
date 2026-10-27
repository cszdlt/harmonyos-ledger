import test from 'node:test';
import assert from 'node:assert/strict';
import { parseRuleImport } from '../entry/src/main/ets/services/ruleImport/RuleImportEngine.ets';
import { createNotificationRule, previewNotificationRule } from '../entry/src/main/ets/services/ruleImport/NotificationRuleImportAdapter.ets';

function notification(bodyPattern) {
  return JSON.stringify({ schemaVersion: 1, kind: 'notification', rule: {
    name: '示例规则', sourceKeywords: ['ExamplePay'], bodyPattern,
    incomeText: '收入', expenseText: '支出', dateFormat: '', dateStrategy: 'delivery-time',
    defaultMerchant: '示例商户', defaultCategory: '其他'
  }, examples: [{ input: '支出 12.30元\n详情："示例"\\原文', expected: { amount: '12.30', direction: 'expense' } }] });
}

function barePattern(pattern) {
  return notification('PLACEHOLDER').replace('PLACEHOLDER', () => pattern);
}

test('通知 JSON 接受单反斜杠的数字、空白及小数点表达式，并可由正式解析器识别金额', () => {
  const parsed = parseRuleImport(barePattern(String.raw`(?<direction>收入|支出)\s*(?<amount>\d+\.\d{2})元`), 'notification');
  assert.equal(parsed.valid, true);
  assert.equal(parsed.rule.bodyPattern, String.raw`(?<direction>收入|支出)\s*(?<amount>\d+\.\d{2})元`);
  const preview = previewNotificationRule(createNotificationRule(parsed.rule, []), parsed.examples);
  assert.equal(preview[0].matched, true);
  assert.equal(parsed.examples[0].input, '支出 12.30元\n详情："示例"\\原文');
});

test('已合法转义的 JSON 完整保留，含反斜杠、引号、换行和 Unicode', () => {
  const pattern = String.raw`(?<direction>收入|支出)\s*(?<amount>\d+\.\d{2})元`;
  const text = notification(pattern).replace('示例商户', String.raw`\u793a\u4f8b商户`);
  const parsed = parseRuleImport(text, 'notification');
  assert.equal(parsed.valid, true);
  assert.equal(parsed.rule.bodyPattern, pattern);
  assert.equal(parsed.rule.defaultMerchant, '示例商户');
  assert.equal(parsed.examples[0].input, '支出 12.30元\n详情："示例"\\原文');
});

test('同一正则内混合单反斜杠与合法 JSON 转义时只修复非法转义', () => {
  const parsed = parseRuleImport(barePattern(String.raw`(?<direction>收入|支出)\\s*(?<amount>\d+\.\d{2})\n\t\b\u5143`), 'notification');
  assert.equal(parsed.valid, true);
  assert.equal(parsed.rule.bodyPattern, '(?<direction>收入|支出)\\s*(?<amount>\\d+\\.\\d{2})\n\t\b元');
});

test('OCR 的来源、锚点、字段、排除条件及分类映射均兼容单反斜杠', () => {
  const parsed = parseRuleImport(String.raw`{
    "schemaVersion": 1, "kind": "ocr",
    "rule": {
      "name": "示例钱包", "source": { "id": "example", "name": "钱包", "patterns": ["钱包\s*账单"] },
      "record": { "mode": "anchor", "anchor": "交易\d+" },
      "fields": { "amount": "(\d+\.\d{2})", "date": "(\d{4}-\d{2}-\d{2})",
        "time": "(\d{2}:\d{2})", "merchant": "(\S+)", "direction": "(支出|收入)", "category": "(\w+)" },
      "incomeKeywords": ["收入"], "expenseKeywords": ["支出"], "defaultCategory": "其他",
      "failurePatterns": ["失败\s*"], "refundPatterns": ["退款\d*"], "summaryPatterns": ["合计\s*"],
      "categoryMappings": [{ "pattern": "午餐\s*", "category": "餐饮" }]
    }
  }`, 'ocr');
  assert.equal(parsed.valid, true);
  assert.equal(parsed.rule.source.patterns[0], String.raw`钱包\s*账单`);
  assert.equal(parsed.rule.record.anchor, String.raw`交易\d+`);
  assert.equal(parsed.rule.fields.amount, String.raw`(\d+\.\d{2})`);
  assert.equal(parsed.rule.fields.date, String.raw`(\d{4}-\d{2}-\d{2})`);
  assert.equal(parsed.rule.fields.time, String.raw`(\d{2}:\d{2})`);
  assert.equal(parsed.rule.fields.merchant, String.raw`(\S+)`);
  assert.equal(parsed.rule.fields.category, String.raw`(\w+)`);
  assert.equal(parsed.rule.failurePatterns[0], String.raw`失败\s*`);
  assert.equal(parsed.rule.refundPatterns[0], String.raw`退款\d*`);
  assert.equal(parsed.rule.summaryPatterns[0], String.raw`合计\s*`);
  assert.equal(parsed.rule.categoryMappings[0].pattern, String.raw`午餐\s*`);
});

test('不修复样例、商户、关键词或同名的嵌套字段中的非法转义', () => {
  const base = barePattern(String.raw`(?<direction>收入|支出)\s*(?<amount>\d+)`);
  for (const text of [
    base.replace('示例商户', () => String.raw`商户\d`),
    base.replace('ExamplePay', () => String.raw`Example\s`),
    base.replace('支出 12.30元', () => String.raw`样例\d`),
    base.slice(0, -1) + String.raw`, "bodyPattern": "\d"}`,
    base.slice(0, -1) + String.raw`, "extra": { "rule": { "bodyPattern": "\d" } }}`,
    base.slice(0, -1) + String.raw`, "rule.bodyPattern": "\d"}`
  ]) {
    assert.equal(parseRuleImport(text, 'notification').valid, false, text);
  }
});

test('兼容转义后仍拒绝损坏 JSON、错误正则和缺失必需捕获', () => {
  const base = barePattern(String.raw`(?<direction>收入|支出)\s*(?<amount>\d+)`);
  for (const text of [base.slice(0, -1), base.replace('"schemaVersion":1,', '"schemaVersion":1,,')]) {
    assert.equal(parseRuleImport(text, 'notification').valid, false);
  }
  const malformed = parseRuleImport(barePattern(String.raw`(?<direction>支出)\d+[`), 'notification');
  assert.equal(malformed.valid, false);
  assert.ok(malformed.issues.some(issue => issue.field === 'rule.bodyPattern'));
});
