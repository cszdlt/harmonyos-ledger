import type { LedgerEntry } from '../model/LedgerModels';
import type { NotificationArchiveEntry } from '../model/NotificationArchiveModels';
import type { NotificationRule, NotificationInput } from './notificationRules/NotificationRuleModels';
import { parseNotificationEntry } from './notificationRules/NotificationRuleEngine';

export interface NotificationRebookingCandidate {
  archive: NotificationArchiveEntry;
  entry: LedgerEntry;
  duplicate: boolean;
}

function duplicateKey(entry: LedgerEntry): string {
  return Math.floor(entry.happenedAt / 60000) + ':' + entry.amountFen + ':' + entry.direction;
}

export class NotificationHistoryRebookingMatcher {
  private rule: NotificationRule;
  private seenKeys: Set<string> = new Set<string>();
  private candidates: NotificationRebookingCandidate[] = [];

  constructor(rule: NotificationRule, ledgerEntries: LedgerEntry[]) {
    this.rule = rule;
    ledgerEntries.forEach((entry: LedgerEntry) => {
      if (entry.hasTime) {
        this.seenKeys.add(duplicateKey(entry));
      }
    });
  }

  scan(notifications: NotificationArchiveEntry[]): void {
    notifications.forEach((archive: NotificationArchiveEntry) => {
      const input: NotificationInput = {
        appName: archive.appName,
        bundleName: archive.bundleName,
        title: archive.title,
        body: archive.body,
        deliveryTime: archive.deliveryTime,
        receivedAt: archive.receivedAt
      };
      const parsed = parseNotificationEntry(input, [this.rule]);
      if (parsed === undefined) {
        return;
      }
      const entry: LedgerEntry = {
        id: parsed.id,
        happenedAt: parsed.happenedAt,
        hasTime: parsed.hasTime,
        amountFen: parsed.amountFen,
        direction: parsed.direction,
        accountingType: parsed.accountingType,
        provenance: parsed.provenance,
        source: parsed.source,
        merchant: parsed.merchant,
        category: parsed.category,
        note: parsed.note
      };
      const key = duplicateKey(entry);
      const duplicate = this.seenKeys.has(key);
      this.seenKeys.add(key);
      const candidate: NotificationRebookingCandidate = { archive: archive, entry: entry, duplicate: duplicate };
      this.candidates.push(candidate);
    });
  }

  preview(): NotificationRebookingCandidate[] {
    return this.candidates.slice();
  }
}

export function findHistoricalNotificationCandidates(
  notifications: NotificationArchiveEntry[],
  rule: NotificationRule,
  ledgerEntries: LedgerEntry[]
): NotificationRebookingCandidate[] {
  const matcher = new NotificationHistoryRebookingMatcher(rule, ledgerEntries);
  matcher.scan(notifications);
  return matcher.preview();
}
