import test from 'node:test';
import assert from 'node:assert/strict';

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

test('home data calculates balance from income and expense in the selected cycle', async () => {
  const { buildLedgerHomeData } = await import('../entry/src/main/ets/services/LedgerHomeData.ets');
  const entries = [
    entry('before-cycle-income', 0, 14, 10000, 'income'),
    entry('cycle-income', 0, 15, 500, 'income'),
    entry('cycle-expense', 0, 15, 200, 'expense'),
    entry('cycle-end-income', 1, 14, 50, 'income'),
    entry('cycle-end-expense', 1, 14, 500, 'expense'),
    entry('after-cycle-expense', 1, 15, 10000, 'expense')
  ];

  const homeData = buildLedgerHomeData(entries, new Date(2026, 0, 20).getTime(), 15);

  assert.equal(homeData.balanceTotalFen, -150);
});

test('home data reports zero balance when the selected cycle has no entries', async () => {
  const { buildLedgerHomeData } = await import('../entry/src/main/ets/services/LedgerHomeData.ets');

  const homeData = buildLedgerHomeData([], new Date(2026, 0, 20).getTime(), 15);

  assert.equal(homeData.balanceTotalFen, 0);
});

test('money formatting keeps a negative balance sign before the currency symbol', async () => {
  const { formatMoney } = await import('../entry/src/main/ets/model/LedgerModels.ets');

  assert.equal(formatMoney(-150), '-¥1.50');
});
