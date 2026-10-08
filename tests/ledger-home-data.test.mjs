import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const moduleUrl = new URL('../entry/src/main/ets/services/LedgerHomeData.ets', import.meta.url);

function entry(id, monthIndex, day, amountFen, direction) {
  return {
    id: id,
    happenedAt: new Date(2026, monthIndex, day, 12).getTime(),
    hasTime: true,
    amountFen: amountFen,
    direction: direction,
    source: 'manual',
    merchant: id,
    category: '测试',
    note: ''
  };
}

test('home data filters the selected cycle, groups days, totals fen, and labels its range', async () => {
  assert.ok(existsSync(fileURLToPath(moduleUrl)), 'LedgerHomeData.ets must exist');
  const { buildLedgerHomeData } = await import('../entry/src/main/ets/services/LedgerHomeData.ets');
  const entries = [
    entry('before-cycle', 0, 14, 999, 'expense'),
    entry('jan-income', 0, 15, 125, 'income'),
    entry('jan-expense', 0, 15, 50, 'expense'),
    entry('feb-expense', 1, 14, 200, 'expense'),
    entry('after-cycle', 1, 15, 900, 'income')
  ];

  const homeData = buildLedgerHomeData(entries, new Date(2026, 0, 20).getTime(), 15);

  assert.deepEqual(homeData.monthEntries.map((item) => item.id), [
    'jan-income', 'jan-expense', 'feb-expense'
  ]);
  assert.deepEqual(homeData.dayGroups.map((group) => ({
    dateKey: group.dateKey,
    entryIds: group.entries.map((item) => item.id),
    expenseTotalFen: group.expenseTotalFen,
    incomeTotalFen: group.incomeTotalFen
  })), [
    {
      dateKey: '2026-01-15',
      entryIds: ['jan-income', 'jan-expense'],
      expenseTotalFen: 50,
      incomeTotalFen: 125
    },
    {
      dateKey: '2026-02-14',
      entryIds: ['feb-expense'],
      expenseTotalFen: 200,
      incomeTotalFen: 0
    }
  ]);
  assert.equal(homeData.incomeTotalFen, 125);
  assert.equal(homeData.expenseTotalFen, 250);
  assert.equal(homeData.monthLabel, '2026年1月15日—2月14日');
});

test('month navigation resets to the first day without carrying a long month day', async () => {
  assert.ok(existsSync(fileURLToPath(moduleUrl)), 'LedgerHomeData.ets must exist');
  const { moveLedgerMonthCursor } = await import('../entry/src/main/ets/services/LedgerHomeData.ets');

  assert.equal(
    moveLedgerMonthCursor(new Date(2026, 0, 31, 16).getTime(), 1),
    new Date(2026, 1, 1).getTime()
  );
  assert.equal(
    moveLedgerMonthCursor(new Date(2026, 0, 1).getTime(), -1),
    new Date(2025, 11, 1).getTime()
  );
});
