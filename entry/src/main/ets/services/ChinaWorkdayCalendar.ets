export interface ChinaWorkdaySchedule {
  restDates: string[];
  makeupWorkdays: string[];
}

// 国务院办公厅公布的2026年放假调休安排。尚未公布安排的年份按周一至周五处理。
export const CHINA_WORKDAY_CALENDAR_VERSION: string = 'cn-2026-v1';

const REST_DATES_2026: string[] = [
  '2026-01-01', '2026-01-02', '2026-01-03',
  '2026-02-15', '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
  '2026-02-20', '2026-02-21', '2026-02-22', '2026-02-23',
  '2026-04-04', '2026-04-05', '2026-04-06',
  '2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05',
  '2026-06-19', '2026-06-20', '2026-06-21',
  '2026-09-25', '2026-09-26', '2026-09-27',
  '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
  '2026-10-05', '2026-10-06', '2026-10-07'
];

const MAKEUP_WORKDAYS_2026: string[] = [
  '2026-01-04', '2026-02-14', '2026-02-28', '2026-05-09', '2026-09-20', '2026-10-10'
];

export function getChinaWorkdaySchedule(year: number): ChinaWorkdaySchedule {
  if (year !== 2026) {
    return { restDates: [], makeupWorkdays: [] };
  }
  return { restDates: REST_DATES_2026.slice(), makeupWorkdays: MAKEUP_WORKDAYS_2026.slice() };
}

export function chinaWorkdayDateKey(date: Date): string {
  return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') +
    '-' + date.getDate().toString().padStart(2, '0');
}

export function isChinaWorkday(date: Date): boolean {
  const schedule = getChinaWorkdaySchedule(date.getFullYear());
  const key = chinaWorkdayDateKey(date);
  if (schedule.makeupWorkdays.includes(key)) {
    return true;
  }
  if (schedule.restDates.includes(key)) {
    return false;
  }
  return date.getDay() >= 1 && date.getDay() <= 5;
}
