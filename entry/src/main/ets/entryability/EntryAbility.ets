import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { indexStorage } from '../state/IndexStorage';
import { NotificationReminderService } from '../services/NotificationReminderService';

export default class EntryAbility extends UIAbility {
  private foregroundRefreshRevision: number = 0;

  onWindowStageCreate(windowStage: window.WindowStage): void {
    indexStorage.setOrCreate('shareImportMode', false);
    indexStorage.setOrCreate('sharedImageUris', []);
    indexStorage.setOrCreate('shareImportError', '');
    indexStorage.setOrCreate('ledgerRefreshRevision', this.foregroundRefreshRevision);
    windowStage.loadContent('pages/Index', indexStorage).then(() => {
      hilog.info(0x0000, 'HarmonyLedger', '主页加载完成');
    }).catch((error: Error) => {
      hilog.error(0x0000, 'HarmonyLedger', '主页加载失败: ' + error.message);
    });
  }

  onForeground(): void {
    this.foregroundRefreshRevision++;
    indexStorage.setOrCreate('ledgerRefreshRevision', this.foregroundRefreshRevision);
    void new NotificationReminderService().refresh(this.context).catch((error: Error) => {
      hilog.error(0x0000, 'HarmonyLedger', '恢复通知提醒失败：' + error.message);
    });
  }
}
