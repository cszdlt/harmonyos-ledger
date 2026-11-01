import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';
import { moveLedgerMonthCursor } from '../entry/src/main/ets/services/LedgerHomeData.ets';
import {
  buildLedgerStatistics,
  previousStatisticsRange,
  statisticsRange
} from '../entry/src/main/ets/services/LedgerStatistics.ets';

const StatisticsView = loadPageMethods(
  new URL('../entry/src/main/ets/pages/statistics/StatisticsView.ets', import.meta.url),
  ['movePeriod', 'refreshStatistics'],
  { moveLedgerMonthCursor, buildLedgerStatistics, previousStatisticsRange, statisticsRange }
);

function createView(period = 'month') {
  const page = new StatisticsView();
  page.period = period;
  page.cursor = new Date(2026, 9, 15, 13).getTime();
  page.cycleStartDay = 15;
  page.customStart = 0;
  page.customEnd = 0;
  page.statisticsRefreshKey = 0;
  page.entries = [7, 8, 9, 10].map((month, index) => ({
    id: String(month),
    happenedAt: new Date(2026, month, 20, 12).getTime(),
    hasTime: true,
    amountFen: (index + 1) * 100,
    direction: 'expense',
    source: 'manual',
    merchant: '测试商户',
    category: '测试',
    note: ''
  }));
  return page;
}

test('统计月翻页从当前真实账期移动并刷新该期与上期数据', () => {
  for (const [offset, firstDay, lastDay, expenseFen, previousExpenseFen] of [
    [-1, '2026-09-15', '2026-10-14', 200, 100],
    [1, '2026-11-15', '2026-12-14', 400, 300]
  ]) {
    const page = createView();
    page.movePeriod(offset);

    assert.equal(page.statistics.trend[0].key, firstDay);
    assert.equal(page.statistics.trend.at(-1).key, lastDay);
    assert.equal(page.statistics.expenseFen, expenseFen);
    assert.equal(page.previousStatistics.expenseFen, previousExpenseFen);

    page.movePeriod(-offset);
    assert.equal(page.statistics.trend[0].key, '2026-10-15');
    assert.equal(page.statistics.trend.at(-1).key, '2026-11-14');
    assert.equal(page.statistics.expenseFen, 300);
  }
});

test('统计年翻页仍按自然年移动', () => {
  const page = createView('year');
  page.movePeriod(-1);
  assert.equal(page.cursor, new Date(2025, 0, 1).getTime());
  assert.equal(page.statistics.trend[0].key, '2025-01');
  assert.equal(page.statistics.trend.at(-1).key, '2025-12');
});
