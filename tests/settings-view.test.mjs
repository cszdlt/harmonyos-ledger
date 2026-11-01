import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const settingsViewUrl = new URL('../entry/src/main/ets/components/settings/SettingsView.ets', import.meta.url);
const settingsViewSource = readFileSync(settingsViewUrl, 'utf8');

test('账本设置隐藏数据与隐私和记账周期，保留其他设置功能', () => {
  assert.doesNotMatch(settingsViewSource, /Text\('数据与隐私'\)/);
  assert.doesNotMatch(settingsViewSource, /Text\('记账周期'\)/);
  assert.doesNotMatch(settingsViewSource, /CycleStartDaySelector/);
  assert.match(settingsViewSource, /Text\('使用帮助'\)/);
  assert.match(settingsViewSource, /Text\('截图 OCR'\)/);
  assert.match(settingsViewSource, /Text\('数据备份'\)/);
  assert.match(settingsViewSource, /Button\('导入本应用 CSV'\)/);
});
