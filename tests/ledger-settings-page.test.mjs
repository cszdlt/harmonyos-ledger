import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const pagePath = new URL('../entry/src/main/ets/pages/ledger/LedgerSettingsPage.ets', import.meta.url);
const pageSource = existsSync(fileURLToPath(pagePath)) ? readFileSync(pagePath, 'utf8') : '';
const includes = (pattern, message) => assert.ok(pattern.test(pageSource), message);

test('LedgerSettingsPage owns CSV selection and export interactions', () => {
  assert.notEqual(pageSource, '', 'LedgerSettingsPage.ets must exist');
  includes(/export\s+struct\s+LedgerSettingsPage/, 'the settings page component must be exported');
  includes(/SettingsView\s*\(/, 'the page must continue to compose the controlled settings view');
  includes(/CsvImporter\.selectAndPreview\(context,\s*existingEntries\)/,
    'CSV selection and preview must happen in the settings page');
  includes(/CsvExporter\.export\(context,\s*entries\)/,
    'CSV export must happen in the settings page');
  includes(/onListEntries:\s*\(\)\s*=>\s*Promise<LedgerEntry\[\]>/,
    'the settings page must request current entries through its owner');
  includes(/onSaveCsvEntries:\s*\(entries:\s*LedgerEntry\[\],\s*duplicateCount:\s*number,\s*invalidCount:\s*number\)\s*=>\s*Promise<void>/,
    'confirmed imports must return to the repository owner');
});

test('CSV preview retains cancellation, invalid row limit, and import confirmation', () => {
  includes(/if\s*\(preview === undefined\)[\s\S]*?已取消 CSV 导入/,
    'canceling the file picker must report cancellation');
  includes(/preview\.invalidRows\.slice\(0,\s*5\)/,
    'the preview must show at most five invalid rows');
  includes(/if\s*\(preview\.entries\.length === 0\)[\s\S]*?text:\s*'关闭'/,
    'a preview without importable entries must only offer closing');
  includes(/response\.index !== 1[\s\S]*?已取消 CSV 导入/,
    'canceling the confirmation must not import entries');
  includes(/this\.onSaveCsvEntries\(preview\.entries,\s*preview\.duplicateCount,\s*preview\.invalidRows\.length\)/,
    'only confirmed entries and preview counts must be passed for saving');
});
