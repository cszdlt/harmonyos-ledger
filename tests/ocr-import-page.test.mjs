import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const pagePath = new URL('../entry/src/main/ets/pages/import/OcrImportPage.ets', import.meta.url);
const pageSource = existsSync(fileURLToPath(pagePath)) ? readFileSync(pagePath, 'utf8') : '';
const includes = (pattern, message) => assert.ok(pattern.test(pageSource), message);

test('OcrImportPage exposes the approved session and save contract', () => {
  includes(/export\s+interface\s+OcrImportSaveResult/, 'the save result type must be exported');
  for (const inputName of [
    'entries', 'shareImportMode', 'sharedImportUris', 'sharedImportError', 'sessionRevision', 'backRequestRevision'
  ]) {
    includes(new RegExp(`@Prop\\s+${inputName}\\s*:`), `${inputName} must be a page input`);
  }
  includes(/onConfirmDrafts\s*:/, 'the page must receive the repository callback');
  includes(/onBack\s*:/, 'the page must receive the route callback');
  includes(/onToast\s*:/, 'the page must receive the toast callback');
});

test('OcrImportPage retains OCR, share, review, and return flows', () => {
  assert.notEqual(pageSource, '', 'OcrImportPage.ets must exist');
  includes(/OcrImportView\s*\(/, 'the page must compose the existing review view');
  includes(/@Watch\('[^']+'\)[\s\S]{0,100}\bsessionRevision\s*:/,
    'session changes must start or reset the import flow');
  includes(/@Watch\('[^']+'\)[\s\S]{0,100}\bbackRequestRevision\s*:/,
    'back requests must reach the page');
  includes(/OcrImporter\.chooseAndRecognize\(/, 'ordinary image selection must remain available');
  includes(/OcrImporter\.recognizeUris\(/, 'share imports must recognize received URIs');
  includes(/requestId\s*!==\s*this\.ocrRequestId/, 'stale picker results must be discarded');
  includes(/OcrImportCoordinator\.parsePages\(/, 'recognized pages must use the existing coordinator');
  includes(/OcrImportCoordinator\.parsePage\(/, 'manual source selection must use the existing coordinator');
  includes(/OcrImportCoordinator\.prepareConfirmation\(/, 'drafts must be validated before saving');
  includes(/duplicateMessage\s*:/, 'duplicate feedback must remain in the review view');
  includes(/onResolvePage\s*:/, 'unclassified pages must remain resolvable');
});

test('OcrImportPage cancels active share imports on hardware back', () => {
  includes(/@State\s+private\s+shareImportStarted:\s*boolean\s*=\s*false;/,
    'the page must track whether a valid share import has started');
  includes(/this\.shareImportStarted\s*=\s*false;/,
    'new import sessions must clear the share started state');
  includes(/if \(this\.shareImportMode\) \{\s*if \(this\.shareImportStarted && !this\.shareImportCompleted && !this\.shareImportCancelled\) \{\s*this\.requestLeaveImport\(\);\s*\} else \{\s*void this\.closeShareImport\(\);\s*\}\s*return;\s*\}/,
    'hardware back must cancel an active share import and close a share outcome directly');
  includes(/private async startSharedImport\(\): Promise<void> \{\s*if \(this\.sharedImportUris\.length === 0\) \{[\s\S]*?\}\s*this\.shareImportStarted = true;/,
    'the share started state must only be set after confirming a received URI');
});
