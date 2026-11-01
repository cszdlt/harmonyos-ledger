import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { validateNotificationBody, createDefaultNotificationRules } from '../entry/src/main/ets/services/notificationRules/NotificationRuleEngine.ets';
import { formatDateTime } from '../entry/src/main/ets/model/LedgerModels.ets';

const Editor = loadPageMethods(
  new URL('../entry/src/main/ets/components/notifications/NotificationRuleEditor.ets', import.meta.url),
  ['copyRule', 'updateRule', 'clearBodyValidation', 'validateBody'],
  { validateNotificationBody, formatDateTime }
);

function editor() {
  const instance = new Editor();
  instance.draft = createDefaultNotificationRules()[1];
  instance.sampleBody = '尾号1234的账户支出12.30元';
  return instance;
}

test('编辑器验证展示正式解析字段，失败后清除上一次成功结果', () => {
  const instance = editor();
  instance.validateBody();
  assert.match(instance.bodyValidationMessage, /验证通过/);
  for (const value of ['金额：12.30 元', '收支：支出', '日期：', '商户：中信银行账户', '分类：其他']) {
    assert.ok(instance.bodyValidationResult.includes(value));
  }
  instance.sampleBody = '无法匹配的正文';
  instance.validateBody();
  assert.match(instance.bodyValidationMessage, /正则未匹配/);
  assert.equal(instance.bodyValidationResult, '');
});

test('修改草稿后验证结果失效，原规则与样例保持不变', () => {
  const instance = editor();
  const original = instance.draft;
  instance.validateBody();
  instance.updateRule(draft => { draft.defaultCategory = '日用'; });
  assert.equal(instance.bodyValidationMessage, '');
  assert.equal(instance.bodyValidationResult, '');
  assert.equal(original.defaultCategory, '其他');
  assert.equal(instance.sampleBody, '尾号1234的账户支出12.30元');
});

test('编辑器复制规则时保留排除正则', () => {
  const instance = editor();
  instance.draft.excludeBodyPatterns = ['退款成功', '系统摘要'];
  assert.deepEqual(instance.copyRule(instance.draft).excludeBodyPatterns, ['退款成功', '系统摘要']);
});
