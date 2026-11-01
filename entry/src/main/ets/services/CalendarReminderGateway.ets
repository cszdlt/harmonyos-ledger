import { common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import type { NotificationReminderConfig, OwnedReminder, ReminderGateway } from '../model/NotificationReminderModels';
import { chinaWorkdayDateKey, getChinaWorkdaySchedule } from './ChinaWorkdayCalendar';

const ACCOUNT_NAME: string = 'com.gyg.harmonyledger.attendance';
const EVENT_IDENTIFIER: string = 'com.gyg.harmonyledger.attendance.reminder.v1';
const MAKEUP_IDENTIFIER_PREFIX: string = EVENT_IDENTIFIER + '.makeup.';

export class CalendarReminderGateway implements ReminderGateway {
  private context: common.Context;
  private calendar: calendarManager.Calendar | undefined = undefined;

  constructor(context: common.Context) {
    this.context = context;
  }

  async list(): Promise<OwnedReminder[]> {
    const events = await this.ownedEvents();
    const regular = events.filter((event) => event.identifier === EVENT_IDENTIFIER);
    const reminders: OwnedReminder[] = regular.map((event): OwnedReminder => {
      return { id: event.id as number, primary: true };
    });
    for (const event of events) {
      if (event.identifier === undefined || !event.identifier.startsWith(MAKEUP_IDENTIFIER_PREFIX)) { continue; }
      const groupId = this.makeupGroupId(event.identifier);
      if (groupId > 0 && !regular.some((item) => item.id === groupId) &&
        !reminders.some((item) => item.id === groupId)) {
        reminders.push({ id: groupId, primary: false });
      }
    }
    return reminders;
  }

  async publish(config: NotificationReminderConfig, now: number, matchedDate: string = ''): Promise<number> {
    const calendar = await this.getCalendar(true);
    if (calendar === undefined) { throw new Error('无法创建提醒日历'); }
    const events = await this.ownedEvents();
    let regular = events.find((event) => event.identifier === EVENT_IDENTIFIER);
    const excludedDates = this.holidayExclusions(config.deadlineMinute, now);
    if (regular === undefined) {
      const start = this.nextWeekdayStart(now, config.deadlineMinute);
      regular = {
        type: calendarManager.EventType.NORMAL,
        title: '下班打卡提醒',
        description: '尚未收到下班打卡通知，请检查是否忘记打卡。',
        identifier: EVENT_IDENTIFIER,
        startTime: start.getTime(), endTime: start.getTime() + 60000,
        isAllDay: false,
        reminderTime: [0],
        recurrenceRule: {
          recurrenceFrequency: calendarManager.RecurrenceFrequency.WEEKLY,
          interval: 1, daysOfWeek: [1, 2, 3, 4, 5], excludedDates
        }
      };
      const id = await calendar.addEvent(regular);
      if (id <= 0) { throw new Error('日历未返回有效的日程编号'); }
      regular.id = id;
    } else {
      const recurrence = regular.recurrenceRule;
      const allExcludedDates = this.mergeDates(recurrence?.excludedDates ?? [], excludedDates);
      const recurrenceChanged = recurrence === undefined ||
        recurrence.recurrenceFrequency !== calendarManager.RecurrenceFrequency.WEEKLY ||
        recurrence.interval !== 1 || !this.sameNumbers(recurrence.daysOfWeek ?? [], [1, 2, 3, 4, 5]) ||
        !this.sameNumbers(recurrence.excludedDates ?? [], allExcludedDates);
      if (recurrenceChanged) {
        regular.recurrenceRule = {
          recurrenceFrequency: calendarManager.RecurrenceFrequency.WEEKLY,
          interval: 1, daysOfWeek: [1, 2, 3, 4, 5], excludedDates: allExcludedDates
        };
        await calendar.updateEvent(regular);
      }
    }
    const id = regular.id as number;
    await this.synchronizeMakeupEvents(calendar, events, id, config.deadlineMinute, now, matchedDate);
    return id;
  }

  async cancel(id: number): Promise<void> {
    const calendar = await this.getCalendar(false);
    if (calendar === undefined) { return; }
    const events = await this.ownedEvents();
    const ids = events.filter((event) => event.identifier === EVENT_IDENTIFIER && event.id === id ||
      event.identifier !== undefined && event.identifier.startsWith(MAKEUP_IDENTIFIER_PREFIX) &&
      this.makeupGroupId(event.identifier) === id).map((event) => event.id as number);
    for (const eventId of ids) {
      await calendar.deleteEvent(eventId);
    }
  }

  async exclude(id: number, date: Date): Promise<void> {
    const calendar = await this.getCalendar(false);
    const events = await this.ownedEvents();
    if (date.getDay() === 0 || date.getDay() === 6) {
      const makeup = events.find((event) => event.identifier === this.makeupIdentifier(id, chinaWorkdayDateKey(date)));
      if (calendar !== undefined && makeup?.id !== undefined) {
        await calendar.deleteEvent(makeup.id);
      }
      return;
    }
    const event = events.find((item) => item.id === id && item.identifier === EVENT_IDENTIFIER);
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
    return events.filter((event) => event.identifier !== undefined &&
      (event.identifier === EVENT_IDENTIFIER || event.identifier.startsWith(MAKEUP_IDENTIFIER_PREFIX)) &&
      event.id !== undefined && event.id > 0);
  }

  private nextWeekdayStart(now: number, deadlineMinute: number): Date {
    const start = new Date(now);
    start.setHours(Math.floor(deadlineMinute / 60), deadlineMinute % 60, 0, 0);
    if (start.getTime() <= now) { start.setDate(start.getDate() + 1); }
    while (!this.isRegularWorkday(start)) {
      start.setDate(start.getDate() + 1);
    }
    return start;
  }

  private isRegularWorkday(date: Date): boolean {
    if (date.getDay() === 0 || date.getDay() === 6) { return false; }
    return !getChinaWorkdaySchedule(date.getFullYear()).restDates.includes(chinaWorkdayDateKey(date));
  }

  private holidayExclusions(deadlineMinute: number, now: number): number[] {
    const excluded: number[] = [];
    const year = new Date(now).getFullYear();
    for (let candidate = year; candidate <= year + 3; candidate++) {
      const schedule = getChinaWorkdaySchedule(candidate);
      for (const dateKey of schedule.restDates) {
        const date = this.dateAtMinute(dateKey, deadlineMinute);
        if (date.getTime() > now && date.getDay() >= 1 && date.getDay() <= 5) {
          excluded.push(date.getTime());
        }
      }
    }
    return excluded.sort((left, right) => left - right);
  }

  private async synchronizeMakeupEvents(
    calendar: calendarManager.Calendar, events: calendarManager.Event[], groupId: number,
    deadlineMinute: number, now: number, matchedDate: string
  ): Promise<void> {
    const desiredDates: string[] = [];
    const year = new Date(now).getFullYear();
    for (let candidate = year; candidate <= year + 3; candidate++) {
      const schedule = getChinaWorkdaySchedule(candidate);
      for (const dateKey of schedule.makeupWorkdays) {
        const date = this.dateAtMinute(dateKey, deadlineMinute);
        if (date.getTime() > now && dateKey !== matchedDate && (date.getDay() === 0 || date.getDay() === 6)) {
          desiredDates.push(dateKey);
        }
      }
    }
    const desiredIdentifiers = desiredDates.map((dateKey) => this.makeupIdentifier(groupId, dateKey));
    const children = events.filter((event) => event.identifier !== undefined &&
      event.identifier.startsWith(MAKEUP_IDENTIFIER_PREFIX) && this.makeupGroupId(event.identifier) === groupId);
    for (const dateKey of desiredDates) {
      const identifier = this.makeupIdentifier(groupId, dateKey);
      if (children.some((event) => event.identifier === identifier)) { continue; }
      const start = this.dateAtMinute(dateKey, deadlineMinute);
      const id = await calendar.addEvent({
        type: calendarManager.EventType.NORMAL,
        title: '下班打卡提醒',
        description: '尚未收到下班打卡通知，请检查是否忘记打卡。',
        identifier,
        startTime: start.getTime(), endTime: start.getTime() + 60000,
        isAllDay: false, reminderTime: [0]
      });
      if (id <= 0) { throw new Error('日历未返回有效的调休日程编号'); }
    }
    for (const event of children) {
      if (event.id !== undefined && event.identifier !== undefined && !desiredIdentifiers.includes(event.identifier)) {
        await calendar.deleteEvent(event.id);
      }
    }
  }

  private dateAtMinute(dateKey: string, minute: number): Date {
    const parts = dateKey.split('-');
    const date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    date.setHours(Math.floor(minute / 60), minute % 60, 0, 0);
    return date;
  }

  private mergeDates(existing: number[], additional: number[]): number[] {
    const merged = existing.slice();
    for (const timestamp of additional) {
      if (!merged.includes(timestamp)) { merged.push(timestamp); }
    }
    return merged.sort((left, right) => left - right);
  }

  private sameNumbers(first: number[], second: number[]): boolean {
    if (first.length !== second.length) { return false; }
    return first.every((value, index) => value === second[index]);
  }

  private makeupIdentifier(groupId: number, dateKey: string): string {
    return MAKEUP_IDENTIFIER_PREFIX + groupId + '.' + dateKey;
  }

  private makeupGroupId(identifier: string): number {
    if (!identifier.startsWith(MAKEUP_IDENTIFIER_PREFIX)) { return -1; }
    const group = identifier.substring(MAKEUP_IDENTIFIER_PREFIX.length).split('.')[0];
    const id = Number(group);
    return Number.isInteger(id) && id > 0 ? id : -1;
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
