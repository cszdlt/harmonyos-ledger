import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { emptyRuleSample, changeRuleSample, sampleFromNotification, unwrapRuleResponse, explainImportIssues } from '../entry/src/main/ets/services/ruleImport/RuleImportGuide.ets';
import { validateNotificationSamples, previewNotificationSamples } from '../entry/src/main/ets/services/ruleImport/NotificationRuleSamples.ets';
import { parseRuleImport } from '../entry/src/main/ets/services/ruleImport/RuleImportEngine.ets';
import { createNotificationRule } from '../entry/src/main/ets/services/ruleImport/NotificationRuleImportAdapter.ets';

const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets', import.meta.url),
  ['changeSample', 'resetImportPreview', 'currentSamples', 'toggleSample', 'setCurrentSampleExcluded', 'removeSample', 'activateSample',
    'selectSampleSource', 'loadPickerEntries', 'updateImportResponse', 'previewImportedRule', 'saveImportedRule', 'copyRule'],
  { emptyRuleSample, changeRuleSample, sampleFromNotification, unwrapRuleResponse, explainImportIssues,
    validateNotificationSamples, previewNotificationSamples, parseRuleImport, createNotificationRule });
const timestamp = new Date(2026, 10, 1, 8, 34).getTime();
function entry(id, body = '支出12.30元') {
  return { id, bundleName: 'example.pay', appName: '示例支付', title: '交易提醒', body,
    deliveryTime: timestamp, receivedAt: timestamp };
}
function page() {
  return Object.assign(new Page(), { sample: emptyRuleSample(), selectedSamples: [], activeSampleIndex: 0,
    rules: [], importJson: '', importPreviews: [], isSavingRules: false, pickerBundle: 'example.pay',
    pickerEntries: [], pickerLoading: false, pickerQueryRevision: 0, pickerMessage: '', pickerCursor: undefined });
}
function confirm(instance, amount) {
  instance.changeSample('amount', amount);
  instance.changeSample('direction', 'expense');
}
const description = { name: '示例支付', sourceKeywords: ['example.pay'],
  bodyPattern: '(?<direction>收入|支出)(?<amount>(?:\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?|\\d+(?:\\.\\d{1,2})?))元',
  incomeText: '收入', expenseText: '支出', dateFormat: '', dateStrategy: 'delivery-time',
  defaultMerchant: '示例支付', defaultCategory: '其他' };

test('多选通知可切换、取消，已确认字段保留且选择变化撤销保存资格', () => {
  const instance = page();
  instance.toggleSample(entry(1)); confirm(instance, '12.30');
  instance.toggleSample(entry(2, '支出98.76元')); confirm(instance, '98.76');
  instance.activateSample(0);
  assert.equal(instance.sample.amount, '12.30');
  instance.importCandidate = {};
  instance.toggleSample(entry(2));
  assert.equal(instance.selectedSamples.length, 1);
  assert.equal(instance.importCandidate, undefined);
  assert.equal(instance.sample.input, '支出12.30元');
});

test('选择其他包名清空旧样例，迟到的旧查询不能覆盖新来源', async () => {
  const instance = page();
  instance.toggleSample(entry(1));
  let finishOld;
  instance.sampleRepository = { listPage: ({ bundleName }) => bundleName === 'old.pay'
    ? new Promise(resolve => { finishOld = resolve; }) : Promise.resolve({ entries: [entry(9)] }) };
  instance.selectSampleSource('old.pay');
  instance.selectSampleSource('new.pay');
  await new Promise(resolve => setImmediate(resolve));
  finishOld({ entries: [entry(8)] });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(instance.pickerBundle, 'new.pay');
  assert.deepEqual(instance.pickerEntries.map(item => item.id), [9]);
  assert.equal(instance.selectedSamples.length, 0);
  assert.equal(instance.sample.source, 'new.pay');
});

test('AI返回的规则必须匹配全部通知且通过金额泛化，保存失败前不写入', async () => {
  const instance = page();
  instance.toggleSample(entry(1)); confirm(instance, '12.30');
  instance.toggleSample(entry(2, '消费98.76元')); confirm(instance, '98.76');
  instance.updateImportResponse(JSON.stringify({ schemaVersion: 1, kind: 'notification', rule: description }));
  assert.deepEqual(instance.importPreviews.map(item => item.matched), [true, false]);
  let writes = 0;
  instance.persistRules = async () => { writes++; };
  await instance.saveImportedRule(); assert.equal(writes, 0);
  instance.removeSample(2);
  const fixedAmount = { ...description, bodyPattern: '(?<direction>收入|支出)(?<amount>12\\.30)元' };
  instance.updateImportResponse(JSON.stringify({ schemaVersion: 1, kind: 'notification', rule: fixedAmount }));
  await instance.saveImportedRule(); assert.equal(writes, 0);
  instance.updateImportResponse(JSON.stringify({ schemaVersion: 1, kind: 'notification', rule: description }));
  await instance.saveImportedRule(); assert.equal(writes, 1);
  assert.equal(instance.selectedSamples.length, 0);
});

test('归档样例的来源、标题、正文不能被编辑成另一条通知', () => {
  const instance = page(); instance.toggleSample(entry(1));
  for (const field of ['source', 'title', 'input']) { instance.changeSample(field, '伪造'); }
  assert.equal(instance.sample.source, 'example.pay');
  assert.equal(instance.sample.title, '交易提醒');
  assert.equal(instance.sample.input, '支出12.30元');
});

test('所选通知可切换包含或排除，切换时保留原文并撤销旧预览', () => {
  const instance = page();
  instance.toggleSample(entry(1)); confirm(instance, '12.30');
  instance.importCandidate = {};
  instance.setCurrentSampleExcluded(true);
  assert.equal(instance.currentSamples()[0].excluded, true);
  assert.equal(instance.sample.input, '支出12.30元');
  assert.equal(instance.sample.amount, '12.30');
  assert.equal(instance.importCandidate, undefined);
  instance.setCurrentSampleExcluded(false);
  assert.equal(instance.currentSamples()[0].excluded, false);
});

test('规则设置页复制规则时保留排除正文正则', () => {
  const instance = page();
  const rule = createNotificationRule({ ...description, excludeBodyPatterns: ['系统摘要'] }, []);
  assert.deepEqual(instance.copyRule(rule).excludeBodyPatterns, ['系统摘要']);
});
