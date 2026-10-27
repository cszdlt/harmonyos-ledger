import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LedgerEntry } from '../../model/LedgerModels';
import { CsvExporter } from '../../services/CsvExporter';
import { CsvImporter } from '../../services/CsvImporter';
import { BackupFile } from '../../services/BackupFile';
import { formatDateTime } from '../../model/LedgerModels';
import { planBackupRestore } from '../../model/BackupModels';
import type { LedgerBackup, BackupRestoreResult } from '../../model/BackupModels';
import { SettingsView } from '../../components/settings/SettingsView';

interface CsvImportDialogResponse {
  index: number;
}

@Component
export struct LedgerSettingsPage {
  @Prop cycleStartDay: number = 15;
  @Prop creditHistoryUndoCount: number = 0;
  @Link busy: boolean;
  @State private operationMessage: string = '';
  onCreateBackup: () => Promise<LedgerBackup> = () => Promise.reject(new Error('账本尚未连接'));
  onRestoreBackup: (backup: LedgerBackup) => Promise<BackupRestoreResult> =
    (_backup: LedgerBackup) => Promise.reject(new Error('账本尚未连接'));
  onUndoCreditHistory: () => Promise<number> = () => Promise.reject(new Error('账本尚未连接'));

  onBack: () => void = () => {};
  onCycleStartDayChange: (day: number) => void = (_day: number) => {};
  onOpenOcrRules: () => void = () => {};
  onListEntries: () => Promise<LedgerEntry[]> = () => Promise.resolve([]);
  onSaveCsvEntries: (entries: LedgerEntry[], duplicateCount: number, invalidCount: number) => Promise<void> =
    (_entries: LedgerEntry[], _duplicateCount: number, _invalidCount: number) => Promise.resolve();
  onToast: (message: string) => void = (_message: string) => {};

  build() {
    SettingsView({
      cycleStartDay: this.cycleStartDay,
      busy: this.busy,
      operationMessage: this.operationMessage,
      onExportBackup: () => { void this.exportBackup(); },
      onRestoreBackup: () => { void this.restoreBackup(); },
      creditHistoryUndoCount: this.creditHistoryUndoCount,
      onUndoCreditHistory: () => { void this.undoCreditHistory(); },
      onBack: () => this.onBack(),
      onCycleStartDayChange: (day: number) => this.onCycleStartDayChange(day),
      onOpenOcrRules: () => this.onOpenOcrRules(),
      onExportCsv: () => {
        void this.exportCsv();
      },
      onImportCsv: () => {
        void this.importCsv();
      }
    });
  }

  private async undoCreditHistory(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const response = await this.getUIContext().getPromptAction().showDialog({
        title: '撤销最近一次批量标记',
        message: '恢复为普通支出，跳过后来已编辑或删除的记录。此操作仅撤销最近一次批量标记。',
        buttons: [{ text: '取消', color: '#52606D' }, { text: '撤销标记', color: '#2457C5' }]
      });
      if (response.index !== 1) { return; }
      const before = this.creditHistoryUndoCount;
      const count = await this.onUndoCreditHistory();
      this.onToast('已撤销 ' + count + ' 笔，跳过 ' + (before - count) + ' 笔');
    } catch (error) {
      this.onToast('撤销失败：' + (error as BusinessError).message);
    } finally { this.busy = false; }
  }

  private async exportBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.operationMessage = '正在准备完整备份…';
    try {
      const backup = await this.onCreateBackup();
      const saved = await BackupFile.save(this.getUIContext().getHostContext() as common.UIAbilityContext, backup);
      this.operationMessage = saved ? '完整备份已导出：' + backup.entries.length + ' 笔账目，' +
        backup.notificationRules.length + ' 条通知规则，' + backup.ocrRules.length + ' 条 OCR 规则。' : '已取消完整备份导出';
    } catch (error) {
      this.operationMessage = '备份失败：' + (error as BusinessError).message;
    } finally { this.busy = false; }
  }

  private async restoreBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.operationMessage = '正在读取备份…';
    try {
      const backup = await BackupFile.select(this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (backup === undefined) { this.operationMessage = '已取消恢复'; return; }
      const current = await this.onCreateBackup();
      const plan = planBackupRestore(backup.entries, current.entries);
      const response = await this.getUIContext().getPromptAction().showDialog({
        title: '完整备份恢复预览',
        message: '备份时间：' + formatDateTime(backup.createdAt) +
          '\n新增账目：' + plan.addedCount + ' 笔；相同跳过：' + plan.duplicateCount + ' 笔' +
          '\n同 ID 内容冲突：' + plan.conflictCount + ' 笔（保留本机）' +
          '\n通知规则：' + current.notificationRules.length + ' → ' + backup.notificationRules.length + ' 条' +
          '\nOCR 规则：' + current.ocrRules.length + ' → ' + backup.ocrRules.length + ' 条' +
          '\n周期起始日：' + current.cycleStartDay + ' → ' + backup.cycleStartDay + ' 号' +
          '\n\n确认后替换全部通知/OCR 规则及记账周期。已有账目不删除、不覆盖；通知归档不变。' +
          '\n如需保留当前规则，请先导出一份完整备份。',
        buttons: [{ text: '取消', color: '#52606D' }, { text: '确认恢复', color: '#2457C5' }]
      });
      if (response.index !== 1) { this.operationMessage = '已取消恢复'; return; }
      this.operationMessage = '正在恢复账目、规则和周期…';
      const summary = await this.onRestoreBackup(backup);
      this.operationMessage = '恢复完成：新增 ' + summary.addedCount + ' 笔，跳过相同 ' + summary.duplicateCount +
        ' 笔、冲突 ' + summary.conflictCount + ' 笔。规则和记账周期已恢复。';
    } catch (error) {
      this.operationMessage = '恢复失败：' + (error as BusinessError).message;
    } finally { this.busy = false; }
  }

  private async exportCsv(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const entries = await this.onListEntries();
      const exported = await CsvExporter.export(context, entries);
      this.onToast(exported ? 'CSV 已导出' : '已取消导出');
    } catch (error) {
      const businessError = error as BusinessError;
      this.onToast('导出失败：' + businessError.message);
    }
  }

  private async importCsv(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const existingEntries = await this.onListEntries();
      const preview = await CsvImporter.selectAndPreview(context, existingEntries);
      if (preview === undefined) {
        this.onToast('已取消 CSV 导入');
        return;
      }
      if (preview.rowCount === 0) {
        this.onToast('CSV 中没有账目记录');
        return;
      }

      let message = '账目记录：' + preview.rowCount + ' 条' +
        '\n可导入：' + preview.entries.length + ' 条' +
        '\n与现有账本完全相同，跳过：' + preview.duplicateCount + ' 条' +
        '\n格式无效，不导入：' + preview.invalidRows.length + ' 条';
      preview.invalidRows.slice(0, 5).forEach((problem) => {
        message += '\n第 ' + problem.recordNumber + ' 条数据：' + problem.message;
      });
      if (preview.invalidRows.length > 5) {
        message += '\n其余 ' + (preview.invalidRows.length - 5) + ' 条无效记录未展开';
      }

      if (preview.entries.length === 0) {
        await this.getUIContext().getPromptAction().showDialog({
          title: 'CSV 导入预览',
          message: message,
          buttons: [{ text: '关闭', color: '#2457C5' }]
        });
        return;
      }
      this.getUIContext().getPromptAction().showDialog({
        title: 'CSV 导入预览',
        message: message,
        buttons: [
          { text: '取消', color: '#52606D' },
          { text: '导入 ' + preview.entries.length + ' 条', color: '#2457C5' }
        ]
      }, (error: BusinessError, response: CsvImportDialogResponse) => {
        if (error) {
          this.onToast('打开 CSV 导入预览失败：' + error.message);
          return;
        }
        if (response.index !== 1) {
          this.onToast('已取消 CSV 导入');
          return;
        }
        void this.onSaveCsvEntries(preview.entries, preview.duplicateCount, preview.invalidRows.length);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      this.onToast('CSV 导入失败：' + businessError.message);
    }
  }
}
