import test from 'node:test';
import assert from 'node:assert/strict';
import { emptyRuleSample, changeRuleSample, sampleFromNotification, validateRuleSample, buildSamplePrompt,
  unwrapRuleResponse, previewNotificationSample, previewOcrSample, previewFieldRows,
  explainImportIssues } from '../entry/src/main/ets/services/ruleImport/RuleImportGuide.ets';
import { createNotificationRule } from '../entry/src/main/ets/services/ruleImport/NotificationRuleImportAdapter.ets';
import { createOcrRule } from '../entry/src/main/ets/services/ruleImport/OcrRuleImportAdapter.ets';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { parseRuleImport } from '../entry/src/main/ets/services/ruleImport/RuleImportEngine.ets';
import { parseNotificationEntry } from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';

const archive = { appName: '示例支付', bundleName: 'example.pay', title: '交易提醒',
  body: '支出 12.30元 商户：午餐店', deliveryTime: new Date(2026, 9, 28, 10, 15).getTime(),
  receivedAt: new Date(2026, 9, 28, 10, 16).getTime() };
const description = { name: '示例支付交易', sourceKeywords: ['example.pay'],
  bodyPattern: '(?<direction>支出|收入) (?<amount>[\\d.]+)元 商户：(?<merchant>.+)',
  incomeText: '收入', expenseText: '支出', dateFormat: '', dateStrategy: 'delivery-time',
  defaultMerchant: '示例支付', defaultCategory: '其他' };

test('通知样例带入原始来源、标题和真实时间，表单不猜测金额和方向', () => {
  const sample = sampleFromNotification(archive);
  assert.equal(sample.source, 'example.pay');
  assert.equal(sample.title, '交易提醒');
  assert.equal(sample.input, archive.body);
  assert.equal(sample.date, '2026-10-28 10:15');
  assert.equal(sample.amount, '');
  assert.equal(sample.direction, '');
});

test('引导要求可靠日期、正数金额及明确方向，错误日期不能生成材料', () => {
  const sample = { ...emptyRuleSample(), source: '钱包', input: '示例正文', amount: '12.30',
    direction: 'expense', date: '2026-02-30' };
  assert.match(validateRuleSample(sample, 'ocr'), /日期/);
  assert.equal(validateRuleSample({ ...sample, date: '2026-10-28' }, 'ocr'), '');
  assert.match(validateRuleSample({ ...sample, amount: '-1' }, 'ocr'), /金额/);
  assert.match(validateRuleSample({ ...sample, direction: '' }, 'ocr'), /收入|支出/);
});

test('完整材料包括用户确认值和标题，支持仅移除包裹代码块而不改写内容', () => {
  const sample = { ...sampleFromNotification(archive), amount: '12.30', direction: 'expense', merchant: '午餐店' };
  const prompt = buildSamplePrompt(sample, 'notification');
  assert.ok(prompt.includes('example.pay'));
  assert.ok(prompt.includes('交易提醒'));
  assert.ok(prompt.includes('12.30'));
  assert.ok(prompt.includes('2026-10-28 10:15'));
  assert.equal(unwrapRuleResponse('```json\n{"x":"保留\\n转义"}\n```'), '{"x":"保留\\n转义"}');
  assert.equal(unwrapRuleResponse('前言 {"x":1}'), '前言 {"x":1}');
});

test('本地通知预览校验用户确认值、真实投递时间和标题，不能由 AI 自带样例替代', () => {
  const sample = { ...sampleFromNotification(archive), amount: '12.30', direction: 'expense', merchant: '午餐店' };
  const rule = createNotificationRule(description, []);
  rule.requiredTitle = sample.title;
  assert.equal(previewNotificationSample(rule, sample).matched, true);
  assert.equal(previewNotificationSample(rule, { ...sample, amount: '13' }).matched, false);
  assert.equal(previewNotificationSample(rule, { ...sample, title: '普通聊天' }).actual, undefined);
  assert.equal(previewNotificationSample(rule, { ...sample, source: 'other.app' }).actual, undefined);
});

test('OCR 本地预览使用真实截图的列坐标，余额不能冒充交易金额', () => {
  const rule = createOcrRule({ name: '钱包', source: { id: 'wallet', name: '钱包', patterns: ['钱包'] },
    record: { mode: 'row' }, fields: { amount: '(\\d+\\.\\d{2})', date: '(2026-10-28)', direction: '(支出)' },
    columns: { amount: { left: 0.5, right: 1 } }, incomeKeywords: ['收入'], expenseKeywords: ['支出'], defaultCategory: '其他' }, []);
  const line = (text, left, right, y) => ({ text, left, right, top: y, bottom: y + 20, centerY: y + 10, height: 20 });
  const page = { pageNumber: 1, imageWidth: 1000, rawText: '钱包\n2026-10-28 支出 99.00 12.30',
    lines: [line('钱包', 0, 100, 0), line('2026-10-28 支出 99.00', 0, 450, 30), line('12.30', 600, 900, 30)] };
  const sample = { ...emptyRuleSample(), source: '钱包', input: page.rawText, amount: '12.30',
    date: '2026-10-28', direction: 'expense', ocrPage: page };
  assert.equal(previewOcrSample(rule, sample).matched, true);
  assert.equal(previewOcrSample(rule, { ...sample, amount: '99.00' }).matched, false);
});

test('字段对照按金额数值比较，并明确标出差异和未识别项', () => {
  const rows = previewFieldRows({ input: '', expected: { amount: '1,000.00', direction: 'expense', merchant: '午餐' },
    actual: { amount: '1000.00', direction: 'income' }, matched: false });
  assert.equal(rows.find(row => row.label === '金额').matched, true);
  assert.equal(rows.find(row => row.label === '收支').actual, '收入');
  assert.equal(rows.find(row => row.label === '商户').actual, '未识别');
  assert.equal(rows.find(row => row.label === '商户').matched, false);
  assert.match(explainImportIssues([{ field: 'rule.fields.amount', message: '表达式至少需要一个捕获组' }]), /金额/);
});

test('修改文字后不再把旧截图坐标用于新文字，修改确认值则保留坐标', () => {
  const page = { rawText: '原文', lines: [] };
  const sample = { ...emptyRuleSample(), input: '原文', ocrPage: page };
  assert.equal(changeRuleSample(sample, 'amount', '10').ocrPage, page);
  assert.equal(changeRuleSample(sample, 'input', '新文字').ocrPage, undefined);
});

test('规则页面粘贴后自动试跑，修改确认值即撤销旧的保存资格', async () => {
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets', import.meta.url),
    ['changeSample', 'updateImportResponse', 'previewImportedRule', 'saveImportedRule'],
    { changeRuleSample, validateRuleSample, unwrapRuleResponse, parseRuleImport, createNotificationRule,
      previewNotificationSample, explainImportIssues, emptyRuleSample });
  const page = new Page();
  Object.assign(page, { sample: { ...sampleFromNotification(archive), amount: '12.30', direction: 'expense' },
    rules: [], importJson: '', importPreviews: [], isSavingRules: false });
  page.updateImportResponse(JSON.stringify({ schemaVersion: 1, kind: 'notification', rule: description,
    examples: [{ input: '支出 12.30元 商户：午餐店', expected: { amount: '12.30' } }] }));
  assert.equal(page.importPreviews[0].matched, true);
  assert.equal(page.importCandidate.requiredTitle, undefined);
  page.changeSample('matchTitle', 'true');
  page.previewImportedRule();
  assert.equal(page.importCandidate.requiredTitle, '交易提醒');
  page.changeSample('amount', '13');
  assert.equal(page.importCandidate, undefined);
  let writes = 0;
  page.persistRules = async () => { writes++; };
  await page.saveImportedRule();
  assert.equal(writes, 0);
  page.previewImportedRule();
  assert.equal(page.importPreviews[0].matched, false);
  await page.saveImportedRule();
  assert.equal(writes, 0);
});

test('OCR 来源不匹配或与另一来源并列时不能宣称预览通过', () => {
  const rule = createOcrRule({ name: '钱包', source: { id: 'wallet', name: '钱包', patterns: ['不存在的来源'] },
    record: { mode: 'row' }, fields: { amount: '(\\d+\\.\\d{2})', date: '(2026-10-28)', direction: '(支出)' },
    incomeKeywords: ['收入'], expenseKeywords: ['支出'], defaultCategory: '其他' }, []);
  const sample = { ...emptyRuleSample(), source: '钱包', input: '钱包 2026-10-28 支出 12.30',
    amount: '12.30', date: '2026-10-28', direction: 'expense' };
  assert.equal(previewOcrSample(rule, sample).matched, false);
  rule.sourceMatchers = [{ pattern: '钱包' }];
  const competing = { ...rule, id: 'another', source: 'another-wallet' };
  assert.equal(previewOcrSample(rule, sample, [competing]).matched, false);
});

test('保存顺序与预览一致，新规则优先于同来源的旧规则，且不保存未选择的标题', async () => {
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets', import.meta.url),
    ['changeSample', 'updateImportResponse', 'previewImportedRule', 'saveImportedRule'],
    { changeRuleSample, validateRuleSample, unwrapRuleResponse, parseRuleImport, createNotificationRule,
      previewNotificationSample, explainImportIssues, emptyRuleSample });
  const page = new Page();
  const old = createNotificationRule({ ...description, name: '旧规则', bodyPattern: '(?<direction>支出|收入) (?<amount>[\\d.]+)元' }, []);
  Object.assign(page, { sample: { ...sampleFromNotification(archive), amount: '12.30', direction: 'expense', merchant: '午餐店' },
    rules: [old], importJson: '', importPreviews: [], isSavingRules: false });
  page.updateImportResponse(JSON.stringify({ schemaVersion: 1, kind: 'notification', rule: description }));
  assert.equal(page.importPreviews[0].matched, true);
  let saved;
  page.persistRules = async rules => { saved = rules; };
  await page.saveImportedRule();
  const entry = parseNotificationEntry({ appName: archive.appName, bundleName: archive.bundleName, title: '下一笔动态标题',
    body: archive.body, deliveryTime: archive.deliveryTime, receivedAt: archive.receivedAt }, saved);
  assert.equal(entry.merchant, '午餐店');
  assert.equal(entry.provenance.ruleId, saved[0].id);
  assert.equal(saved[1], old);
  assert.equal(saved[0].requiredTitle, undefined);
});
