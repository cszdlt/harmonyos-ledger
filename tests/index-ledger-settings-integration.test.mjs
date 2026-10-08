import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const indexSource = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const includes = (pattern, message) => assert.ok(pattern.test(indexSource), message);
const excludes = (pattern, message) => assert.equal(pattern.test(indexSource), false, message);

test('Index provides settings callbacks through LedgerTabPage while retaining repository ownership', () => {
  includes(/import\s+\{[^}]*\bLedgerTabPage\b[^}]*\}\s+from\s+['"]\.\/ledger\/LedgerTabPage['"]/,
    'Index must import LedgerTabPage');
  includes(/LedgerTabPage\s*\([\s\S]*?onListEntries:\s*\(\)\s*=>\s*this\.repository\.listEntries\(\)/,
    'Index must provide fresh entries from its repository');
  includes(/onSaveCsvEntries:\s*\(entries:\s*LedgerEntry\[\],\s*duplicateCount:\s*number,\s*invalidCount:\s*number\)\s*=>\s*this\.saveCsvEntries\(entries,\s*duplicateCount,\s*invalidCount\)/,
    'Index must route confirmed imports to its save method');
  includes(/private\s+async\s+saveCsvEntries\(entries:\s*LedgerEntry\[\],\s*duplicateCount:\s*number,\s*invalidCount:\s*number\):\s*Promise<void>[\s\S]*?repository\.addEntries\(entries\)[\s\S]*?await\s+this\.reloadEntries\(\)/,
    'the repository owner must persist imports and refresh the ledger');

  excludes(/import\s+\{\s*SettingsView\s*\}\s+from/, 'Index must no longer compose SettingsView directly');
  excludes(/import\s+\{[^}]*\bLedgerSettingsPage\b/, 'LedgerTabPage must compose the settings page');
  excludes(/import\s+\{\s*Csv(?:Importer|Exporter)\s*\}\s+from/, 'CSV services must leave Index');
  excludes(/CsvImportDialogResponse|private\s+async\s+(?:exportCsv|importCsv)\s*\(/,
    'CSV picker and preview implementation must leave Index');
});
