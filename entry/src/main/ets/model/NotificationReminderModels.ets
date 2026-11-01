export interface NotificationReminderConfig {
  enabled: boolean;
  bundleName: string;
  keyword: string;
  startMinute: number;
  deadlineMinute: number;
}

export interface NotificationReminderState {
  backend?: string;
  config: NotificationReminderConfig;
  reminderId: number;
  scheduledMinute: number;
  matchedDate: string;
  matchedAt: number;
  excludedDate: string;
  error: string;
}

export interface ReminderNotification {
  bundleName: string;
  title: string;
  body: string;
  deliveryTime?: number;
  receivedAt: number;
}

export interface OwnedReminder {
  id: number;
}

export interface ReminderSettingsDraft {
  enabled: boolean;
  bundleName: string;
  keyword: string;
  startTime: string;
  deadlineTime: string;
}

export interface ReminderGateway {
  list(): Promise<OwnedReminder[]>;
  publish(config: NotificationReminderConfig, now: number): Promise<number>;
  cancel(id: number): Promise<void>;
  exclude(id: number, date: Date): Promise<void>;
}
