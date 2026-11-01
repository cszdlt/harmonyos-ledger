import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPageMethods } from './helpers/page-methods.mjs';

test('笔数较上期减少时只显示一个负号', () => {
  const StatisticsOverview = loadPageMethods(
    new URL('../entry/src/main/ets/components/statistics/StatisticsOverview.ets', import.meta.url),
    ['countChange']
  );
  const overview = new StatisticsOverview();
  assert.equal(overview.countChange(3, 5), '较上期 −2 笔（−40.0%）');
});
