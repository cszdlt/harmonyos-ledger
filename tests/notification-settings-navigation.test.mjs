import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';

const pageUrl = new URL('../entry/src/main/ets/pages/notifications/NotificationSettingsPage.ets', import.meta.url);

function createSettingsPage(dialogIndex, draftChanged = true) {
  const Page = loadPageMethods(pageUrl, [
    'requestLeaveSettings', 'reminderDraftHasUnsavedChanges', 'discardReminderDraft', 'closeReminderSourcePicker'
  ]);
  const savedDraft = {
    enabled: false, bundleName: 'com.example.clock', keyword: '下班打卡成功',
    startTime: '17:00', deadlineTime: '20:00'
  };
  const draft = {
    ...savedDraft,
    enabled: draftChanged,
    keyword: draftChanged ? '已修改关键词' : savedDraft.keyword
  };
  const page = Object.assign(new Page(), {
    reminderSourcePickerOpen: false,
    reminderSourceRequest: 4,
    reminderSourceLoading: false,
    reminderDraft: draft,
    persistedReminderDraft: savedDraft,
    leaveConfirmationOpen: false,
    onBackCount: 0,
    onBack() { this.onBackCount++; },
    getUIContext() {
      return { getPromptAction: () => ({ showDialog: async () => ({ index: dialogIndex }) }) };
    }
  });
  return page;
}

test('system back from the reminder source picker closes only the picker', async () => {
  const page = createSettingsPage(1);
  page.reminderSourcePickerOpen = true;

  await page.requestLeaveSettings();

  assert.equal(page.reminderSourcePickerOpen, false);
  assert.equal(page.reminderSourceRequest, 5);
  assert.equal(page.onBackCount, 0);
});

test('leaving without reminder changes returns immediately', async () => {
  const page = createSettingsPage(0, false);

  await page.requestLeaveSettings();

  assert.equal(page.onBackCount, 1);
});

test('leaving with a changed reminder draft offers to keep editing, discard, or save', async () => {
  const page = createSettingsPage(0);
  let saved = 0;
  page.saveReminderSettings = async () => { saved++; return true; };

  await page.requestLeaveSettings();

  assert.equal(saved, 0);
  assert.equal(page.onBackCount, 0);
  assert.equal(page.reminderDraft.keyword, '已修改关键词');
});

test('discarding a changed reminder draft restores the saved values before returning', async () => {
  const page = createSettingsPage(1);

  await page.requestLeaveSettings();

  assert.equal(page.onBackCount, 1);
  assert.equal(page.reminderDraft.enabled, false);
  assert.equal(page.reminderDraft.keyword, '下班打卡成功');
});

test('saving a changed reminder draft returns only after saving succeeds', async () => {
  const page = createSettingsPage(2);
  let saved = 0;
  page.saveReminderSettings = async () => { saved++; return true; };

  await page.requestLeaveSettings();

  assert.equal(saved, 1);
  assert.equal(page.onBackCount, 1);
});

test('a failed save keeps the user on reminder settings', async () => {
  const page = createSettingsPage(2);
  page.saveReminderSettings = async () => false;

  await page.requestLeaveSettings();

  assert.equal(page.onBackCount, 0);
});
