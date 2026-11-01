import test from 'node:test';
import assert from 'node:assert/strict';
import * as engine from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';

const timestamp = new Date(2026, 10, 1, 8, 34, 45).getTime();
const body = '尾号1234卡11月1日05:36工商银行支出(测试商户)1,234.56元。';
function rule(overrides = {}) {
  return {
    id: 'test', name: '验证规则', enabled: true, sourceKeywords: ['icbc'],
    semanticCaptures: true,
    bodyPattern: String.raw`尾号\s*\d{4}\s*卡\s*\d{1,2}月\d{1,2}日\s*\d{1,2}:\d{2}\s*工商银行\s*(?<direction>支出|收入)\s*[（(](?<merchant>[^）)]+)[）)]\s*(?<amount>[\d,.]+)元`,
    incomeText: '收入', expenseText: '支出', dateFormat: '', dateStrategy: 'delivery-time',
    defaultMerchant: '默认商户', defaultCategory: '其他', categoryMappings: [],
    merchantPrefixToStrip: '', noteTemplate: '', ...overrides
  };
}

test('正文验证复用金额、方向、商户与投递时间解析，且不修改规则', () => {
  const candidate = rule({ enabled: false, requiredTitle: '固定标题' });
  const before = structuredClone(candidate);
  const result = engine.validateNotificationBody(candidate, body, timestamp);
  assert.equal(result.entry?.amountFen, 123456);
  assert.equal(result.entry?.direction, 'expense');
  assert.equal(result.entry?.merchant, '测试商户');
  assert.equal(result.entry?.category, '其他');
  assert.equal(result.entry?.happenedAt, new Date(2026, 10, 1, 8, 34).getTime());
  assert.deepEqual(candidate, before);
});

test('正文为空或正则未匹配时给出不同原因', () => {
  assert.match(engine.validateNotificationBody(rule(), '  ', timestamp).message, /输入.*正文/);
  const result = engine.validateNotificationBody(rule({ bodyPattern: rule().bodyPattern.replaceAll('\\s*', '\\s') }), body, timestamp);
  assert.equal(result.entry, undefined);
  assert.match(result.message, /正则未匹配/);
});

test('正则或捕获配置错误时返回正式规则校验信息', () => {
  for (const bodyPattern of ['(', '(收入|支出)(?<amount>\\d+)']) {
    const candidate = rule({ bodyPattern });
    const result = engine.validateNotificationBody(candidate, body, timestamp);
    assert.equal(result.entry, undefined);
    assert.equal(result.message, engine.validateNotificationRule(candidate).message);
  }
});

test('匹配成功但方向或金额无效时不能报告成功', () => {
  for (const overrides of [{ expenseText: '消费' }, {}]) {
    const text = overrides.expenseText ? body : body.replace('1,234.56', '0');
    const result = engine.validateNotificationBody(rule(overrides), text, timestamp);
    assert.equal(result.entry, undefined);
    assert.match(result.message, /已匹配正文.*无法解析/);
  }
});

test('未捕获商户时显示默认商户，旧数字捕获规则仍可验证', () => {
  const result = engine.validateNotificationBody(rule({
    semanticCaptures: false, bodyPattern: '(收入|支出)([\\d.]+)元', directionGroup: 1, amountGroup: 2
  }), '收入12.30元', timestamp);
  assert.equal(result.entry?.amountFen, 1230);
  assert.equal(result.entry?.direction, 'income');
  assert.equal(result.entry?.merchant, '默认商户');
});

test('正文日期策略解析交易时间并拒绝无效日期', () => {
  const candidate = rule({
    bodyPattern: '(?<date>\\d{1,2}月\\d{1,2}日\\d{2}:\\d{2})(?<direction>收入|支出)(?<amount>\\d+)元',
    dateStrategy: 'infer-year', dateFormat: 'M月d日HH:mm'
  });
  assert.equal(engine.validateNotificationBody(candidate, '11月1日05:36支出12元', timestamp).entry?.happenedAt,
    new Date(2026, 10, 1, 5, 36).getTime());
  assert.equal(engine.validateNotificationBody(candidate, '2月30日05:36支出12元', timestamp).entry, undefined);
});

test('失败与撤销通知沿用正式引擎的排除规则', () => {
  const result = engine.validateNotificationBody(rule(), body + '交易失败', timestamp);
  assert.equal(result.entry, undefined);
  assert.match(result.message, /失败.*撤销/);
});

test('手动验证正文命中规则排除条件时明确提示不会入账', () => {
  const result = engine.validateNotificationBody(rule({ excludeBodyPatterns: ['测试商户'] }), body, timestamp);
  assert.equal(result.entry, undefined);
  assert.match(result.message, /命中排除规则.*不会入账/);
});
