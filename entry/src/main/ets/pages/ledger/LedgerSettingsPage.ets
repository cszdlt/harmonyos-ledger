import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LedgerEntry } from '../../model/LedgerModels';
import { CsvExporter } from '../../services/CsvExporter';
import { CsvImporter } from '../../services/CsvImporter';
import { SettingsView } from '../../components/settings/SettingsView';

interface CsvImportDialogResponse {
  index: number;
}

@Component
export struct LedgerSettingsPage {
  @Prop cycleStartDay: number = 15;

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
