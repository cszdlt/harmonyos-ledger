import type { LedgerEntry } from '../model/LedgerModels';
import { accountingTypeOf, parseDateTime } from '../model/LedgerModels';
import type { NotificationInput, NotificationRule } from './notificationRules/NotificationRuleModels';
import { parseNotificationEntry } from './notificationRules/NotificationRuleEngine';

export interface CreditHistoryRule {
  name: string;
  source: string;
  notificationRule?: NotificationRule;
}

export interface CreditHistoryFilter {
  source: string;
  startTime?: number;
  endTimeExclusive?: number;
  keyword: string;
}

export interface CreditHistoryCandidate {
  entry: LedgerEntry;
  matched: boolean;
}

export interface CreditHistoryPreview {
  candidates: CreditHistoryCandidate[];
  ambiguousCount: number;
}

export function parseCreditHistoryFilter(source: string, startDate: string, endDate: string,
  keyword: string): CreditHistoryFilter {
  const startText = startDate.trim();
  const endText = endDate.trim();
  const start = startText.length === 0 ? undefined : parseDateTime(startText);
  const end = endText.length === 0 ? undefined : parseDateTime(endText);
  if ((startText.length > 0 && (!/^\d{4}-\d{2}-\d{2}$/.test(startText) || start === undefined)) ||
    (endText.length > 0 && (!/^\d{4}-\d{2}-\d{2}$/.test(endText) || end === undefined))) {
    throw new Error('请填写有效日期，格式为 YYYY-MM-DD，留空表示不限');
  }
  if (start !== undefined && end !== undefined && start > end) {
    throw new Error('开始日期不能晚于结束日期');
  }
  const lastDay = end === undefined ? undefined : new Date(end);
  return {
    source: source,
    startTime: start,
    endTimeExclusive: lastDay === undefined ? undefined :
      new Date(lastDay.getFullYear(), lastDay.getMonth(), lastDay.getDate() + 1).getTime(),
    keyword: keyword.trim().toLowerCase()
  };
}

// 沿用通知入账的同分钟、金额与方向查重口径；有多个可能对象时不自动关联。
function matchKey(happenedAt: number, amountFen: number): string {
  return Math.floor(happenedAt / 60000) + ':' + amountFen;
}

export class CreditHistoryMatcher {
  private entries: LedgerEntry[];
  private ruleSource: string;
  private timedExpenses: Map<string, LedgerEntry[]> = new Map<string, LedgerEntry[]>();
  private matchedIds: Set<string> = new Set<string>();
  private ambiguousKeys: Set<string> = new Set<string>();

  constructor(entries: LedgerEntry[], ruleSource: string) {
    this.entries = entries;
    this.ruleSource = ruleSource;
    entries.forEach((entry: LedgerEntry) => {
      if (entry.direction !== 'expense' || !entry.hasTime) {
        return;
      }
      const key = matchKey(entry.happenedAt, entry.amountFen);
      let bucket = this.timedExpenses.get(key);
      if (bucket === undefined) {
        bucket = [];
        this.timedExpenses.set(key, bucket);
      }
      bucket.push(entry);
    });
  }

  scan(notifications: NotificationInput[], rule: NotificationRule): void {
    if (rule.isCreditCard !== true) {
      return;
    }
    const replayRule = JSON.parse(JSON.stringify(rule)) as NotificationRule;
    replayRule.enabled = true;
    notifications.forEach((input: NotificationInput) => {
      const parsed = parseNotificationEntry(input, [replayRule]);
      if (parsed === undefined || parsed.direction !== 'expense') {
        return;
      }
      const key = matchKey(parsed.happenedAt, parsed.amountFen);
      const matches = this.timedExpenses.get(key);
      if (matches === undefined) {
        return;
      }
      if (matches.length !== 1) {
        this.ambiguousKeys.add(key);
        return;
      }
      if (accountingTypeOf(matches[0]) === 'normal') {
        this.matchedIds.add(matches[0].id);
      }
    });
  }

  preview(filter: CreditHistoryFilter): CreditHistoryPreview {
    const candidates: CreditHistoryCandidate[] = [];
    this.entries.forEach((entry: LedgerEntry) => {
      if (entry.direction !== 'expense' || accountingTypeOf(entry) !== 'normal' ||
        (filter.startTime !== undefined && entry.happenedAt < filter.startTime) ||
        (filter.endTimeExclusive !== undefined && entry.happenedAt >= filter.endTimeExclusive) ||
        (filter.source.length > 0 && entry.source !== filter.source) ||
        (filter.keyword.length > 0 &&
          !(entry.merchant + '\n' + entry.note).toLowerCase().includes(filter.keyword))) {
        return;
      }
      const matched = this.matchedIds.has(entry.id);
      const candidateSource = filter.source.length > 0 ? filter.source : this.ruleSource;
      if (matched || entry.source === candidateSource) {
        candidates.push({ entry: entry, matched: matched });
      }
    });
    return { candidates: candidates, ambiguousCount: this.ambiguousKeys.size };
  }
}
