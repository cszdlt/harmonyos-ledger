import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const helpViewUrl = new URL('../entry/src/main/ets/components/settings/HelpView.ets', import.meta.url);
const helpSource = readFileSync(helpViewUrl, 'utf8');

test('使用帮助说明与当前界面路径一致', () => {
  assert.match(helpSource, /记账周期/);
  assert.match(helpSource, /查看统计 ›/);
  assert.match(helpSource, /＋ 手动记账/);
  assert.match(helpSource, /打开通知访问授权/);
  assert.match(helpSource, /配置识别规则/);
  assert.doesNotMatch(helpSource, /可切换周期，进入统计详情/);
  assert.doesNotMatch(helpSource, /在“账本”页点“手动记账”/);
  assert.match(helpSource, /复制修正说明和原材料给 AI/);
});
