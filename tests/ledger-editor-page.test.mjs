import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const pagePath = new URL('../entry/src/main/ets/pages/ledger/LedgerEditorPage.ets', import.meta.url);
const pageSource = existsSync(fileURLToPath(pagePath)) ? readFileSync(pagePath, 'utf8') : '';
const includes = (pattern, message) => assert.ok(pattern.test(pageSource), message);

test('LedgerEditorPage exposes the approved edit session and save contract', () => {
  assert.notEqual(pageSource, '', 'LedgerEditorPage.ets must exist');
  includes(/export\s+struct\s+LedgerEditorPage/, 'the page component must be exported');
  includes(/@Watch\('onSessionRevisionChanged'\)\s*@Prop\s+sessionRevision:\s*number/,
    'each editor session must initialize from its input');
  includes(/@Watch\('onBackRequestChanged'\)\s*@Prop\s+backRequestRevision:\s*number/,
    'hardware back requests must reach the page');
  includes(/@Prop\s+editingEntry:\s*LedgerEntry\s*\|\s*undefined/,
    'the page must receive the selected ledger entry');
  includes(/onSave:\s*\(entry:\s*LedgerEntry,\s*isEditing:\s*boolean\)\s*=>\s*Promise<boolean>/,
    'saving must return to the repository owner through a callback');
});

test('LedgerEditorPage owns editable form state and preserves exit validation', () => {
  for (const stateName of [
    'editorDirty', 'editorDateError', 'editorAmountError', 'pendingDiscardConfirmation',
    'formMerchant', 'formDateText', 'formAmountText', 'formDirection', 'formCategory', 'formNote'
  ]) {
    includes(new RegExp(`@State\\s+private\\s+${stateName}\\s*:`), `${stateName} must belong to the page`);
  }
  includes(/LedgerEditorView\s*\(/, 'the page must reuse the existing editor view');
  includes(/parseDateTime\(this\.formDateText\)/, 'the page must validate the entered date');
  includes(/parseAmountFen\(this\.formAmountText\)/, 'the page must validate the entered amount');
  includes(/showDatePickerDialog\(/, 'date selection must remain available');
  includes(/this\.editingEntry\.hasTime\s*\?\s*formatDateTime\(this\.editingEntry\.happenedAt\)\s*:\s*formatDateOnly\(this\.editingEntry\.happenedAt\)/,
    'editing a date-only entry must not invent a time');
  includes(/this\.onSave\(entry,\s*this\.editingId\.length\s*>\s*0\)/,
    'the repository callback must know whether this is an edit');
  includes(/if \(saved\) \{\s*this\.editorDirty = false;\s*this\.onBack\(\);\s*\}/,
    'the page must leave only after a successful save');
  includes(/if \(this\.pendingDiscardConfirmation\) \{\s*this\.pendingDiscardConfirmation = false;\s*return;\s*\}/,
    'hardware back must dismiss an open discard prompt first');
  includes(/this\.pendingDiscardConfirmation\s*=\s*true/, 'dirty forms must ask before leaving');
});
