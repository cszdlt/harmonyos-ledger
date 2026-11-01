import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { OcrImportCoordinator } from '../entry/src/main/ets/services/OcrImportCoordinator.ets';
import { formatDateOnly, formatDateTime, hasClockTime, makeId, parseAmountFen, parseDateTime }
  from '../entry/src/main/ets/model/LedgerModels.ets';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

function draft() {
  return { id: 'draft', source: 'wechat', merchant: '早餐店', dateText: '2026-10-15 12:30',
    hasTime: true, amountText: '10.00', direction: 'expense', category: '餐饮',
    checked: true, isRefund: false, warnings: [] };
}

function ocrPage() {
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/import/OcrImportPage.ets', import.meta.url), [
    'confirmDrafts', 'persistDrafts', 'requestLeaveImport', 'cancelImport', 'resetImportReview',
    'setDraftText', 'setDraftDirection', 'toggleDraft', 'clearDraftValidationError',
    'onBackRequestChanged', 'startSessionForRevision',
    'startImport', 'startSharedImport'
  ], { OcrImportCoordinator, hasClockTime, loadOcrRules: async () => [],
    OcrImporter: { chooseAndRecognize: async () => ({ pages: [] }), recognizeUris: async () => ({ pages: [] }) } });
  const page = new Page();
  Object.assign(page, { drafts: [draft()], entries: [], saving: false, ocrLoading: false, ocrRequestId: 0,
    unclassifiedPages: [], draftValidationErrors: [], reviewMessage: '', ocrRawText: 'original',
    shareImportMode: false, pendingImportDiscardConfirmation: false,
    handledSessionRevision: 0, sessionRevision: 0, exitCount: 0, toastMessages: [] });
  page.onBack = () => { page.exitCount++; };
  page.onToast = message => page.toastMessages.push(message);
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  return page;
}

function editorPage() {
  const Page = loadPageMethods(new URL('../entry/src/main/ets/pages/ledger/LedgerEditorPage.ets', import.meta.url), [
    'saveEditor', 'requestLeaveEditor', 'discardEditor', 'setFormValue', 'chooseEditorDate',
    'onBackRequestChanged', 'startSessionForRevision'
  ], { formatDateOnly, formatDateTime, hasClockTime, makeId, parseAmountFen, parseDateTime });
  const page = new Page();
  Object.assign(page, { editingId: '', editingSource: 'manual', saving: false, formDateText: '2026-10-15 12:30',
    formAmountText: '10.00', formMerchant: '早餐店', formCategory: '餐饮', formNote: '', formDirection: 'expense',
    editorDirty: true, editorDateError: '', editorAmountError: '', pendingDiscardConfirmation: false,
    handledSessionRevision: 0, sessionRevision: 0, exitCount: 0 });
  page.onBack = () => { page.exitCount++; };
  return page;
}

test('OCR confirmation submits once while saving and exits once after success', async () => {
  const page = ocrPage();
  const pending = deferred();
  const plans = [];
  page.onConfirmDrafts = plan => { plans.push(plan); return pending.promise; };
  const first = page.confirmDrafts();
  const second = page.confirmDrafts();
  const savingState = page.saving;
  pending.resolve({ success: true, message: '新增 1 笔' });
  await Promise.all([first, second]);
  assert.equal(plans.length, 1);
  assert.equal(plans[0].additions.length, 1);
  assert.equal(savingState, true);
  assert.equal(page.saving, false);
  assert.equal(page.exitCount, 1);
  assert.equal(page.drafts.length, 0);
});

test('OCR saving blocks hardware back cancellation editing and session replacement', async () => {
  const page = ocrPage();
  const pending = deferred();
  page.onConfirmDrafts = () => pending.promise;
  const saving = page.confirmDrafts();
  const original = structuredClone(page.drafts);
  page.onBackRequestChanged();
  page.requestLeaveImport();
  page.cancelImport();
  page.setDraftText('draft', 'amountText', '20.00');
  page.setDraftDirection('draft', 'income');
  page.toggleDraft('draft');
  page.sessionRevision++;
  page.startSessionForRevision();
  assert.deepEqual(page.drafts, original);
  assert.equal(page.exitCount, 0);
  assert.equal(page.pendingImportDiscardConfirmation, false);
  pending.resolve({ success: false, message: '写入失败' });
  await saving;
});

test('failed OCR saves retain drafts and release the lock for a successful retry', async () => {
  const page = ocrPage();
  let attempts = 0;
  page.onConfirmDrafts = async () => ++attempts === 1 ?
    { success: false, message: '写入失败' } : { success: true, message: '新增 1 笔' };
  await page.confirmDrafts();
  assert.equal(page.saving, false);
  assert.equal(page.drafts.length, 1);
  assert.equal(page.reviewMessage, '写入失败');
  assert.equal(page.exitCount, 0);
  await page.confirmDrafts();
  assert.equal(attempts, 2);
  assert.equal(page.exitCount, 1);
});

test('a rejected OCR save releases the lock without losing the review', async () => {
  const page = ocrPage();
  page.onConfirmDrafts = async () => { throw new Error('write rejected'); };
  await page.confirmDrafts();
  assert.equal(page.saving, false);
  assert.equal(page.drafts.length, 1);
  assert.match(page.reviewMessage, /write rejected/);
});

test('manual creation submits once while saving and exits after success', async () => {
  const page = editorPage();
  const pending = deferred();
  const writes = [];
  page.onSave = (entry, isEditing) => { writes.push({ entry, isEditing }); return pending.promise; };
  const first = page.saveEditor();
  const second = page.saveEditor();
  const savingState = page.saving;
  pending.resolve(true);
  await Promise.all([first, second]);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].isEditing, false);
  assert.equal(writes[0].entry.amountFen, 1000);
  assert.equal(savingState, true);
  assert.equal(page.saving, false);
  assert.equal(page.exitCount, 1);
  assert.equal(page.editorDirty, false);
});

test('manual saving blocks back discard editing and date picker callbacks', async () => {
  const page = editorPage();
  let dateDialog;
  page.getUIContext = () => ({ showDatePickerDialog: value => { dateDialog = value; },
    runScopedTask: action => action() });
  page.chooseEditorDate();
  const pending = deferred();
  page.onSave = () => pending.promise;
  const saving = page.saveEditor();
  page.onBackRequestChanged();
  page.requestLeaveEditor();
  page.discardEditor();
  page.setFormValue('amount', '20.00');
  dateDialog.onDateAccept(new Date(2026, 9, 16));
  page.sessionRevision++;
  page.startSessionForRevision();
  assert.equal(page.formAmountText, '10.00');
  assert.equal(page.formDateText, '2026-10-15 12:30');
  assert.equal(page.exitCount, 0);
  assert.equal(page.pendingDiscardConfirmation, false);
  pending.resolve(false);
  await saving;
});

test('manual failed and rejected saves allow retry without leaving the editor', async () => {
  const page = editorPage();
  page.onSave = async () => false;
  await page.saveEditor();
  assert.equal(page.saving, false);
  assert.equal(page.editorDirty, true);
  assert.equal(page.exitCount, 0);
  page.onSave = async () => { throw new Error('write rejected'); };
  await assert.rejects(page.saveEditor(), /write rejected/);
  assert.equal(page.saving, false);
  page.onSave = async () => true;
  await page.saveEditor();
  assert.equal(page.exitCount, 1);
});

test('manual date selection preserves accepted single-digit minute precision', () => {
  const page = editorPage();
  page.formDateText = '2026-10-15 12:3';
  let dateDialog;
  page.getUIContext = () => ({ showDatePickerDialog: value => { dateDialog = value; },
    runScopedTask: action => action() });
  page.chooseEditorDate();
  dateDialog.onDateAccept(new Date(2026, 9, 16));
  assert.equal(page.formDateText, '2026-10-16 12:03');
});
