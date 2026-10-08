import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const indexSource = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const includes = (pattern, message) => assert.ok(pattern.test(indexSource), message);
const excludes = (pattern, message) => assert.equal(pattern.test(indexSource), false, message);

test('Index delegates persistent ledger routes and keeps root ownership', () => {
  includes(/import\s+\{[^}]*\bLedgerTabPage\b[^}]*\}\s+from\s+['"]\.\/ledger\/LedgerTabPage['"]/,
    'Index must import LedgerTabPage');
  includes(/LedgerTabPage\s*\([\s\S]*?screen:\s*\$screen[\s\S]*?monthCursor:\s*\$monthCursor[\s\S]*?pendingDeleteId:\s*\$pendingDeleteId/,
    'Index must link route, month, and delete state into LedgerTabPage');
  includes(/LedgerTabPage\s*\([\s\S]*?entries:\s*this\.entries[\s\S]*?entriesViewRevision:\s*this\.entriesViewRevision[\s\S]*?cycleStartDay:\s*this\.cycleStartDay/,
    'Index must provide the current ledger view data');
  includes(/onOpenEditor:\s*\(entry:\s*LedgerEntry\s*\|\s*undefined,\s*fromStatistics:\s*boolean\)\s*=>\s*this\.openEditor\(entry,\s*fromStatistics\)/,
    'editor opens must continue through Index');
  includes(/onListEntries:\s*\(\)\s*=>\s*this\.repository\.listEntries\(\)/,
    'CSV export and preview must read through Index repository ownership');
  includes(/onSaveCsvEntries:[\s\S]*?this\.saveCsvEntries\(entries,\s*duplicateCount,\s*invalidCount\)/,
    'confirmed CSV imports must continue through Index');

  excludes(/import\s+\{[^}]*\b(?:LedgerHomeView|StatisticsView|LedgerSettingsPage|OcrRuleSettingsView)\b/,
    'Index must not import persistent ledger views directly');
  for (const methodName of ['monthRange', 'monthEntries', 'monthEntryGroupsByDay', 'monthTotal', 'monthLabel', 'moveMonth']) {
    excludes(new RegExp(`private\\s+(?:async\\s+)?${methodName}\\s*\\(`),
      `${methodName} must move to the ledger-tab layer or home-data module`);
  }

  includes(/Tabs\s*\(/, 'Index must retain the root tab shell');
  includes(/new\s+LedgerRepository\(/, 'Index must retain repository ownership');
  includes(/repository\.(?:addEntry|updateEntry|deleteEntry|addEntries)\(/,
    'database mutations must remain in Index');
  includes(/private\s+ledgerEditorScreen\s*\(/, 'Index must retain the root editor overlay');
  includes(/private\s+ocrImportScreen\s*\(/, 'Index must retain the root OCR import overlay');
  includes(/private\s+deleteConfirmationView\s*\(/, 'Index must retain the root delete confirmation');
  includes(/ledgerTabBackRequestRevision\+\+/, 'hardware back must be forwarded for nested ledger-tab routes');
});
