import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LedgerRepository } from '../data/LedgerRepository';
import type { BackupRestoreResult, LedgerBackup } from '../model/BackupModels';
import { BACKUP_FORMAT, validateBackup } from './BackupFormat';
import { loadNotificationRules, saveNotificationRules } from './NotificationRuleStore';
import { loadOcrRules, saveOcrRules } from './OcrRuleStore';

export class LedgerBackupService {
  static async create(context: common.Context, repository: LedgerRepository): Promise<LedgerBackup> {
    const settings = await preferences.getPreferences(context, 'ledger_settings');
    const savedDay = settings.getSync('cycleStartDay', 15);
    if (typeof savedDay !== 'number') { throw new Error('本机记账周期数据无效'); }
    const backup: LedgerBackup = {
      format: BACKUP_FORMAT, version: 1, createdAt: Date.now(), entries: await repository.listEntries(),
      notificationRules: await loadNotificationRules(context), ocrRules: await loadOcrRules(context),
      cycleStartDay: savedDay
    };
    validateBackup(backup);
    return backup;
  }

  static async restore(context: common.Context, repository: LedgerRepository,
    backup: LedgerBackup): Promise<BackupRestoreResult> {
    validateBackup(backup);
    const previousNotificationRules = await loadNotificationRules(context);
    const previousOcrRules = await loadOcrRules(context);
    const settings = await preferences.getPreferences(context, 'ledger_settings');
    const previousDay = settings.getSync('cycleStartDay', 15);
    let configurationStarted = false;
    try {
      return await repository.importBackupEntries(backup.entries, async () => {
        configurationStarted = true;
        await saveNotificationRules(context, backup.notificationRules);
        await saveOcrRules(context, backup.ocrRules);
        await settings.put('cycleStartDay', backup.cycleStartDay);
        await settings.flush();
      });
    } catch (error) {
      if (configurationStarted) {
        let rollbackFailed = false;
        try { await saveNotificationRules(context, previousNotificationRules); } catch (_error) { rollbackFailed = true; }
        try { await saveOcrRules(context, previousOcrRules); } catch (_error) { rollbackFailed = true; }
        try {
          await settings.put('cycleStartDay', previousDay);
          await settings.flush();
        } catch (_error) { rollbackFailed = true; }
        if (rollbackFailed) {
          throw new Error('账目导入已回滚，但部分设置未能恢复。请保留备份并重新执行恢复。');
        }
      }
      throw new Error('恢复未完成，账目未新增：' + (error as Error).message);
    }
  }
}
