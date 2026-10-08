import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const indexSource = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const includes = (pattern, message) => assert.ok(pattern.test(indexSource), message);
const excludes = (pattern, message) => assert.equal(pattern.test(indexSource), false, message);

test('Index delegates OCR state to OcrImportPage and keeps repository writes in Index', () => {
  includes(/import\s+\{[^}]*\bOcrImportPage\b[^}]*\}\s+from\s+['"]\.\/import\/OcrImportPage['"]/, 'Index must import OcrImportPage');
  includes(/OcrImportPage\s*\(\s*\{/, 'the route must render OcrImportPage');
  includes(/onConfirmDrafts\s*:\s*\(plan:\s*OcrDraftConfirmationPlan\)\s*=>\s*this\.saveDrafts\(plan\)/,
    'Index must pass repository saving as the confirmation callback');
  includes(/private\s+async\s+saveDrafts\(plan:\s*OcrDraftConfirmationPlan\):\s*Promise<OcrImportSaveResult>/,
    'repository saving must report success or failure');
  includes(/repository\.updateEntry\(entry\)/, 'matched category updates must remain in the repository path');
  includes(/repository\.addEntries\(plan\.additions\)/, 'new entries must remain in the repository path');

  for (const stateName of [
    'drafts', 'unclassifiedPages', 'ocrRawText', 'ocrLoading', 'ocrErrorMessage',
    'reviewMessage', 'draftValidationErrors', 'shareImportCompleted',
    'shareImportCancelled', 'shareImportOutcomeMessage', 'ocrRulesSnapshot', 'ocrRequestId'
  ]) {
    excludes(new RegExp(`private\\s+${stateName}\\s*:`), `${stateName} must move to OcrImportPage`);
  }
  for (const methodName of [
    'applyImportResult', 'startImport', 'startSharedImport', 'resolveUnclassifiedPage',
    'setDraftText', 'setDraftDirection', 'toggleDraft', 'confirmDrafts', 'requestLeaveImport', 'cancelImport'
  ]) {
    excludes(new RegExp(`private\\s+(?:async\\s+)?${methodName}\\s*\\(`), `${methodName} must move to OcrImportPage`);
  }
});
