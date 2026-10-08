import { formatDateOnly } from '../model/LedgerModels';
import type { LedgerEntry } from '../model/LedgerModels';
import { statisticsRange } from './LedgerStatistics';

export interface LedgerDayGroup {
  dateKey: string;
  entries: LedgerEntry[];
  expenseTotalFen: number;
  incomeTotalFen: number;
}

export interface LedgerHomeData {
  monthEntries: LedgerEntry[];
  dayGroups: LedgerDayGroup[];
  incomeTotalFen: number;
  expenseTotalFen: number;
  monthLabel: string;
}

export function buildLedgerHomeData(
  entries: LedgerEntry[],
  cursor: number,
  cycleStartDay: number
): LedgerHomeData {
  const range = statisticsRange('month', cursor, 0, 0, cycleStartDay);
  const monthEntries = entries.filter((entry: LedgerEntry) =>
    entry.happenedAt >= range.start && entry.happenedAt < range.endExclusive);
  const dayGroups: LedgerDayGroup[] = [];
  let incomeTotalFen = 0;
  let expenseTotalFen = 0;

  monthEntries.forEach((entry: LedgerEntry) => {
    const dateKey = formatDateOnly(entry.happenedAt);
    let group = dayGroups.find((item: LedgerDayGroup) => item.dateKey === dateKey);
    if (group === undefined) {
      group = { dateKey: dateKey, entries: [], expenseTotalFen: 0, incomeTotalFen: 0 };
      dayGroups.push(group);
    }
    group.entries.push(entry);
    if (entry.direction === 'expense') {
      group.expenseTotalFen += entry.amountFen;
      expenseTotalFen += entry.amountFen;
    } else {
      group.incomeTotalFen += entry.amountFen;
      incomeTotalFen += entry.amountFen;
    }
  });

  const start = new Date(range.start);
  const end = new Date(range.endExclusive - 24 * 60 * 60 * 1000);
  const endYear = start.getFullYear() === end.getFullYear() ? '' : end.getFullYear() + '年';
  const monthLabel = start.getFullYear() + '年' + (start.getMonth() + 1) + '月' + start.getDate() +
    '日—' + endYear + (end.getMonth() + 1) + '月' + end.getDate() + '日';

  return {
    monthEntries: monthEntries,
    dayGroups: dayGroups,
    incomeTotalFen: incomeTotalFen,
    expenseTotalFen: expenseTotalFen,
    monthLabel: monthLabel
  };
}

export function moveLedgerMonthCursor(cursor: number, offset: number): number {
  const date = new Date(cursor);
  return new Date(date.getFullYear(), date.getMonth() + offset, 1).getTime();
}
