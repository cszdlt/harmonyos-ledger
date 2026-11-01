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

const cycleNavigationCases = [
  {
    name: '15 号起点前',
    cursor: new Date(2026, 9, 14, 13).getTime(),
    cycleStartDay: 15,
    current: '2026年9月15日—10月14日',
    previous: '2026年8月15日—9月14日',
    next: '2026年10月15日—11月14日'
  },
  {
    name: '15 号起点当天',
    cursor: new Date(2026, 9, 15, 13).getTime(),
    cycleStartDay: 15,
    current: '2026年10月15日—11月14日',
    previous: '2026年9月15日—10月14日',
    next: '2026年11月15日—12月14日'
  },
  {
    name: '15 号起点后',
    cursor: new Date(2026, 9, 31, 13).getTime(),
    cycleStartDay: 15,
    current: '2026年10月15日—11月14日',
    previous: '2026年9月15日—10月14日',
    next: '2026年11月15日—12月14日'
  },
  {
    name: '31 号在平年二月夹取月末',
    cursor: new Date(2026, 1, 28, 13).getTime(),
    cycleStartDay: 31,
    current: '2026年2月28日—3月30日',
    previous: '2026年1月31日—2月27日',
    next: '2026年3月31日—4月29日'
  },
  {
    name: '31 号在三月起点前仍从二月账期移动',
    cursor: new Date(2026, 2, 15, 13).getTime(),
    cycleStartDay: 31,
    current: '2026年2月28日—3月30日',
    previous: '2026年1月31日—2月27日',
    next: '2026年3月31日—4月29日'
  },
  {
    name: '31 号在闰年二月夹取月末',
    cursor: new Date(2028, 1, 29, 13).getTime(),
    cycleStartDay: 31,
    current: '2028年2月29日—3月30日',
    previous: '2028年1月31日—2月28日',
    next: '2028年3月31日—4月29日'
  },
  {
    name: '15 号账期跨年',
    cursor: new Date(2026, 0, 15, 13).getTime(),
    cycleStartDay: 15,
    current: '2026年1月15日—2月14日',
    previous: '2025年12月15日—2026年1月14日',
    next: '2026年2月15日—3月14日'
  }
];

for (const scenario of cycleNavigationCases) {
  test(`${scenario.name}：翻页选择相邻账期并可往返`, async () => {
    const { buildLedgerHomeData, moveLedgerMonthCursor } = await import('../entry/src/main/ets/services/LedgerHomeData.ets');

    for (const [offset, expected] of [[-1, scenario.previous], [1, scenario.next]]) {
      const moved = moveLedgerMonthCursor(scenario.cursor, offset, scenario.cycleStartDay);
      assert.equal(buildLedgerHomeData([], moved, scenario.cycleStartDay).monthLabel, expected);

      const returned = moveLedgerMonthCursor(moved, -offset, scenario.cycleStartDay);
      assert.equal(buildLedgerHomeData([], returned, scenario.cycleStartDay).monthLabel, scenario.current);
    }
  });
}
