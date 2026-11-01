import test from 'node:test';
import assert from 'node:assert/strict';
import { OcrImportCoordinator } from '../entry/src/main/ets/services/OcrImportCoordinator.ets';
import { createDefaultOcrRules } from '../entry/src/main/ets/services/ocrRules/OcrRuleEngine.ets';

function line(text, centerY, left = 10, right = 900) {
  return { text, left, top: centerY - 10, right, bottom: centerY + 10, centerY, height: 20 };
}

function parse(lines, overrides = {}) {
  const rule = { ...createDefaultOcrRules()[0], ...overrides };
  return OcrImportCoordinator.parsePage(lines, rule.source, [], [rule], [], undefined, 1000);
}

test('adjacent complete rows keep their own date time and merchant', () => {
  const drafts = parse([
    line('2026-10-03 10:15 早餐店 -12.00', 100),
    line('2026-10-04 18:45 书店 -34.00', 130)
  ]);
  assert.deepEqual(drafts.map(({ dateText, merchant, amountText }) => ({ dateText, merchant, amountText })), [
    { dateText: '2026-10-03 10:15', merchant: '早餐店', amountText: '12.00' },
    { dateText: '2026-10-04 18:45', merchant: '书店', amountText: '34.00' }
  ]);
});

test('adjacent failed and refund rows cannot change normal transactions', () => {
  const drafts = parse([
    line('2026-10-03 10:00 早餐店 -12.00', 100),
    line('2026-10-03 11:00 失败订单 -20.00 交易失败', 130),
    line('2026-10-03 12:00 书店 -30.00', 160),
    line('2026-10-03 13:00 退款 +40.00', 190),
    line('2026-10-03 14:00 午餐店 -50.00', 220)
  ]);
  assert.deepEqual(drafts.map(({ dateText, isRefund, direction }) => ({ dateText, isRefund, direction })), [
    { dateText: '2026-10-03 10:00', isRefund: false, direction: 'expense' },
    { dateText: '2026-10-03 12:00', isRefund: false, direction: 'expense' },
    { dateText: '2026-10-03 13:00', isRefund: true, direction: undefined },
    { dateText: '2026-10-03 14:00', isRefund: false, direction: 'expense' }
  ]);
});

test('the previous receipt time cannot supply a date for an undated next receipt', () => {
  const drafts = parse([
    line('早餐店', 100), line('-12.00', 120), line('2026-10-03 10:15', 140),
    line('无日期商户', 160), line('-34.00', 180)
  ]);
  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].merchant, '早餐店');
  assert.equal(drafts[0].dateText, '2026-10-03 10:15');
});

test('a standalone date heading is shared by its following row transactions', () => {
  const drafts = parse([
    line('2026-10-03', 80), line('早餐店 -12.00', 100), line('书店 -34.00', 120)
  ]);
  assert.deepEqual(drafts.map(({ dateText, merchant, hasTime }) => ({ dateText, merchant, hasTime })), [
    { dateText: '2026-10-03', merchant: '早餐店', hasTime: false },
    { dateText: '2026-10-03', merchant: '书店', hasTime: false }
  ]);
});

test('a timed heading before the first receipt remains available to that receipt', () => {
  const drafts = parse([
    line('2026-10-03 10:15', 100), line('早餐店', 120), line('-12.00', 140)
  ]);
  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].dateText, '2026-10-03 10:15');
  assert.equal(drafts[0].merchant, '早餐店');
});

test('each receipt keeps the closer timed date above its amount', () => {
  const drafts = parse([
    line('2026-10-03 10:15', 80), line('ShopA -12.00', 100),
    line('2026-10-04 18:45', 130), line('ShopB -34.00', 150)
  ]);
  assert.deepEqual(drafts.map(({ dateText, merchant, amountText }) => ({ dateText, merchant, amountText })), [
    { dateText: '2026-10-03 10:15', merchant: 'ShopA', amountText: '12.00' },
    { dateText: '2026-10-04 18:45', merchant: 'ShopB', amountText: '34.00' }
  ]);
});

test('a timed date equally close to two undated receipts is not assigned by guesswork', () => {
  const drafts = parse([
    line('ShopA -12.00', 100), line('2026-10-03 10:15', 130), line('ShopB -34.00', 160)
  ]);
  assert.equal(drafts.length, 0);
});

test('separate status and date lines stay with their receipt', () => {
  const drafts = parse([
    line('2026-10-03 09:00 正常订单 -10.00', 60),
    line('失败订单 -20.00', 100), line('交易失败', 120), line('2026-10-03 10:00', 140),
    line('退款订单 +30.00', 180), line('退款', 200), line('2026-10-03 11:00', 220),
    line('2026-10-03 12:00 后续正常订单 -40.00', 280)
  ]);
  assert.deepEqual(drafts.map(({ amountText, isRefund, direction }) => ({ amountText, isRefund, direction })), [
    { amountText: '10.00', isRefund: false, direction: 'expense' },
    { amountText: '30.00', isRefund: true, direction: undefined },
    { amountText: '40.00', isRefund: false, direction: 'expense' }
  ]);
});

test('configured columns read the current row before neighbouring fields', () => {
  const drafts = parse([
    line('2026-10-03 10:15', 100, 10, 220), line('商户：早餐店', 100, 300, 500), line('-12.00', 100, 700, 950),
    line('2026-10-04 18:45', 130, 10, 220), line('商户：书店', 130, 300, 500), line('-34.00', 130, 700, 950)
  ], {
    merchantPattern: { pattern: '商户：([^\\s]+)', groupIndex: 1 },
    columns: { date: { left: 0, right: 0.25 }, time: { left: 0, right: 0.25 },
      merchant: { left: 0.25, right: 0.6 }, amount: { left: 0.65, right: 1 } }
  });
  assert.deepEqual(drafts.map(({ dateText, merchant }) => ({ dateText, merchant })), [
    { dateText: '2026-10-03 10:15', merchant: '早餐店' },
    { dateText: '2026-10-04 18:45', merchant: '书店' }
  ]);
});
