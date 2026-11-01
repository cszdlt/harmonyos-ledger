import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  createDefaultNotificationRules,
  decodeNotificationRuleStore,
  validateNotificationRule,
  parseNotificationEntry
} from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';
import { parseAmountFen } from '../entry/src/main/ets/services/notificationRules/AmountParser.ets';

function customRule(overrides = {}) {
  return {
    id: 'custom-1',
    name: '示例规则',
    enabled: true,
    sourceKeywords: ['MockPay'],
    bodyPattern: '^REF:(\\w+):(收入|支出):([\\d.]+):(.+)$',
    amountGroup: 3,
    directionGroup: 2,
    incomeText: '收入',
    expenseText: '支出',
    dateFormat: '',
    dateStrategy: 'delivery-time',
    defaultMerchant: '未知商户',
    defaultCategory: '其他',
    categoryMappings: [],
    merchantPrefixToStrip: '',
    noteTemplate: '参考号 {{1}}',
    ...overrides
  };
}

function input(overrides = {}) {
  return {
    appName: '工商银行',
    bundleName: 'com.icbc.mobile',
    body: '尾号1234卡3月5日12:03支出（消费午餐）18.50元',
    receivedAt: new Date(2026, 2, 6, 8, 0).getTime(),
    ...overrides
  };
}

function visibleEntry(entry) {
  if (entry === undefined) return undefined;
  return {
    happenedAt: entry.happenedAt,
    hasTime: entry.hasTime,
    amountFen: entry.amountFen,
    direction: entry.direction,
    source: entry.source,
    merchant: entry.merchant,
    category: entry.category,
    note: entry.note
  };
}

test('ICBC default rule preserves amount, local transaction time, merchant, category and note', () => {
  const entry = parseNotificationEntry(input(), createDefaultNotificationRules());
  assert.deepEqual(visibleEntry(entry), {
    happenedAt: new Date(2026, 2, 5, 12, 3).getTime(),
    hasTime: true,
    amountFen: 1850,
    direction: 'expense',
    source: 'icbc',
    merchant: '午餐',
    category: '消费',
    note: '尾号1234卡 · 动账通知'
  });
});

test('ICBC default rule accepts a one-digit transaction hour', () => {
  const entry = parseNotificationEntry(input({
    body: '尾号1234卡3月5日9:03支出（消费午餐）18.50元'
  }), createDefaultNotificationRules());
  assert.equal(entry?.happenedAt, new Date(2026, 2, 5, 9, 3).getTime());
  assert.equal(entry?.source, 'icbc');
});

test('ICBC accepts optional whitespace before the time and keeps ordered transaction categories', () => {
  const rules = createDefaultNotificationRules();
  const atm = parseNotificationEntry(input({ body: '尾号1234卡 3月5日 12:03支出（ATM取款）100元' }), rules);
  const loan = parseNotificationEntry(input({ body: '尾号1234卡3月5日12:03支出（贷款本息）100元' }), rules);
  assert.equal(atm?.category, '取现');
  assert.equal(atm?.merchant, 'ATM取款');
  assert.equal(loan?.category, '贷款');
});

test('CITIC default rule uses delivery time and the fallback merchant and note', () => {
  const deliveryTime = new Date(2026, 0, 2, 10, 12, 38).getTime();
  const entry = parseNotificationEntry(input({
    appName: '中信银行',
    bundleName: 'com.citic.bank',
    body: '尾号123456的账户支出￥18.50元',
    receivedAt: new Date(2026, 0, 3, 9, 0).getTime(),
    deliveryTime
  }), createDefaultNotificationRules());
  assert.deepEqual(visibleEntry(entry), {
    happenedAt: new Date(2026, 0, 2, 10, 12).getTime(),
    hasTime: true,
    amountFen: 1850,
    direction: 'expense',
    source: 'citic',
    merchant: '中信银行账户',
    category: '其他',
    note: '尾号123456账户 · 通知未提供商户'
  });
});

test('CITIC falls back to received time when delivery time is invalid', () => {
  const receivedAt = new Date(2026, 0, 3, 9, 7, 45).getTime();
  const entry = parseNotificationEntry(input({
    appName: '中信银行', bundleName: 'com.citic.bank',
    body: '尾号123456的账户支出￥18.50元', receivedAt, deliveryTime: 0
  }), createDefaultNotificationRules());
  assert.equal(entry?.happenedAt, new Date(2026, 0, 3, 9, 7).getTime());
});

test('custom capture mappings create a ledger entry whose source is the rule name', () => {
  const rule = customRule({
    merchantGroup: 4,
    categoryGroup: 4,
    merchantPrefixToStrip: '消费',
    categoryMappings: [{ text: '消费', matchMode: 'startsWith', category: '餐饮' }],
    noteTemplate: '流水 {{1}}'
  });
  const entry = parseNotificationEntry(input({
    appName: 'MockPay', bundleName: 'example.mock',
    body: 'REF:AB12:支出:18.50:消费咖啡店', deliveryTime: new Date(2026, 1, 2, 3, 4, 5).getTime()
  }), [rule]);
  assert.deepEqual(visibleEntry(entry), {
    happenedAt: new Date(2026, 1, 2, 3, 4).getTime(),
    hasTime: true,
    amountFen: 1850,
    direction: 'expense',
    source: '示例规则',
    merchant: '咖啡店',
    category: '餐饮',
    note: '流水 AB12'
  });
});

test('custom optional capture falls back to the merchant and expands a missing note capture to empty text', () => {
  const rule = customRule({
    bodyPattern: '^REF:(\\w+)(?: MERCHANT:([^ ]+))?:(收入|支出):([\\d.]+)$',
    amountGroup: 4,
    directionGroup: 3,
    merchantGroup: 2,
    noteTemplate: '参考 {{1}} {{2}}'
  });
  const entry = parseNotificationEntry(input({
    appName: 'MockPay', body: 'REF:AB12:支出:18.50'
  }), [rule]);
  assert.equal(entry?.merchant, '未知商户');
  assert.equal(entry?.note, '参考 AB12 ');
});

test('the first source and body match owns the notice even when its fields are invalid', () => {
  const first = customRule({ id: 'first', name: '优先规则', amountGroup: 9 });
  const second = customRule({ id: 'second', name: '备用规则' });
  const result = parseNotificationEntry(input({
    appName: 'MockPay', body: 'REF:AB12:支出:18.50:商户'
  }), [first, second]);
  assert.equal(result, undefined);
});

test('disabled and source-mismatched rules do not match', () => {
  const rule = customRule({ enabled: false });
  assert.equal(parseNotificationEntry(input({ appName: 'MockPay' }), [rule]), undefined);
  assert.equal(parseNotificationEntry(input({ appName: 'Other' }), [customRule()]), undefined);
});

test('blocked failure, cancellation and reversal notices never create entries', () => {
  for (const blocked of ['交易失败', '扣款失败', '交易取消', '已撤销']) {
    assert.equal(parseNotificationEntry(input({ body: `尾号1234卡3月5日12:03支出（消费午餐）18.50元 ${blocked}` }), createDefaultNotificationRules()), undefined);
  }
});

test('ICBC rejects impossible calendar dates', () => {
  assert.equal(parseNotificationEntry(input({
    body: '尾号1234卡2月29日12:03支出（消费午餐）18.50元',
    receivedAt: new Date(2025, 2, 1).getTime()
  }), createDefaultNotificationRules()), undefined);
});

test('ICBC applies the existing strict 183-day year inference boundary', () => {
  const receivedAt = new Date(2026, 0, 1, 12, 0).getTime();
  const rules = createDefaultNotificationRules();
  const exactly183Days = parseNotificationEntry(input({
    receivedAt, body: '尾号1234卡7月3日12:00支出（消费午餐）18.50元'
  }), rules);
  const beyond183Days = parseNotificationEntry(input({
    receivedAt, body: '尾号1234卡7月4日12:00支出（消费午餐）18.50元'
  }), rules);
  assert.equal(exactly183Days?.happenedAt, new Date(2026, 6, 3, 12).getTime());
  assert.equal(beyond183Days?.happenedAt, new Date(2025, 6, 4, 12).getTime());
});

test('default rule storage seeds only a missing value and preserves a saved empty list', () => {
  const missing = decodeNotificationRuleStore(undefined);
  const empty = decodeNotificationRuleStore(JSON.stringify({ version: 1, rules: [] }));
  assert.equal(missing.persistDefaults, true);
  assert.equal(missing.rules.length, 4);
  assert.equal(missing.rules[0].entrySource, 'icbc');
  assert.equal(missing.rules[1].entrySource, 'citic');
  assert.equal(empty.rules.length, 0);
  assert.equal(empty.persistDefaults, false);
});

test('corrupt or unsupported stored rules fail instead of silently restoring defaults', () => {
  assert.throws(() => decodeNotificationRuleStore('{'), Error);
  assert.throws(() => decodeNotificationRuleStore(JSON.stringify({ version: 3, rules: [] })), Error);
  const incompleteRule = { ...createDefaultNotificationRules()[0] };
  delete incompleteRule.merchantPrefixToStrip;
  assert.throws(() => decodeNotificationRuleStore(JSON.stringify({ version: 1, rules: [incompleteRule] })), Error);
});

test('validation rejects malformed regular expressions', () => {
  const issue = validateNotificationRule(customRule({ bodyPattern: '[' }));
  assert.equal(issue?.field, 'bodyPattern');
});

test('custom rule names cannot collide with built-in source codes', () => {
  for (const name of ['manual', 'wechat', 'alipay', 'icbc', 'citic']) {
    assert.equal(validateNotificationRule(customRule({ name }))?.field, 'name');
  }
});

test('capture counting skips escaped parentheses, character classes, and non-capturing groups while counting named captures', () => {
  const rule = customRule({
    bodyPattern: '^(?:foo)[()]\\((?<dir>收入|支出)\\)(\\d+)$',
    directionGroup: 1,
    amountGroup: 2
  });
  assert.equal(validateNotificationRule(rule), undefined);
  assert.equal(validateNotificationRule({ ...rule, amountGroup: 3 })?.field, 'amountGroup');
});

test('validation rejects out-of-range optional and note-template group references', () => {
  const rule = customRule({
    bodyPattern: '^(\\w+):(收入|支出):([\\d.]+)$',
    amountGroup: 3,
    directionGroup: 2,
    merchantGroup: 4
  });
  assert.equal(validateNotificationRule(rule)?.field, 'merchantGroup');
  assert.equal(validateNotificationRule({ ...rule, merchantGroup: undefined, noteTemplate: '{{5}}' })?.field, 'noteTemplate');
});

test('amount conversion retains yuan-to-fen decimal behavior', () => {
  assert.equal(parseAmountFen('¥1,234.56'), 123456);
  assert.equal(parseAmountFen('18.5'), 1850);
  assert.equal(parseAmountFen('bad'), undefined);
});

test('semantic rule parses a CITIC expense notification with a thousands separator', () => {
  const rule = customRule({
    sourceKeywords: ['中信银行'],
    semanticCaptures: true,
    bodyPattern: String.raw`.*(?<direction>存入|支出)(?<amount>[\d,.]+)`,
    amountGroup: undefined,
    directionGroup: undefined,
    incomeText: '存入',
    expenseText: '支出',
    noteTemplate: ''
  });
  const entry = parseNotificationEntry(input({
    appName: '中信银行',
    body: '您尾号6370的账户支出3,000.00元，点击查看详情。'
  }), [rule]);

  assert.equal(entry?.amountFen, 300000);
  assert.equal(entry?.direction, 'expense');
});

test('semantic captures parse named amount and direction without numeric group configuration', () => {
  const rule = customRule({
    semanticCaptures: true,
    bodyPattern: '^(?<direction>收入|支出)\\s+(?<amount>[¥￥]?[\\d,.]+)元\\s+(?<merchant>.+)$',
    amountGroup: undefined,
    directionGroup: undefined,
    merchantGroup: undefined,
    noteTemplate: ''
  });
  const entry = parseNotificationEntry(input({
    appName: 'MockPay',
    body: '支出 12,345,678.90元 示例店'
  }), [rule]);

  assert.equal(entry?.amountFen, 1234567890);
  assert.equal(entry?.direction, 'expense');
  assert.equal(entry?.merchant, '示例店');
});

test('semantic captures may omit optional fields and then use configured defaults', () => {
  const rule = customRule({
    semanticCaptures: true,
    bodyPattern: '^(?<direction>收入|支出)\\s+(?<amount>[\\d,.]+)元$',
    amountGroup: undefined,
    directionGroup: undefined,
    dateGroup: undefined,
    merchantGroup: undefined,
    categoryGroup: undefined,
    noteTemplate: ''
  });
  const entry = parseNotificationEntry(input({
    appName: 'MockPay', body: '收入 1,031.10元'
  }), [rule]);

  assert.equal(entry?.amountFen, 103110);
  assert.equal(entry?.direction, 'income');
  assert.equal(entry?.merchant, '未知商户');
  assert.equal(entry?.category, '其他');
});

test('semantic date captures keep strict calendar validation and the configured format', () => {
  const rule = customRule({
    semanticCaptures: true,
    bodyPattern: '^(?<direction>收入|支出)\\s+(?<amount>[\\d,.]+)\\s+(?<date>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2})$',
    amountGroup: undefined,
    directionGroup: undefined,
    dateGroup: undefined,
    dateFormat: 'yyyy-MM-dd HH:mm',
    dateStrategy: 'format',
    noteTemplate: ''
  });
  const good = parseNotificationEntry(input({
    appName: 'MockPay', body: '支出 18.50 2026-10-03 08:25'
  }), [rule]);
  const bad = parseNotificationEntry(input({
    appName: 'MockPay', body: '支出 18.50 2026-02-30 08:25'
  }), [rule]);

  assert.equal(good?.happenedAt, new Date(2026, 9, 3, 8, 25).getTime());
  assert.equal(bad, undefined);
});

test('semantic validation requires amount and direction and rejects unnamed, unknown, or duplicate captures', () => {
  const base = customRule({ semanticCaptures: true, amountGroup: undefined, directionGroup: undefined, noteTemplate: '' });
  assert.equal(validateNotificationRule({ ...base, bodyPattern: '(?<direction>收入|支出)\\d+' })?.field,
    'bodyPattern');
  assert.equal(validateNotificationRule({ ...base, bodyPattern: '(?<amount>\\d+)' })?.field, 'bodyPattern');
  assert.equal(validateNotificationRule({ ...base, bodyPattern: '(收入|支出)(?<amount>\\d+)' })?.field,
    'bodyPattern');
  assert.equal(validateNotificationRule({ ...base, bodyPattern:
    '(?<direction>收入|支出)(?<amount>\\d+)(?<amount>\\d+)' })?.field, 'bodyPattern');
});

test('version one notification rules migrate without changing their legacy numeric captures', () => {
  const rule = customRule({ bodyPattern: '^REF:(\\w+):(收入|支出):([\\d.]+)$', amountGroup: 3, directionGroup: 2 });
  const stored = decodeNotificationRuleStore(JSON.stringify({
    version: 1, defaultRulesVersion: 1, rules: [rule]
  }));

  assert.equal(stored.migrated, true);
  assert.equal(stored.rules[0].bodyPattern, rule.bodyPattern);
  assert.equal(stored.rules[0].amountGroup, 3);
  assert.equal(stored.rules[0].directionGroup, 2);
  assert.deepEqual(decodeNotificationRuleStore(JSON.stringify({ version: 2, rules: [] })).rules, []);
});

test('version one migration still upgrades the exact historical ICBC default pattern', () => {
  const oldRule = createDefaultNotificationRules()[0];
  oldRule.bodyPattern = String.raw`尾号\s*(\d{4})\s*卡\s*(\d{1,2}月\d{1,2}日\s*\d{1,2}:\d{2})\s*(支出|收入)\s*[（(]\s*([^）)]*?)\s*[）)]\s*(\d+(?:[.,]\d{1,2})?)\s*元`;
  const stored = decodeNotificationRuleStore(JSON.stringify({
    version: 1, defaultRulesVersion: 1, rules: [oldRule]
  }));

  assert.equal(stored.migrated, true);
  assert.equal(stored.rules[0].bodyPattern, createDefaultNotificationRules()[0].bodyPattern);
});

test('排除正文正则优先于入账匹配并阻止后续规则处理同一通知', () => {
  const excludedRule = customRule({
    id: 'excluded',
    name: '需要排除的通知',
    semanticCaptures: true,
    amountGroup: undefined,
    directionGroup: undefined,
    bodyPattern: String.raw`(?<direction>支出|收入)\s*(?<amount>\d+(?:\.\d{1,2})?)元`,
    excludeBodyPatterns: ['系统摘要'],
    noteTemplate: ''
  });
  const laterRule = customRule({
    id: 'later',
    name: '后续规则',
    semanticCaptures: true,
    amountGroup: undefined,
    directionGroup: undefined,
    bodyPattern: String.raw`(?<direction>支出|收入)\s*(?<amount>\d+(?:\.\d{1,2})?)元`,
    noteTemplate: ''
  });
  const notification = input({ appName: 'MockPay', bundleName: 'example.mock',
    body: '系统摘要：支出18.50元' });

  assert.equal(parseNotificationEntry(notification, [excludedRule, laterRule]), undefined);
  assert.equal(parseNotificationEntry({ ...notification, body: '普通交易：支出18.50元' }, [excludedRule, laterRule])?.source,
    '需要排除的通知');
});

test('规则存储验证拒绝无效的排除正文正则', () => {
  const rule = customRule({ excludeBodyPatterns: ['系统摘要'] });
  assert.equal(validateNotificationRule(rule), undefined);
  assert.equal(validateNotificationRule({ ...rule, excludeBodyPatterns: ['['] })?.field, 'excludeBodyPatterns');
  assert.equal(validateNotificationRule({ ...rule, excludeBodyPatterns: '系统摘要' })?.field, 'excludeBodyPatterns');
});

test('默认微信规则拒绝普通聊天和正文中转述的支付通知', () => {
  for (const title of ['好友', '聊天群', '', undefined]) {
    const entry = parseNotificationEntry(input({
      appName: '微信', bundleName: 'com.tencent.mm', title,
      body: '我刚刚收到转账100元了'
    }), createDefaultNotificationRules());
    assert.equal(entry, undefined, `普通聊天标题 ${title} 不应记账`);
  }
  assert.equal(parseNotificationEntry(input({
    appName: '微信', bundleName: 'com.tencent.mm', title: '好友',
    body: '微信支付\n收款到账100元'
  }), createDefaultNotificationRules()), undefined);
  assert.equal(parseNotificationEntry(input({
    appName: '微信', bundleName: 'com.tencent.mm', title: undefined,
    body: '微信支付\n收款到账100元'
  }), createDefaultNotificationRules()), undefined, '正文不能冒充实际通知标题');
});

test('默认微信规则保留支付服务的收支识别和失败过滤', () => {
  for (const [body, amountFen, direction] of [
    ['收款到账100元', 10000, 'income'],
    ['支付成功18.50元', 1850, 'expense']
  ]) {
    const entry = parseNotificationEntry(input({
      appName: '微信', bundleName: 'com.tencent.mm', title: '微信支付', body
    }), createDefaultNotificationRules());
    assert.equal(entry?.amountFen, amountFen);
    assert.equal(entry?.direction, direction);
  }
  assert.equal(parseNotificationEntry(input({
    appName: '微信', bundleName: 'com.tencent.mm', title: '微信支付', body: '支付失败18.50元'
  }), createDefaultNotificationRules()), undefined);
});

test('已保存的原始微信默认规则升级后也拒绝聊天误记', () => {
  const saved = readFileSync(new URL('./fixtures/wechat-default-v2.json', import.meta.url), 'utf8');
  const state = decodeNotificationRuleStore(saved);
  assert.equal(state.migrated, true);
  assert.equal(parseNotificationEntry(input({
    appName: '微信', title: '好友', body: '我刚刚收到转账100元了'
  }), state.rules), undefined);
  assert.equal(parseNotificationEntry(input({
    appName: '微信', title: '微信支付', body: '收款到账100元'
  }), state.rules)?.amountFen, 10000);

  const custom = JSON.parse(saved);
  custom.rules[0].bodyPattern += '(?:自定义后缀)?';
  const preserved = decodeNotificationRuleStore(JSON.stringify(custom));
  assert.equal(preserved.rules[0].bodyPattern, custom.rules[0].bodyPattern);
  assert.notEqual(preserved.migrated, true);

  const titleEdited = JSON.parse(saved);
  titleEdited.rules[0].requiredTitle = '商户收款助手';
  const preservedTitle = decodeNotificationRuleStore(JSON.stringify(titleEdited));
  assert.equal(parseNotificationEntry(input({
    appName: '微信', title: '好友', body: '收款到账100元'
  }), preservedTitle.rules), undefined);
  assert.equal(parseNotificationEntry(input({
    appName: '微信', title: '商户收款助手', body: '收款到账100元'
  }), preservedTitle.rules)?.amountFen, 10000);
});

test('完整日期策略拒绝没有年份或月日的格式', () => {
  const base = customRule({
    semanticCaptures: true, amountGroup: undefined, directionGroup: undefined, noteTemplate: '',
    bodyPattern: String.raw`(?<date>.+) (?<direction>收入|支出) (?<amount>\d+)`,
    dateStrategy: 'format'
  });
  for (const dateFormat of ['MM-dd HH:mm', 'yyyy-dd HH:mm', 'yyyy-MM HH:mm', 'HH:mm']) {
    assert.equal(validateNotificationRule({ ...base, dateFormat })?.field, 'dateFormat', dateFormat);
  }
  assert.equal(validateNotificationRule({ ...base, dateFormat: 'yyyy-MM-dd HH:mm' }), undefined);
  assert.equal(validateNotificationRule({ ...base, dateStrategy: 'infer-year', dateFormat: 'M月d日 HH:mm' }), undefined);
  assert.equal(validateNotificationRule({ ...base, dateStrategy: 'infer-year', dateFormat: 'HH:mm' })?.field, 'dateFormat');
});

test('旧版曾允许的缺年份规则仍可读出修正且不阻断其他规则', () => {
  const legacy = customRule({
    bodyPattern: String.raw`^(\d{2}-\d{2} \d{2}:\d{2}) (收入|支出) (\d+)$`,
    amountGroup: 3, directionGroup: 2, dateGroup: 1,
    dateFormat: 'MM-dd HH:mm', dateStrategy: 'format', noteTemplate: ''
  });
  const state = decodeNotificationRuleStore(JSON.stringify({
    version: 2, defaultRulesVersion: 1, rules: [legacy, createDefaultNotificationRules()[1]]
  }));
  assert.equal(state.rules[0].dateFormat, 'MM-dd HH:mm');
  assert.equal(validateNotificationRule(state.rules[0])?.field, 'dateFormat');
  assert.equal(parseNotificationEntry(input({
    appName: '中信银行', body: '尾号1234的账户支出18.50元'
  }), state.rules)?.amountFen, 1850);
});
