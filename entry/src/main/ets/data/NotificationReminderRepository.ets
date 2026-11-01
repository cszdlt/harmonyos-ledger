import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import type { NotificationReminderState } from '../model/NotificationReminderModels';
import { defaultReminderState } from '../services/NotificationReminderEngine';

// 独立于账本和通知归档，不保存通知原文。
export class NotificationReminderRepository {
  private static queue: Promise<void> = Promise.resolve();

  async update(
    context: common.Context, action: (state: NotificationReminderState) => Promise<void>
  ): Promise<NotificationReminderState> {
    const result = NotificationReminderRepository.queue.then(() => this.updateState(context, action));
    NotificationReminderRepository.queue = result.then(() => {}, () => {});
    return result;
  }

  private async updateState(
    context: common.Context, action: (state: NotificationReminderState) => Promise<void>
  ): Promise<NotificationReminderState> {
    const store = await relationalStore.getRdbStore(context, {
      name: 'notification_reminder.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    try {
      const transaction = await this.acquireTransaction(store);
      try {
        await transaction.execute('CREATE TABLE IF NOT EXISTS reminder_state (id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
        const result = await transaction.querySql('SELECT value FROM reminder_state WHERE id = 1');
        let state = defaultReminderState();
        try {
          if (result.goToFirstRow()) {
            state = JSON.parse(result.getString(0)) as NotificationReminderState;
          }
        } finally {
          result.close();
        }
        await action(state);
        await transaction.execute('INSERT OR REPLACE INTO reminder_state (id, value) VALUES (1, ?)',
          [JSON.stringify(state)]);
        await transaction.commit();
        return state;
      } catch (error) {
        await transaction.rollback();
        throw error as Error;
      }
    } finally {
      await store.close();
    }
  }

  private async acquireTransaction(store: relationalStore.RdbStore): Promise<relationalStore.Transaction> {
    // 页面与通知扩展使用不同进程；短暂等待对方提交，不能仅依赖内存队列。
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        return await store.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
      } catch (error) {
        const failure = error as BusinessError;
        if (failure.code !== 14800024 || attempt === 19) {
          throw error as Error;
        }
        await new Promise<void>((resolve) => setTimeout(resolve, 100));
      }
    }
    throw new Error('提醒设置正忙，请重试');
  }
}
