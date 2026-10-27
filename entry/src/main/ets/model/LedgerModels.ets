export type EntryDirection = 'income' | 'expense';
export type AccountingType = 'normal' | 'credit-card' | 'credit-repayment';

export interface EntryProvenance {
  method: 'manual' | 'ocr' | 'notification' | 'csv';
  ruleId?: string;
  ruleName?: string;
  basis?: string;
}

export function validEntryProvenance(value: EntryProvenance): boolean {
  return value !== null && typeof value === 'object' &&
    ['manual', 'ocr', 'notification', 'csv'].includes(value.method) &&
    (value.ruleId === undefined || typeof value.ruleId === 'string') &&
    (value.ruleName === undefined || typeof value.ruleName === 'string') &&
    (value.basis === undefined || typeof value.basis === 'string');
}

export function decodeEntryProvenance(text: string): EntryProvenance | undefined {
  if (text.length === 0) { return undefined; }
  try {
    const value = JSON.parse(text) as EntryProvenance;
    return validEntryProvenance(value) ? value : undefined;
  } catch (_error) {
    return undefined;
  }
}

export function entryProvenanceText(entry: LedgerEntry | undefined): string {
  const value = entry?.provenance;
  if (value === undefined) { return '入账方式：未记录（旧账目未保存识别信息）'; }
  const method = value.method === 'manual' ? '手动记账' : value.method === 'ocr' ? '截图 OCR' :
    value.method === 'notification' ? '通知自动记账' : 'CSV 导入';
  return '入账方式：' + method + (value.ruleName === undefined ? '' : '\n命中规则：' + value.ruleName) +
    (value.basis === undefined ? '' : '\n识别依据：' + value.basis);
}

export type ImportSource = string;
export type EntrySource = string;

export { parseAmountFen } from '../services/notificationRules/AmountParser';

export interface LedgerEntry {
  id: string;
  happenedAt: number;
  hasTime: boolean;
  amountFen: number;
  direction: EntryDirection;
  accountingType?: AccountingType;
  provenance?: EntryProvenance;
  source: EntrySource;
  merchant: string;
  category: string;
  note: string;
}

export interface DraftEntry {
  id: string;
  source: EntrySource;
  merchant: string;
  dateText: string;
  hasTime: boolean;
  amountText: string;
  direction: EntryDirection | undefined;
  accountingType?: AccountingType;
  provenance?: EntryProvenance;
  category: string;
  checked: boolean;
  isRefund: boolean;
  warnings: string[];
}

export function accountingTypeOf(entry: LedgerEntry): AccountingType {
  if (entry.direction === 'expense' &&
    (entry.accountingType === 'credit-card' || entry.accountingType === 'credit-repayment')) {
    return entry.accountingType;
  }
  return 'normal';
}

export function accountingTypeLabel(type: AccountingType): string {
  return type === 'credit-card' ? '信用卡消费' : type === 'credit-repayment' ? '信用卡还款' : '普通';
}

export function formatDateTime(timestamp: number): string {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');
  return year + '-' + month + '-' + day + ' ' + hour + ':' + minute;
}

export function formatDateOnly(timestamp: number): string {
  return formatDateTime(timestamp).slice(0, 10);
}

export function hasClockTime(value: string): boolean {
  const match = value.trim().match(/(?:^|\D)(\d{1,2}):(\d{2})(?::\d{2})?(?:\D|$)/);
  if (match === null) {
    return false;
  }
  return Number(match[1]) <= 23 && Number(match[2]) <= 59;
}

export function parseDateTime(value: string): number | undefined {
  const match = value.trim().match(/^(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})(?:日)?(?:\s+(\d{1,2}):(\d{1,2}))?$/);
  if (match === null) {
    return undefined;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = match[4] === undefined ? 0 : Number(match[4]);
  const minute = match[5] === undefined ? 0 : Number(match[5]);
  const date = new Date(year, month - 1, day, hour, minute, 0, 0);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return undefined;
  }
  return date.getTime();
}


export function formatMoney(amountFen: number): string {
  const absoluteAmountFen = Math.abs(amountFen);
  const sign = amountFen < 0 ? '-' : '';
  const yuan = Math.floor(absoluteAmountFen / 100);
  const fen = String(absoluteAmountFen % 100).padStart(2, '0');
  return sign + '¥' + yuan + '.' + fen;
}

export function makeId(prefix: string): string {
  return prefix + '-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 1000000).toString(36);
}
