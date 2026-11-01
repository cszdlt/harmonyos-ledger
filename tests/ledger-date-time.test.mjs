import test from 'node:test';
import assert from 'node:assert/strict';
import { hasClockTime, parseDateTime } from '../entry/src/main/ets/model/LedgerModels.ets';
import { OcrImportCoordinator } from '../entry/src/main/ets/services/OcrImportCoordinator.ets';

test('date parsing rejects hours and minutes that Date would silently normalize', () => {
  for (const time of ['24:00', '99:00', '12:60', '12:99', '23:99']) {
    const value = '2026-10-15 ' + time;
    assert.equal(parseDateTime(value), undefined, value);
    assert.equal(hasClockTime(value), false, value);
  }
});

test('clock precision agrees with accepted single-digit minutes and date-only inputs', () => {
  const cases = [
    ['2026-10-15 12:3', new Date(2026, 9, 15, 12, 3).getTime(), true],
    ['2026/10/15 0:00', new Date(2026, 9, 15).getTime(), true],
    ['2026年10月15日 23:59', new Date(2026, 9, 15, 23, 59).getTime(), true],
    ['2026-10-15', new Date(2026, 9, 15).getTime(), false],
    ['invalid 12:30', undefined, false],
    ['2026-02-30 12:30', undefined, false]
  ];
  for (const [value, expected, timed] of cases) {
    assert.equal(parseDateTime(value), expected, value);
    assert.equal(hasClockTime(value), timed, value);
  }
});

test('OCR confirmation refuses an edited overflowing time before creating an entry', () => {
  const plan = OcrImportCoordinator.prepareConfirmation([{
    id: 'draft', source: 'wechat', merchant: '早餐店', dateText: '2026-10-15 12:99',
    hasTime: false, amountText: '10.00', direction: 'expense', category: '其他',
    checked: true, isRefund: false, warnings: []
  }], []);
  assert.equal(plan.additions.length, 0);
  assert.equal(plan.validationErrors.length, 1);
});
