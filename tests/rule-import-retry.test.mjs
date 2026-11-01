import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const guideUrl = new URL('../entry/src/main/ets/services/ruleImport/RuleImportGuide.ets', import.meta.url);
const guideSource = readFileSync(guideUrl, 'utf8');
const ocrPageUrl = new URL('../entry/src/main/ets/pages/ocr/OcrRuleSettingsView.ets', import.meta.url);
const notifyPageUrl = new URL('../entry/src/main/ets/pages/notifications/NotificationRuleSettingsView.ets', import.meta.url);
const guideViewUrl = new URL('../entry/src/main/ets/components/RuleImportGuideView.ets', import.meta.url);

test('规则导入失败时可组装 AI 修正包并保留原材料', () => {
  assert.match(guideSource, /export function buildRuleImportRetryPrompt/);
  assert.match(guideSource, /export function buildPreviewFailureReport/);
  assert.match(guideSource, /export function formatImportIssuesForAi/);
  assert.match(guideSource, /【上次完整材料】/);
  assert.match(guideSource, /复制修正说明和原材料给 AI/);
});

test('OCR 与通知规则页保存 lastImportPrompt 并提供重试复制', () => {
  const ocrSource = readFileSync(ocrPageUrl, 'utf8');
  const notifySource = readFileSync(notifyPageUrl, 'utf8');
  const viewSource = readFileSync(guideViewUrl, 'utf8');
  assert.match(ocrSource, /lastImportPrompt/);
  assert.match(ocrSource, /copyImportRetry/);
  assert.match(notifySource, /lastImportPrompt/);
  assert.match(notifySource, /copyImportRetry/);
  assert.match(viewSource, /importRetryAvailable/);
  assert.match(viewSource, /复制修正说明和原材料给 AI/);
});
