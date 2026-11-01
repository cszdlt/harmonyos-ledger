import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NotificationReminderRepository } from '../data/NotificationReminderRepository';
import type {
  NotificationReminderConfig, NotificationReminderState, ReminderNotification
} from '../model/NotificationReminderModels';
import { reconcileReminder, recordReminderNotification, validateReminderConfig } from './NotificationReminderEngine';
import { CalendarReminderGateway } from './CalendarReminderGateway';

export class NotificationReminderService {
  private repository: NotificationReminderRepository = new NotificationReminderRepository();

  async refresh(context: common.Context): Promise<NotificationReminderState> {
    return this.repository.update(context, async (state: NotificationReminderState) => {
      await this.synchronize(context, state, Date.now());
    });
  }

  async save(context: common.Context, config: NotificationReminderConfig): Promise<NotificationReminderState> {
    const normalized: NotificationReminderConfig = {
      enabled: config.enabled, bundleName: config.bundleName.trim(), keyword: config.keyword.trim(),
      startMinute: config.startMinute, deadlineMinute: config.deadlineMinute
    };
    const validation = validateReminderConfig(normalized);
    if (normalized.enabled && validation.length > 0) {
      throw new Error(validation);
    }
    return this.repository.update(context, async (state: NotificationReminderState) => {
      if (!normalized.enabled && (!Number.isInteger(normalized.startMinute) || normalized.startMinute < 0 ||
        !Number.isInteger(normalized.deadlineMinute) || normalized.deadlineMinute > 1439 ||
        normalized.startMinute >= normalized.deadlineMinute)) {
        normalized.startMinute = state.config.startMinute;
        normalized.deadlineMinute = state.config.deadlineMinute;
      }
      if (state.config.bundleName !== normalized.bundleName || state.config.keyword !== normalized.keyword ||
        state.config.startMinute !== normalized.startMinute ||
        (state.matchedAt > 0 && new Date(state.matchedAt).getHours() * 60 +
          new Date(state.matchedAt).getMinutes() >= normalized.deadlineMinute)) {
        state.matchedDate = '';
        state.matchedAt = 0;
        // 匹配条件改变后重建计划，清除旧条件产生的排除日期。
        state.scheduledMinute = -1;
      }
      state.config = normalized;
      await this.synchronize(context, state, Date.now());
    });
  }

  async receive(context: common.Context, input: ReminderNotification): Promise<void> {
    const state = await this.repository.update(context, async (state: NotificationReminderState) => {
      try {
        await this.migrateLegacyState(state);
        await recordReminderNotification(state, new CalendarReminderGateway(context), input);
        if (state.config.enabled && state.reminderId < 0) {
          await this.synchronize(context, state, input.receivedAt);
        }
      } catch (error) {
        state.error = this.describeError(error as BusinessError);
      }
    });
    if (state.error.length > 0) {
      throw new Error(state.error);
    }
  }

  private async synchronize(context: common.Context, state: NotificationReminderState, now: number): Promise<void> {
    try {
      await this.migrateLegacyState(state);
      const gateway = new CalendarReminderGateway(context);
      await reconcileReminder(state, gateway, now);
      if (state.config.enabled) { await gateway.verifyEnabled(); }
    } catch (error) {
      // 默认关闭时不要求用户授权日历，但仍尝试清理中断遗留日程。
      state.error = !state.config.enabled && state.reminderId < 0 && state.config.bundleName.length === 0 &&
        state.config.keyword.length === 0 ? '' : this.describeError(error as BusinessError);
    }
  }

  private async migrateLegacyState(state: NotificationReminderState): Promise<void> {
    if (state.backend === 'calendar') { return; }
    if (state.reminderId >= 0) {
      // 仅用于升级时撤销旧计划，不再发布代理提醒，也不需要发布权限。
      try {
        await reminderAgentManager.cancelReminder(state.reminderId);
      } catch (error) {
        if ((error as BusinessError).code !== 1700003) { throw error as Error; }
      }
    }
    state.backend = 'calendar';
    state.reminderId = -1;
    state.scheduledMinute = -1;
    state.excludedDate = '';
    state.error = '';
  }

  private describeError(error: BusinessError): string {
    return '提醒未就绪' + (error.code !== undefined ? '（' + error.code + '）' : '') + '：' +
      error.message + '。请授权日历读写，并检查系统日历的提醒开关，处理后点击刷新重试。';
  }
}
