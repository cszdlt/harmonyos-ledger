import { hilog } from '@kit.PerformanceAnalysisKit';
import { NotificationSubscriberExtensionAbility, notificationExtensionSubscription } from '@kit.NotificationKit';
import { LedgerRepository } from '../data/LedgerRepository';
import { NotificationArchiveRepository } from '../data/NotificationArchiveRepository';
import { parseBankNotificationEntry } from '../services/BankNotificationParser';
import { loadNotificationRules } from '../services/NotificationRuleStore';
import { recordNotificationProbe } from '../services/NotificationProbeStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'NotificationProbe';

export default class NotificationProbeExtension extends NotificationSubscriberExtensionAbility {
  private ledgerRepository: LedgerRepository = new LedgerRepository();
  private automaticLedgerQueue: Promise<void> = Promise.resolve();
  private notificationArchiveRepository: NotificationArchiveRepository = new NotificationArchiveRepository();
  private notificationArchiveQueue: Promise<void> = Promise.resolve();

  onReceiveMessage(info: notificationExtensionSubscription.NotificationInfo): void {
    const receivedAt = Date.now();
    void recordNotificationProbe(this.context, info).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, '记录通知接收状态失败：' + error.message);
    });
    this.notificationArchiveQueue = this.notificationArchiveQueue.then(() =>
      this.recordNotificationArchive(info, receivedAt)).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, '通知归档失败：' + error.message);
      });
    this.automaticLedgerQueue = this.automaticLedgerQueue.then(() =>
      this.recordAutomaticLedgerEntry(info, receivedAt)).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, '自动入账失败：' + error.message);
      });
  }

  private async recordNotificationArchive(
    info: notificationExtensionSubscription.NotificationInfo,
    receivedAt: number
  ): Promise<void> {
    await this.notificationArchiveRepository.open(this.context);
    await this.notificationArchiveRepository.append(info, receivedAt);
    try {
      this.notificationArchiveRepository.emitArchiveChanged();
    } catch (error) {
      const businessError = error as Error;
      hilog.error(DOMAIN, TAG, '通知归档已保存，但通知历史刷新信号发送失败：' + businessError.message);
    }
  }

  private async recordAutomaticLedgerEntry(
    info: notificationExtensionSubscription.NotificationInfo,
    receivedAt: number
  ): Promise<void> {
    const rules = await loadNotificationRules(this.context);
    const entry = parseBankNotificationEntry(info, receivedAt, rules);
    if (entry === undefined) {
      return;
    }
    await this.ledgerRepository.open(this.context);
    await this.ledgerRepository.addNotificationEntry(entry);
  }
}
