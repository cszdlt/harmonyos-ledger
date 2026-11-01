import { common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import type { NotificationReminderConfig, OwnedReminder, ReminderGateway } from '../model/NotificationReminderModels';

const ACCOUNT_NAME: string = 'com.gyg.harmonyledger.attendance';
const EVENT_IDENTIFIER: string = 'com.gyg.harmonyledger.attendance.reminder.v1';

export class CalendarReminderGateway implements ReminderGateway {
  private context: common.Context;
  private calendar: calendarManager.Calendar | undefined = undefined;

  constructor(context: common.Context) {
    this.context = context;
  }

  async list(): Promise<OwnedReminder[]> {
    const events = await this.ownedEvents();
    return events.map((event): OwnedReminder => { return { id: event.id as number }; });
  }

  async publish(config: NotificationReminderConfig, now: number): Promise<number> {
    const calendar = await this.getCalendar(true);
    if (calendar === undefined) { throw new Error('无法创建提醒日历'); }
    const start = new Date(now);
    start.setHours(Math.floor(config.deadlineMinute / 60), config.deadlineMinute % 60, 0, 0);
    while (start.getTime() <= now || start.getDay() === 0 || start.getDay() === 6) {
      start.setDate(start.getDate() + 1);
    }
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: '下班打卡提醒',
      description: '尚未收到下班打卡通知，请检查是否忘记打卡。',
      identifier: EVENT_IDENTIFIER,
      startTime: start.getTime(), endTime: start.getTime() + 60000,
      isAllDay: false,
      reminderTime: [0],
      recurrenceRule: {
        recurrenceFrequency: calendarManager.RecurrenceFrequency.WEEKLY,
        interval: 1, daysOfWeek: [1, 2, 3, 4, 5]
      }
    };
    const id = await calendar.addEvent(event);
    if (id <= 0) { throw new Error('日历未返回有效的日程编号'); }
    return id;
  }

  async cancel(id: number): Promise<void> {
    const calendar = await this.getCalendar(false);
    if (calendar !== undefined && (await this.ownedEvents()).some((event) => event.id === id)) {
      await calendar.deleteEvent(id);
    }
  }

  async exclude(id: number, date: Date): Promise<void> {
    const calendar = await this.getCalendar(false);
    const event = (await this.ownedEvents()).find((event) => event.id === id);
    if (calendar === undefined || event === undefined || event.recurrenceRule === undefined) {
      throw new Error('提醒日程已删除或重复规则已变更，请刷新重试');
    }
    const start = new Date(event.startTime);
    const excluded = new Date(date.getTime());
    // 日历要求排除时间与日程的时分秒一致，不能直接使用打卡通知时间。
    excluded.setHours(start.getHours(), start.getMinutes(), start.getSeconds(), 0);
    const dates = event.recurrenceRule.excludedDates ?? [];
    if (dates.includes(excluded.getTime())) { return; }
    dates.push(excluded.getTime());
    event.recurrenceRule.excludedDates = dates;
    await calendar.updateEvent(event);
  }

  async verifyEnabled(): Promise<void> {
    const calendar = await this.getCalendar(false);
    if (calendar !== undefined && calendar.getConfig().enableReminder === false) {
      throw new Error('请在系统日历中开启“下班打卡提醒”日历的提醒');
    }
  }

  private async ownedEvents(): Promise<calendarManager.Event[]> {
    const calendar = await this.getCalendar(false);
    if (calendar === undefined) { return []; }
    const events = await calendar.getEvents(calendarManager.EventFilter.filterByTitle('下班打卡提醒'), [
      'id', 'identifier', 'type', 'title', 'description', 'startTime', 'endTime',
      'isAllDay', 'reminderTime', 'recurrenceRule'
    ]);
    return events.filter((event) => event.identifier === EVENT_IDENTIFIER && event.id !== undefined && event.id > 0);
  }

  private async getCalendar(create: boolean): Promise<calendarManager.Calendar | undefined> {
    if (this.calendar !== undefined) { return this.calendar; }
    const manager = calendarManager.getCalendarManager(this.context);
    const calendars = await manager.getAllCalendars();
    this.calendar = calendars.find((calendar) => {
      const account = calendar.getAccount();
      return account.name === ACCOUNT_NAME && account.type === calendarManager.CalendarType.LOCAL;
    });
    if (this.calendar === undefined && create) {
      this.calendar = await manager.createCalendar({
        name: ACCOUNT_NAME, type: calendarManager.CalendarType.LOCAL, displayName: '下班打卡提醒'
      });
      if (this.calendar.id <= 0) { throw new Error('日历账号创建失败'); }
      await this.calendar.setConfig({ enableReminder: true });
    }
    return this.calendar;
  }
}
