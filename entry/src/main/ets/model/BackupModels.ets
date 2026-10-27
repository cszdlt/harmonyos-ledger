import type { LedgerEntry } from './LedgerModels';
import { accountingTypeOf } from './LedgerModels';
import type { NotificationRule } from '../services/notificationRules/NotificationRuleModels';
import type { OcrRule } from '../services/ocrRules/OcrRuleModels';

export interface LedgerBackup {
  format: string;
  version: number;
  createdAt: number;
  entries: LedgerEntry[];
  notificationRules: NotificationRule[];
  ocrRules: OcrRule[];
  cycleStartDay: number;
}

export interface BackupRestoreResult {
  addedCount: number;
  duplicateCount: number;
  conflictCount: number;
}

export function backupEntryKey(entry: LedgerEntry): string {
  const provenance = entry.provenance;
  return JSON.stringify([entry.happenedAt, entry.hasTime, entry.amountFen, entry.direction, accountingTypeOf(entry),
    entry.source, entry.merchant, entry.category, entry.note, provenance?.method ?? '', provenance?.ruleId ?? '',
    provenance?.ruleName ?? '', provenance?.basis ?? '']);
}

export function planBackupRestore(entries: LedgerEntry[], existing: LedgerEntry[]): BackupRestoreResult {
  const byId: Map<string, string> = new Map<string, string>();
  existing.forEach((entry: LedgerEntry) => { byId.set(entry.id, backupEntryKey(entry)); });
  let duplicates = 0;
  let conflicts = 0;
  entries.forEach((entry: LedgerEntry) => {
    const key = byId.get(entry.id);
    if (key !== undefined) {
      if (key === backupEntryKey(entry)) { duplicates++; } else { conflicts++; }
    }
  });
  return { addedCount: entries.length - duplicates - conflicts, duplicateCount: duplicates, conflictCount: conflicts };
}
