import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const settingsViewUrl = new URL('../entry/src/main/ets/components/settings/SettingsView.ets', import.meta.url);
const settingsViewSource = readFileSync(settingsViewUrl, 'utf8');
const ledgerHomeUrl = new URL('../entry/src/main/ets/pages/ledger/LedgerHomeView.ets', import.meta.url);
const ledgerHomeSource = readFileSync(ledgerHomeUrl, 'utf8');

test('记账周期在设置页配置，首页不再展示周期选择器', () => {
  assert.doesNotMatch(settingsViewSource, /Text\('数据与隐私'\)/);
  assert.match(settingsViewSource, /Text\('记账周期'\)/);
  assert.match(settingsViewSource, /CycleStartDaySelector/);
  assert.match(settingsViewSource, /Text\('使用帮助'\)/);
  assert.match(settingsViewSource, /Text\('截图 OCR'\)/);
  assert.match(settingsViewSource, /Text\('数据备份'\)/);
  assert.match(settingsViewSource, /Button\('导入本应用 CSV'\)/);
  assert.doesNotMatch(ledgerHomeSource, /CycleStartDaySelector/);
  assert.doesNotMatch(ledgerHomeSource, /Text\('记账周期'\)/);
});
