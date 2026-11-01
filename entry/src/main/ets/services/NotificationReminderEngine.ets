import type {
  NotificationReminderConfig, NotificationReminderState, ReminderGateway, ReminderNotification
} from '../model/NotificationReminderModels';
import { CHINA_WORKDAY_CALENDAR_VERSION, isChinaWorkday } from './ChinaWorkdayCalendar';

export function defaultReminderState(): NotificationReminderState {
  return {
    backend: 'calendar',
    config: { enabled: false, bundleName: '', keyword: '', startMinute: 17 * 60, deadlineMinute: 20 * 60 },
    reminderId: -1, scheduledMinute: -1, matchedDate: '', matchedAt: 0, excludedDate: '',
    calendarVersion: CHINA_WORKDAY_CALENDAR_VERSION, error: ''
  };
}

export function reminderDateKey(timestamp: number): string {
  const date = new Date(timestamp);
  return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') +
    '-' + date.getDate().toString().padStart(2, '0');
}

export function formatReminderMinute(minute: number): string {
  return Math.floor(minute / 60).toString().padStart(2, '0') + ':' + (minute % 60).toString().padStart(2, '0');
}

export function parseReminderMinute(value: string): number {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(value.trim())) {
    return -1;
  }
  const parts = value.trim().split(':');
  return Number(parts[0]) * 60 + Number(parts[1]);
}

export function validateReminderConfig(config: NotificationReminderConfig): string {
  if (config.bundleName.trim().length === 0 || config.keyword.trim().length === 0) {
    return '请选择来源应用，并填写下班打卡成功关键词';
  }
  if (!Number.isInteger(config.startMinute) || !Number.isInteger(config.deadlineMinute) ||
    config.startMinute < 0 || config.deadlineMinute > 1439 || config.startMinute >= config.deadlineMinute) {
    return '请输入有效时间（HH:mm），接收起始时间须早于提醒时间，不支持跨天';
  }
  return '';
}

export function matchesReminderNotification(config: NotificationReminderConfig, input: ReminderNotification): boolean {
  if (!config.enabled || validateReminderConfig(config).length > 0 || input.bundleName !== config.bundleName) {
    return false;
  }
  const timestamp = input.deliveryTime !== undefined && Number.isFinite(input.deliveryTime) && input.deliveryTime > 0 ?
    input.deliveryTime : input.receivedAt;
  const date = new Date(timestamp);
  const minute = date.getHours() * 60 + date.getMinutes();
  const received = new Date(input.receivedAt);
  const receivedMinute = received.getHours() * 60 + received.getMinutes();
  return Number.isFinite(timestamp) && timestamp <= input.receivedAt &&
    reminderDateKey(timestamp) === reminderDateKey(input.receivedAt) &&
    isChinaWorkday(date) &&
    minute >= config.startMinute && minute < config.deadlineMinute && receivedMinute < config.deadlineMinute &&
    (input.title.includes(config.keyword) || input.body.includes(config.keyword));
}

// 调用方在跨进程事务内执行，避免设置修改与通知回调互相覆盖。
export async function reconcileReminder(
  state: NotificationReminderState, gateway: ReminderGateway, now: number
): Promise<void> {
  const reminders = await gateway.list();
  const keep = state.config.enabled && state.scheduledMinute === state.config.deadlineMinute &&
    state.calendarVersion === CHINA_WORKDAY_CALENDAR_VERSION;
  let found = false;
  for (const reminder of reminders) {
    if (keep && reminder.primary !== false && reminder.id === state.reminderId) {
      found = true;
    } else {
      await gateway.cancel(reminder.id);
    }
  }
  if (!found) {
    state.reminderId = -1;
    state.scheduledMinute = -1;
    state.excludedDate = '';
  }
  if (!state.config.enabled) {
    state.error = '';
    return;
  }
  if (!found) {
    state.reminderId = -1;
    state.scheduledMinute = -1;
  }
  const today = reminderDateKey(now);
  state.reminderId = await gateway.publish(state.config, now, state.matchedDate === today ? today : '');
  state.scheduledMinute = state.config.deadlineMinute;
  state.calendarVersion = CHINA_WORKDAY_CALENDAR_VERSION;
  if (state.matchedDate === today && state.excludedDate !== today) {
    await gateway.exclude(state.reminderId, new Date(state.matchedAt));
    state.excludedDate = today;
  }
  state.error = '';
}

export async function recordReminderNotification(
  state: NotificationReminderState, gateway: ReminderGateway, input: ReminderNotification
): Promise<void> {
  if (!matchesReminderNotification(state.config, input)) {
    return;
  }
  state.matchedDate = reminderDateKey(input.receivedAt);
  state.matchedAt = input.deliveryTime !== undefined && input.deliveryTime > 0 ? input.deliveryTime : input.receivedAt;
  await reconcileReminder(state, gateway, input.receivedAt);
}
