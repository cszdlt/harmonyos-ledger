import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const indexSource = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const includes = (pattern, message) => assert.ok(pattern.test(indexSource), message);
const excludes = (pattern, message) => assert.equal(pattern.test(indexSource), false, message);

test('Index delegates both editor presentations and keeps repository writes', () => {
  includes(/import\s+\{[^}]*\bLedgerEditorPage\b[^}]*\}\s+from\s+['"]\.\/ledger\/LedgerEditorPage['"]/,
    'Index must import LedgerEditorPage');
  assert.equal([...indexSource.matchAll(/this\.editorPage\(\)/g)].length, 2,
    'ledger and statistics editing must both use the shared editor page builder');
  includes(/private\s+editorPage\(\)[\s\S]*?LedgerEditorPage\s*\(\s*\{/,
    'the shared builder must create LedgerEditorPage');
  includes(/onSave:\s*\(entry:\s*LedgerEntry,\s*isEditing:\s*boolean\)\s*=>\s*this\.saveEditor\(entry,\s*isEditing\)/,
    'Index must provide a save callback to the editor page');
  includes(/private\s+async\s+saveEditor\(entry:\s*LedgerEntry,\s*isEditing:\s*boolean\):\s*Promise<boolean>/,
    'Index must retain the save operation');
  includes(/repository\.updateEntry\(savedEntry\)/, 'existing entries must still update through the repository');
  includes(/repository\.addEntry\(savedEntry\)/, 'new entries must still be added through the repository');
  includes(/source:\s*existing === undefined \? 'manual' : existing\.source/,
    'editing an entry must retain its current source');
  includes(/if \(!this\.statisticsEditorOpen\) \{\s*this\.monthCursor = savedEntry\.happenedAt;/,
    'only a normal editor save may move the selected ledger month');
  includes(/this\.editorBackRequestRevision\+\+/, 'hardware back must be forwarded to the editor page');

  for (const stateName of [
    'editorDirty', 'editorDateError', 'editorAmountError', 'pendingDiscardConfirmation',
    'formMerchant', 'formDateText', 'formAmountText', 'formDirection', 'formCategory', 'formNote'
  ]) {
    excludes(new RegExp(`private\\s+${stateName}\\s*:`), `${stateName} must move to LedgerEditorPage`);
  }
  for (const methodName of ['setFormValue', 'chooseEditorDate', 'requestLeaveEditor', 'discardEditor']) {
    excludes(new RegExp(`private\\s+(?:async\\s+)?${methodName}\\s*\\(`),
      `${methodName} must move to LedgerEditorPage`);
  }
});
