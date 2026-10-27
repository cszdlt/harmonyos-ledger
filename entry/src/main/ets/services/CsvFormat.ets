import type { EntrySource } from '../model/LedgerModels';

export const LEGACY_CSV_HEADER: string[] = ['日期', '方向', '金额', '商户/摘要', '分类', '来源', '备注'];
export const CSV_HEADER: string[] = LEGACY_CSV_HEADER.concat(['记账类型']);
const CSV_APOSTROPHE_ESCAPE = "'\uFEFF'";

export function csvSourceLabel(source: EntrySource): string {
  if (source === 'manual') {
    return '手动';
  }
  if (source === 'wechat') {
    return '微信支付';
  }
  if (source === 'alipay') {
    return '支付宝';
  }
  if (source === 'icbc') {
    return '工商银行';
  }
  if (source === 'citic') {
    return '中信银行';
  }
  return source;
}

export function parseCsvSourceLabel(label: string): EntrySource | undefined {
  if (label === '微信支付') {
    return 'wechat';
  }
  if (label === '支付宝') {
    return 'alipay';
  }
  if (label === '工商银行') {
    return 'icbc';
  }
  if (label === '中信银行') {
    return 'citic';
  }
  if (label === '手动') {
    return 'manual';
  }
  return label.trim().length > 0 ? label : undefined;
}

function needsSpreadsheetProtection(value: string): boolean {
  return /^[\t\r\n\u0000=+\-@]/.test(value) ||
    /^[\s\uFEFF]*[=+\-@\uFF1D\uFF0B\uFF0D\uFF20]/.test(value);
}

function leadingApostropheCount(value: string): number {
  let count = 0;
  while (count < value.length && value[count] === "'") {
    count++;
  }
  return count;
}

export function encodeCsvCell(value: string): string {
  const apostropheCount = leadingApostropheCount(value);
  const hasLiteralApostropheBeforeFormulaText = apostropheCount > 0 &&
    needsSpreadsheetProtection(value.slice(apostropheCount));
  let safeValue = value;
  if (value.startsWith(CSV_APOSTROPHE_ESCAPE) || hasLiteralApostropheBeforeFormulaText) {
    safeValue = CSV_APOSTROPHE_ESCAPE + value;
  } else if (needsSpreadsheetProtection(value)) {
    safeValue = "'" + value;
  }
  return '"' + safeValue.replace(/"/g, '""') + '"';
}

export function decodeCsvCell(value: string): string {
  if (value.startsWith(CSV_APOSTROPHE_ESCAPE)) {
    return value.slice(CSV_APOSTROPHE_ESCAPE.length);
  }
  const apostropheCount = leadingApostropheCount(value);
  const hasProtectionPrefix = apostropheCount === 1 && needsSpreadsheetProtection(value.slice(apostropheCount));
  return hasProtectionPrefix ? value.slice(1) : value;
}
