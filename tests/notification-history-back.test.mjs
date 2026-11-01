import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadPageMethods } from './helpers/page-methods.mjs';

const pageUrl = new URL('../entry/src/main/ets/pages/notifications/NotificationHistoryView.ets', import.meta.url);
const HistoryView = loadPageMethods(pageUrl, ['onBackRequestChanged', 'closeOverlay', 'updateBackLayerState']);

function createHistoryView(state) {
  return Object.assign(new HistoryView(), {
    overlayOpen: false,
    sourcePickerOpen: false,
    filtersExpanded: false,
    selectedEntry: undefined,
    showTechnicalDetails: false,
    ...state
  });
}

test('system back closes the source picker before the expanded filters', () => {
  const view = createHistoryView({ sourcePickerOpen: true, filtersExpanded: true, overlayOpen: true });

  view.onBackRequestChanged();

  assert.equal(view.sourcePickerOpen, false);
  assert.equal(view.filtersExpanded, true);
  assert.equal(view.overlayOpen, true);
});

test('system back collapses expanded filters before leaving notification history', () => {
  const view = createHistoryView({ filtersExpanded: true, overlayOpen: true });

  view.onBackRequestChanged();

  assert.equal(view.filtersExpanded, false);
  assert.equal(view.overlayOpen, false);
});

test('opening settings clears history back layers before changing routes', () => {
  const SettingsHistoryView = loadPageMethods(pageUrl, ['openSettings', 'updateBackLayerState']);
  let opened = 0;
  const view = Object.assign(new SettingsHistoryView(), {
    sourcePickerOpen: false,
    selectedEntry: undefined,
    showTechnicalDetails: false,
    filtersExpanded: true,
    overlayOpen: true,
    onOpenSettings() { opened++; }
  });

  view.openSettings();

  assert.equal(view.filtersExpanded, false);
  assert.equal(view.overlayOpen, false);
  assert.equal(opened, 1);
});

test('empty-history settings button clears back layers before changing routes', () => {
  const source = readFileSync(pageUrl, 'utf8');
  const emptyStateSettingsButton = source.match(/Button\('前往通知设置'\)[\s\S]*?\.onClick\(\(\) => this\.(\w+)\(\)\)/);

  assert.ok(emptyStateSettingsButton, 'empty-history settings button should have a click handler');
  assert.equal(emptyStateSettingsButton[1], 'openSettings');
});
