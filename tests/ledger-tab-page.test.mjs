import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const moduleUrl = new URL('../entry/src/main/ets/pages/ledger/LedgerTabPage.ets', import.meta.url);

test('LedgerTabPage owns persistent ledger routes and their presentation state', () => {
  const modulePath = fileURLToPath(moduleUrl);
  assert.ok(existsSync(modulePath), 'LedgerTabPage.ets must exist');
  const source = readFileSync(modulePath, 'utf8');

  assert.match(source, /export type LedgerScreen\s*=\s*'ledger'\s*\|\s*'editor'\s*\|\s*'statistics'\s*\|\s*'import'\s*\|\s*'settings'\s*\|\s*'ocrRules'/);
  assert.match(source, /export struct LedgerTabPage/);
  assert.match(source, /@Link\s+screen:\s*LedgerScreen/);
  assert.match(source, /@Watch\('onHomeDataInputsChanged'\)\s*@Link\s+monthCursor:\s*number/);
  assert.match(source, /@Link\s+monthCursor:\s*number/);
  assert.match(source, /@Link\s+pendingDeleteId:\s*string/);
  assert.match(source, /@Prop\s+entries:\s*LedgerEntry\[\]/);
  assert.match(source, /@Watch\('onHomeDataInputsChanged'\)\s*@Prop\s+entriesViewRevision:\s*number/);
  assert.match(source, /@Watch\('onHomeDataInputsChanged'\)\s*@Prop\s+cycleStartDay:\s*number/);
  assert.match(source, /@Watch\('onBackRequestChanged'\)\s*@Prop\s+backRequestRevision:\s*number/);

  for (const component of ['LedgerHomeView', 'StatisticsView', 'LedgerSettingsPage', 'OcrRuleSettingsView']) {
    assert.match(source, new RegExp(`\\b${component}\\s*\\(`), `${component} must be composed by LedgerTabPage`);
  }
  assert.match(source, /buildLedgerHomeData\(/);
  assert.match(source, /moveLedgerMonthCursor\(/);
  assert.match(source, /selectedRankValue/);
  assert.match(source, /ledgerScrollOffset/);
  assert.match(source, /restoreLedgerScrollOnAppear/);
  assert.match(source, /selectedRankValue\s*=\s*''/);
  assert.match(source, /this\.screen\s*=\s*'settings'/);
  assert.match(source, /this\.screen\s*=\s*'ledger'/);
  assert.doesNotMatch(source, /LedgerRepository/);
});
