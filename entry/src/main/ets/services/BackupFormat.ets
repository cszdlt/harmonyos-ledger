import type { LedgerBackup } from '../model/BackupModels';
import type { LedgerEntry } from '../model/LedgerModels';
import { validEntryProvenance } from '../model/LedgerModels';
import { validateNotificationRule } from './notificationRules/NotificationRuleEngine';
import { validateOcrRule } from './ocrRules/OcrRuleEngine';

export const BACKUP_FORMAT: string = 'com.gyg.harmonyledger.backup';
export const MAX_BACKUP_BYTES: number = 64 * 1024 * 1024;

function validEntry(entry: LedgerEntry): boolean {
  return entry !== null && typeof entry === 'object' && !Array.isArray(entry) &&
    typeof entry.id === 'string' && entry.id.trim().length > 0 &&
    Number.isSafeInteger(entry.happenedAt) && !Number.isNaN(new Date(entry.happenedAt).getTime()) &&
    typeof entry.hasTime === 'boolean' && Number.isSafeInteger(entry.amountFen) && entry.amountFen > 0 &&
    (entry.direction === 'income' || entry.direction === 'expense') &&
    (entry.accountingType === undefined || ['normal', 'credit-card', 'credit-repayment'].includes(entry.accountingType)) &&
    (entry.direction !== 'income' || entry.accountingType === undefined || entry.accountingType === 'normal') &&
    typeof entry.source === 'string' && typeof entry.merchant === 'string' &&
    typeof entry.category === 'string' && typeof entry.note === 'string' &&
    (entry.provenance === undefined || validEntryProvenance(entry.provenance));
}

export function validateBackup(backup: LedgerBackup): void {
  if (backup === null || typeof backup !== 'object' || Array.isArray(backup) ||
    backup.format !== BACKUP_FORMAT || backup.version !== 1) {
    throw new Error('不是受支持的本应用完整备份（版本 1）');
  }
  if (!Number.isSafeInteger(backup.createdAt) || Number.isNaN(new Date(backup.createdAt).getTime()) ||
    !Number.isInteger(backup.cycleStartDay) || backup.cycleStartDay < 1 || backup.cycleStartDay > 31 ||
    !Array.isArray(backup.entries) || backup.entries.length > 100000 ||
    !Array.isArray(backup.notificationRules) || backup.notificationRules.length > 1000 ||
    !Array.isArray(backup.ocrRules) || backup.ocrRules.length > 1000) {
    throw new Error('备份的日期、记账周期或数据列表无效');
  }
  const ids: Set<string> = new Set<string>();
  for (const entry of backup.entries) {
    if (!validEntry(entry) || ids.has(entry.id)) {
      throw new Error('备份包含无效账目或重复的账目标识，未执行恢复');
    }
    ids.add(entry.id);
  }
  ids.clear();
  for (const rule of backup.notificationRules) {
    const issue = validateNotificationRule(rule);
    if (issue !== undefined || ids.has(rule.id)) {
      throw new Error('备份通知规则无效或标识重复' + (issue === undefined ? '' : '：' + issue.message));
    }
    ids.add(rule.id);
  }
  ids.clear();
  for (const rule of backup.ocrRules) {
    const issue = validateOcrRule(rule);
    if (issue !== undefined || ids.has(rule.id)) {
      throw new Error('备份 OCR 规则无效或标识重复' + (issue === undefined ? '' : '：' + issue.message));
    }
    ids.add(rule.id);
  }
}

export function parseBackup(content: string): LedgerBackup {
  let backup: LedgerBackup;
  try { backup = JSON.parse(content.replace(/^\uFEFF/, '')) as LedgerBackup; }
  catch (_error) { throw new Error('备份 JSON 格式无效或文件不完整'); }
  validateBackup(backup);
  return backup;
}
