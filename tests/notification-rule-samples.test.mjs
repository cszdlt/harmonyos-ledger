import test from 'node:test';
import assert from 'node:assert/strict';
import * as samples from '../entry/src/main/ets/services/ruleImport/NotificationRuleSamples.ets';
import { sampleFromNotification } from '../entry/src/main/ets/services/ruleImport/RuleImportGuide.ets';
import { createNotificationRule } from '../entry/src/main/ets/services/ruleImport/NotificationRuleImportAdapter.ets';

const timestamp = new Date(2026, 10, 1, 8, 34).getTime();
const description = {
  name: '样例支付', sourceKeywords: ['example.pay'],
  bodyPattern: String.raw`(?<direction>支出|收入)\s*(?<amount>(?:\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?))元`,
  incomeText: '收入', expenseText: '支出', dateFormat: '', dateStrategy: 'delivery-time',
  defaultMerchant: '默认商户', defaultCategory: '其他'
};
function sample(body = '支出12.30元', amount = '12.30', overrides = {}) {
  return { ...sampleFromNotification({ bundleName: 'example.pay', appName: '样例支付', title: '交易提醒', body,
    deliveryTime: timestamp, receivedAt: timestamp + 5000 }), amount, direction: 'expense', ...overrides };
}

test('批量材料包含每条人工确认样例、真实投递时间和金额通配要求', () => {
  const prompt = samples.buildNotificationSamplesPrompt([sample(), sample('支出98.76元', '98.76')]);
  for (const text of ['12.30', '98.76', 'example.pay', 'deliveryTime', '所有', '不能写死', '千分位']) {
    assert.ok(prompt.includes(text), text);
  }
});

test('逐条确认且同一包名，任一无效样例不能生成AI材料', () => {
  assert.match(samples.validateNotificationSamples([]), /选择|提供/);
  assert.match(samples.validateNotificationSamples([sample(), sample('', '')]), /样例 2/);
  assert.match(samples.validateNotificationSamples([sample(), sample('支出1元', '1', { source: 'other.pay' })]), /同一/);
});

test('全部原始通知必须由新规则命中，不能由旧规则或AI自带样例替代', () => {
  const rule = createNotificationRule(description, []);
  const previews = samples.previewNotificationSamples(rule, [sample(), sample('消费98.76元', '98.76')], [rule]);
  assert.equal(previews[0].matched, true);
  assert.equal(previews[1].matched, false);
  assert.equal(samples.previewNotificationSamples(rule, [sample('支出12.30元', '12.30', { source: 'other.pay' })])[0].matched, false);
});

test('能通配整数、小数和千分位金额才通过，每种通知模板分别验证', () => {
  const rule = createNotificationRule(description, []);
  const originals = [sample(), sample('尾号1234 余额12.30元 支出1,234.56元', '1234.56')];
  const before = structuredClone(originals);
  const previews = samples.previewNotificationSamples(rule, originals);
  assert.ok(previews.every(preview => preview.matched));
  assert.match(previews[0].message, /金额泛化.*通过/);
  assert.deepEqual(originals, before);
});

test('写死样例金额、固定位数或只支持一种分支金额的规则不能通过', () => {
  const patterns = [
    '(?<direction>支出|收入)(?<amount>12\\.30|98\\.76)元',
    '(?<direction>支出|收入)(?<amount>\\d{2}\\.\\d{2})元',
    '(?<direction>支出|收入)(?<amount>\\d+(?:\\.\\d{1,2})?)元'
  ];
  for (const bodyPattern of patterns) {
    const preview = samples.previewNotificationSamples(createNotificationRule({ ...description, bodyPattern }, []), [sample()])[0];
    assert.equal(preview.matched, false, bodyPattern);
    assert.match(preview.message, /金额泛化.*未通过/);
  }
});

test('金额泛化不改变卡号、日期和余额等其他数字', () => {
  const bodyPattern = String.raw`尾号12\s+余额12\.30元\s+(?<direction>支出|收入)(?<amount>(?:\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?))元`;
  const rule = createNotificationRule({ ...description, bodyPattern }, []);
  const body = '尾号12 余额12.30元 支出12.30元';
  assert.equal(samples.previewNotificationSamples(rule, [sample(body, '12.30', {
    amountLocation: 'input:' + body.lastIndexOf('12.30')
  })])[0].matched, true);
});

test('交易金额与余额相同时必须确认位置，提取余额的规则不能借余额替换通过', () => {
  const body = '支出12.30元，余额12.30元';
  const ambiguous = sample(body);
  assert.match(samples.validateNotificationSamples([ambiguous]), /金额位置/);
  const rule = createNotificationRule({ ...description,
    bodyPattern: '(?<direction>支出)12\\.30元，余额(?<amount>[\\d,.]+)元' }, []);
  const chosen = { ...ambiguous, amountLocation: 'input:' + body.indexOf('12.30') };
  assert.equal(samples.previewNotificationSamples(rule, [ambiguous])[0].matched, false);
  assert.equal(samples.previewNotificationSamples(rule, [chosen])[0].matched, false);
});

test('排除样例无需填写账目字段，但至少要保留一条包含样例', () => {
  const excluded = sample('系统摘要：支出98.76元', '', { excluded: true, date: '', direction: '' });
  assert.equal(samples.validateNotificationSamples([sample(), excluded]), '');
  assert.match(samples.validateNotificationSamples([excluded]), /包含/);
});

test('批量提示词标明排除样例并要求生成排除正文正则', () => {
  const prompt = samples.buildNotificationSamplesPrompt([
    sample(), sample('系统摘要：支出98.76元', '', { excluded: true, date: '', direction: '' })
  ]);
  assert.match(prompt, /excludeBodyPatterns/);
  assert.match(prompt, /"excluded": true/);
  assert.match(prompt, /排除样例/);
});

test('排除样例的本地预览要求命中排除正则且不会生成账目', () => {
  const excluded = sample('系统摘要：支出98.76元', '', { excluded: true, date: '', direction: '' });
  const rule = createNotificationRule({ ...description, excludeBodyPatterns: ['系统摘要'] }, []);
  const previews = samples.previewNotificationSamples(rule, [sample(), excluded]);
  assert.deepEqual(previews.map(preview => preview.matched), [true, true]);
  assert.equal(previews[1].actual, undefined);
  assert.match(previews[1].message, /排除/);
});

test('排除样例有填写交易金额时也要验证排除正则支持金额变化', () => {
  const excluded = sample('系统摘要：支出98.76元', '98.76', { excluded: true, date: '', direction: '' });
  const genericPattern = String.raw`系统摘要：支出(?:\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)元`;
  const fixedPattern = String.raw`系统摘要：支出98\.76元`;
  const generic = createNotificationRule({ ...description, excludeBodyPatterns: [genericPattern] }, []);
  const fixed = createNotificationRule({ ...description, excludeBodyPatterns: [fixedPattern] }, []);

  assert.equal(samples.previewNotificationSamples(generic, [sample(), excluded])[1].matched, true);
  const fixedPreview = samples.previewNotificationSamples(fixed, [sample(), excluded])[1];
  assert.equal(fixedPreview.matched, false);
  assert.match(fixedPreview.message, /金额泛化/);
});
