import type { LedgerEntry } from '../model/LedgerModels';
import { accountingTypeOf, isFixedExpense } from '../model/LedgerModels';

export type StatisticsPeriod = 'month' | 'year' | 'custom';
export type StatisticsExpenseScope = 'all' | 'fixed' | 'nonFixed';

export interface StatisticsRange {
  start: number;
  endExclusive: number;
}

export interface StatisticsTrendItem {
  key: string;
  label: string;
  incomeFen: number;
  expenseFen: number;
  fixedExpenseFen: number;
  nonFixedExpenseFen: number;
}

export interface StatisticsRankItem {
  key: string;
  label: string;
  amountFen: number;
  count: number;
}

export interface LedgerStatistics {
  incomeFen: number;
  expenseFen: number;
  fixedExpenseFen: number;
  nonFixedExpenseFen: number;
  netFen: number;
  creditCardFen: number;
  creditRepaymentFen: number;
  entryCount: number;
  trend: StatisticsTrendItem[];
  categories: StatisticsRankItem[];
  merchants: StatisticsRankItem[];
  sources: StatisticsRankItem[];
  fixedCategories: StatisticsRankItem[];
  fixedMerchants: StatisticsRankItem[];
  fixedSources: StatisticsRankItem[];
  nonFixedCategories: StatisticsRankItem[];
  nonFixedMerchants: StatisticsRankItem[];
  nonFixedSources: StatisticsRankItem[];
  incomeCategories: StatisticsRankItem[];
  incomeMerchants: StatisticsRankItem[];
  incomeSources: StatisticsRankItem[];
}

const DAY_MILLISECONDS = 24 * 60 * 60 * 1000;

function startOfDay(timestamp: number): number {
  const date = new Date(timestamp);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function dayCount(range: StatisticsRange): number {
  const start = new Date(range.start);
  const end = new Date(range.endExclusive);
  return (Date.UTC(end.getFullYear(), end.getMonth(), end.getDate()) -
    Date.UTC(start.getFullYear(), start.getMonth(), start.getDate())) / DAY_MILLISECONDS;
}

function dayKey(date: Date): string {
  return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' +
    String(date.getDate()).padStart(2, '0');
}

function monthKey(date: Date): string {
  return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0');
}

function cycleStart(year: number, month: number, day: number): Date {
  const lastDay = new Date(year, month + 1, 0).getDate();
  return new Date(year, month, Math.min(day, lastDay));
}

function trendKey(timestamp: number, monthly: boolean): string {
  const date = new Date(timestamp);
  return monthly ? monthKey(date) : dayKey(date);
}

function buildTrend(range: StatisticsRange, monthly: boolean): StatisticsTrendItem[] {
  const items: StatisticsTrendItem[] = [];
  const first = new Date(range.start);
  const last = new Date(range.endExclusive - DAY_MILLISECONDS);
  const showYear = first.getFullYear() !== last.getFullYear();
  let cursor: Date = monthly ? new Date(first.getFullYear(), first.getMonth(), 1) :
    new Date(startOfDay(range.start));
  while (cursor.getTime() < range.endExclusive) {
    const key = monthly ? monthKey(cursor) : dayKey(cursor);
    const label = monthly ? (showYear ? cursor.getFullYear() + '年' : '') + (cursor.getMonth() + 1) + '月' :
      (cursor.getMonth() + 1) + '/' + cursor.getDate();
    items.push({
      key: key,
      label: label,
      incomeFen: 0,
      expenseFen: 0,
      fixedExpenseFen: 0,
      nonFixedExpenseFen: 0
    });
    cursor = monthly ? new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1) :
      new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1);
  }
  return items;
}

function addRankItem(items: StatisticsRankItem[], key: string, label: string, amountFen: number): void {
  let item = items.find((candidate: StatisticsRankItem) => candidate.key === key);
  if (item === undefined) {
    item = { key: key, label: label, amountFen: 0, count: 0 };
    items.push(item);
  }
  item.amountFen += amountFen;
  item.count++;
}

function sortedRankItems(items: StatisticsRankItem[]): StatisticsRankItem[] {
  return items.sort((left: StatisticsRankItem, right: StatisticsRankItem) =>
    right.amountFen - left.amountFen);
}

export function statisticsRange(
  period: StatisticsPeriod,
  cursor: number,
  customStart: number,
  customEnd: number,
  cycleStartDay: number = 1
): StatisticsRange {
  const selected = new Date(cursor);
  if (period === 'year') {
    return {
      start: new Date(selected.getFullYear(), 0, 1).getTime(),
      endExclusive: new Date(selected.getFullYear() + 1, 0, 1).getTime()
    };
  }
  if (period === 'custom') {
    const firstDay = startOfDay(Math.min(customStart, customEnd));
    const lastDay = startOfDay(Math.max(customStart, customEnd));
    const last = new Date(lastDay);
    return {
      start: firstDay,
      endExclusive: new Date(last.getFullYear(), last.getMonth(), last.getDate() + 1).getTime()
    };
  }
  const selectedDay = startOfDay(cursor);
  let start = cycleStart(selected.getFullYear(), selected.getMonth(), cycleStartDay);
  if (start.getTime() > selectedDay) {
    start = cycleStart(selected.getFullYear(), selected.getMonth() - 1, cycleStartDay);
  }
  const next = cycleStart(start.getFullYear(), start.getMonth() + 1, cycleStartDay);
  return {
    start: start.getTime(),
    endExclusive: next.getTime()
  };
}

export function previousStatisticsRange(
  range: StatisticsRange,
  period: StatisticsPeriod,
  cycleStartDay: number = 1
): StatisticsRange {
  const start = new Date(range.start);
  if (period === 'year') {
    return {
      start: new Date(start.getFullYear() - 1, 0, 1).getTime(),
      endExclusive: range.start
    };
  }
  if (period === 'month') {
    const previousStart = cycleStart(start.getFullYear(), start.getMonth() - 1, cycleStartDay);
    return {
      start: previousStart.getTime(),
      endExclusive: range.start
    };
  }
  const days = dayCount(range);
  return {
    start: new Date(start.getFullYear(), start.getMonth(), start.getDate() - days).getTime(),
    endExclusive: range.start
  };
}

export function buildLedgerStatistics(
  entries: LedgerEntry[],
  range: StatisticsRange,
  period: StatisticsPeriod
): LedgerStatistics {
  const days = dayCount(range);
  const monthlyTrend = period === 'year' || (period === 'custom' && days > 31);
  const trend = buildTrend(range, monthlyTrend);
  const categories: StatisticsRankItem[] = [];
  const merchants: StatisticsRankItem[] = [];
  const sources: StatisticsRankItem[] = [];
  const fixedCategories: StatisticsRankItem[] = [];
  const fixedMerchants: StatisticsRankItem[] = [];
  const fixedSources: StatisticsRankItem[] = [];
  const nonFixedCategories: StatisticsRankItem[] = [];
  const nonFixedMerchants: StatisticsRankItem[] = [];
  const nonFixedSources: StatisticsRankItem[] = [];
  const incomeCategories: StatisticsRankItem[] = [];
  const incomeMerchants: StatisticsRankItem[] = [];
  const incomeSources: StatisticsRankItem[] = [];
  let incomeFen = 0;
  let expenseFen = 0;
  let fixedExpenseFen = 0;
  let creditCardFen = 0;
  let creditRepaymentFen = 0;
  let entryCount = 0;

  entries.forEach((entry: LedgerEntry) => {
    if (entry.happenedAt < range.start || entry.happenedAt >= range.endExclusive) {
      return;
    }
    entryCount++;
    const accountingType = accountingTypeOf(entry);
    if (accountingType === 'credit-repayment') {
      creditRepaymentFen += entry.amountFen;
      return;
    }
    if (accountingType === 'credit-card') {
      creditCardFen += entry.amountFen;
    }
    const key = trendKey(entry.happenedAt, monthlyTrend);
    const bucket = trend.find((item: StatisticsTrendItem) => item.key === key);
    if (bucket !== undefined) {
      if (entry.direction === 'income') {
        bucket.incomeFen += entry.amountFen;
      } else {
        bucket.expenseFen += entry.amountFen;
        if (isFixedExpense(entry)) {
          bucket.fixedExpenseFen += entry.amountFen;
        } else {
          bucket.nonFixedExpenseFen += entry.amountFen;
        }
      }
    }
    if (entry.direction === 'income') {
      incomeFen += entry.amountFen;
      const category = entry.category.trim().length > 0 ? entry.category.trim() : '其他';
      const merchant = entry.merchant.trim().length > 0 ? entry.merchant.trim() : '未填写商户';
      addRankItem(incomeCategories, category, category, entry.amountFen);
      addRankItem(incomeMerchants, merchant, merchant, entry.amountFen);
      addRankItem(incomeSources, entry.source, entry.source, entry.amountFen);
    } else {
      expenseFen += entry.amountFen;
      const fixed = isFixedExpense(entry);
      if (fixed) {
        fixedExpenseFen += entry.amountFen;
      }
      const category = entry.category.trim().length > 0 ? entry.category.trim() : '其他';
      const merchant = entry.merchant.trim().length > 0 ? entry.merchant.trim() : '未填写商户';
      addRankItem(categories, category, category, entry.amountFen);
      addRankItem(merchants, merchant, merchant, entry.amountFen);
      addRankItem(sources, entry.source, entry.source, entry.amountFen);
      if (fixed) {
        addRankItem(fixedCategories, category, category, entry.amountFen);
        addRankItem(fixedMerchants, merchant, merchant, entry.amountFen);
        addRankItem(fixedSources, entry.source, entry.source, entry.amountFen);
      } else {
        addRankItem(nonFixedCategories, category, category, entry.amountFen);
        addRankItem(nonFixedMerchants, merchant, merchant, entry.amountFen);
        addRankItem(nonFixedSources, entry.source, entry.source, entry.amountFen);
      }
    }
  });

  return {
    incomeFen: incomeFen,
    expenseFen: expenseFen,
    fixedExpenseFen: fixedExpenseFen,
    nonFixedExpenseFen: expenseFen - fixedExpenseFen,
    netFen: incomeFen - expenseFen + creditCardFen - creditRepaymentFen,
    creditCardFen: creditCardFen,
    creditRepaymentFen: creditRepaymentFen,
    entryCount: entryCount,
    trend: trend,
    categories: sortedRankItems(categories),
    merchants: sortedRankItems(merchants),
    sources: sortedRankItems(sources),
    fixedCategories: sortedRankItems(fixedCategories),
    fixedMerchants: sortedRankItems(fixedMerchants),
    fixedSources: sortedRankItems(fixedSources),
    nonFixedCategories: sortedRankItems(nonFixedCategories),
    nonFixedMerchants: sortedRankItems(nonFixedMerchants),
    nonFixedSources: sortedRankItems(nonFixedSources),
    incomeCategories: sortedRankItems(incomeCategories),
    incomeMerchants: sortedRankItems(incomeMerchants),
    incomeSources: sortedRankItems(incomeSources)
  };
}
