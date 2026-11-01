import type { DraftEntry, EntryDirection, EntrySource, LedgerEntry } from '../model/LedgerModels';
import { formatDateOnly, formatDateTime, makeId, parseAmountFen, parseDateTime } from '../model/LedgerModels';
import type { OcrLine } from '../model/OcrModels';
import type { OcrColumnRange, OcrRule } from './ocrRules/OcrRuleModels';
import {
  mapOcrCategory, matchOcrPattern, matchesOcrKeyword, matchesOcrPatterns,
  parseOcrDateByFormat, parseOcrTimeByPattern
} from './ocrRules/OcrRuleEngine';

interface VisualRow {
  text: string;
  centerY: number;
  height: number;
  lines: OcrLine[];
}

interface RecordGroup {
  text: string;
  rows: VisualRow[];
}

interface ParsedDate {
  timestamp: number;
  hasTime: boolean;
}

interface DateContext {
  year: number;
  month: number;
}

interface AmountValue {
  fen: number;
  raw: string;
  direction?: EntryDirection;
}

function median(values: number[]): number {
  if (values.length === 0) {
    return 20;
  }
  const sorted = values.slice().sort((left: number, right: number) => left - right);
  return sorted[Math.floor(sorted.length / 2)];
}

function buildRows(lines: OcrLine[]): VisualRow[] {
  const sorted = lines.filter((line: OcrLine) => line.text.trim().length > 0)
    .slice().sort((left: OcrLine, right: OcrLine) => left.centerY - right.centerY);
  const tolerance = Math.max(10, median(sorted.map((line: OcrLine) => line.height)) * 0.72);
  const rows: VisualRow[] = [];
  sorted.forEach((line: OcrLine) => {
    const current = rows.length > 0 ? rows[rows.length - 1] : undefined;
    if (current !== undefined && Math.abs(current.centerY - line.centerY) <= tolerance) {
      current.lines.push(line);
      current.centerY = current.lines.reduce((sum: number, item: OcrLine) => sum + item.centerY, 0) /
        current.lines.length;
      current.height = Math.max(current.height, line.height);
    } else {
      rows.push({ text: line.text.trim(), centerY: line.centerY, height: line.height, lines: [line] });
    }
  });
  rows.forEach((row: VisualRow) => {
    row.lines.sort((left: OcrLine, right: OcrLine) => left.left - right.left);
    row.text = row.lines.map((line: OcrLine) => line.text.trim()).join(' ');
  });
  return rows;
}

function rangeFor(rule: OcrRule, field: string): OcrColumnRange | undefined {
  if (rule.columns === undefined) {
    return undefined;
  }
  if (field === 'amount') { return rule.columns.amount; }
  if (field === 'date') { return rule.columns.date; }
  if (field === 'time') { return rule.columns.time; }
  if (field === 'direction') { return rule.columns.direction; }
  if (field === 'merchant') { return rule.columns.merchant; }
  return rule.columns.category;
}

function fieldText(rows: VisualRow[], field: string, rule: OcrRule, imageWidth?: number): string {
  const range = rangeFor(rule, field);
  if (range === undefined) {
    return rows.map((row: VisualRow) => row.text).join('\n');
  }
  if (imageWidth === undefined || imageWidth <= 0) {
    return '';
  }
  const selected: string[] = [];
  rows.forEach((row: VisualRow) => {
    row.lines.forEach((line: OcrLine) => {
      const normalizedX = ((line.left + line.right) / 2) / imageWidth;
      if (normalizedX >= range.left && normalizedX <= range.right) {
        selected.push(line.text.trim());
      }
    });
  });
  return selected.join('\n');
}

function makeGroups(rows: VisualRow[], rule: OcrRule): RecordGroup[] {
  if (rule.record?.mode === 'anchor') {
    const groups: RecordGroup[] = [];
    let current: VisualRow[] = [];
    const anchor = new RegExp(rule.record.anchorPattern as string, 'i');
    rows.forEach((row: VisualRow) => {
      if (anchor.test(row.text)) {
        if (current.length > 0) {
          groups.push({ text: current.map((item: VisualRow) => item.text).join(' '), rows: current });
        }
        current = [row];
      } else if (current.length > 0) {
        current.push(row);
      }
    });
    if (current.length > 0) {
      groups.push({ text: current.map((item: VisualRow) => item.text).join(' '), rows: current });
    }
    return groups;
  }
  return rows.map((row: VisualRow): RecordGroup => {
    const group: RecordGroup = { text: row.text, rows: [row] };
    return group;
  });
}

function parseAmount(rawValue: string | undefined): AmountValue | undefined {
  if (rawValue === undefined) {
    return undefined;
  }
  const raw = rawValue.trim();
  const numeric = raw.replace(/[+\-¥￥\s元()]/g, '');
  const fen = parseAmountFen(numeric);
  if (fen === undefined || fen <= 0) {
    return undefined;
  }
  let direction: EntryDirection | undefined = undefined;
  if (/[\-（(]/.test(raw)) {
    direction = 'expense';
  } else if (raw.indexOf('+') >= 0) {
    direction = 'income';
  }
  return { fen: fen, raw: raw, direction: direction };
}

function amountMatch(text: string, rule: OcrRule): string | undefined {
  let searchable = text;
  const dateValue = matchOcrPattern(searchable, rule.datePattern);
  if (dateValue !== undefined) {
    searchable = searchable.replace(dateValue, ' ');
  }
  searchable = searchable
    .replace(/20\d{2}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}日?/g, ' ')
    .replace(/\d{1,2}\s*月\s*\d{1,2}\s*日/g, ' ')
    .replace(/\d{1,2}:\d{2}(?::\d{2})?/g, ' ')
    .replace(/\d{1,2}\s*[-/]\s*\d{1,2}/g, ' ');
  return matchOcrPattern(searchable, rule.amountPattern);
}

function makeDate(year: number, month: number, day: number, hour: number, minute: number): number | undefined {
  const result = new Date(year, month - 1, day, hour, minute, 0, 0);
  return result.getFullYear() === year && result.getMonth() === month - 1 && result.getDate() === day &&
    hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ? result.getTime() : undefined;
}

function parseMonthContext(text: string, captureDate: Date | undefined): DateContext | undefined {
  const normalized = text.replace(/\s/g, '');
  const full = normalized.match(/^(20\d{2})年(\d{1,2})月$/);
  if (full !== null) {
    const year = Number(full[1]);
    const month = Number(full[2]);
    return month >= 1 && month <= 12 ? { year: year, month: month } : undefined;
  }
  const short = normalized.match(/^(\d{1,2})月$/);
  if (short !== null && captureDate !== undefined) {
    const month = Number(short[1]);
    return month >= 1 && month <= 12 ? { year: captureDate.getFullYear(), month: month } : undefined;
  }
  return undefined;
}

function buildDateContexts(rows: VisualRow[], captureDate: Date | undefined): DateContext[] {
  const contexts: DateContext[] = [];
  let current: DateContext | undefined = undefined;
  rows.forEach((row: VisualRow, index: number) => {
    current = parseMonthContext(row.text, captureDate) ?? current;
    if (current !== undefined) {
      contexts[index] = current;
    }
  });
  return contexts;
}

function inferYear(month: number, day: number, captureDate: Date | undefined,
  dateContext?: DateContext): number | undefined {
  if (dateContext !== undefined) {
    return dateContext.year;
  }
  if (captureDate === undefined) {
    return undefined;
  }
  const year = captureDate.getFullYear();
  const candidate = makeDate(year, month, day, 0, 0);
  const captureDay = new Date(year, captureDate.getMonth(), captureDate.getDate()).getTime();
  return candidate !== undefined && candidate > captureDay ? year - 1 : year;
}

function parseAutoDate(value: string, captureDate: Date | undefined, timeText: string,
  rule: OcrRule, dateContext?: DateContext): ParsedDate | undefined {
  const normalized = value.trim().replace(/：/g, ':');
  const time = parseOcrTimeByPattern(timeText, rule.timePattern) ??
    parseOcrTimeByPattern(normalized, { pattern: '(\\d{1,2}:\\d{2}(?::\\d{2})?)', groupIndex: 1 });
  let year: number | undefined;
  let month: number | undefined;
  let day: number | undefined;
  const full = normalized.match(/(20\d{2})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?/);
  if (full !== null) {
    year = Number(full[1]); month = Number(full[2]); day = Number(full[3]);
  } else {
    const chinese = normalized.match(/(\d{1,2})\s*月\s*(\d{1,2})\s*日/);
    const slash = normalized.match(/(\d{1,2})\s*[-/]\s*(\d{1,2})/);
    const partial = chinese ?? slash;
    if (partial !== null) {
      month = Number(partial[1]); day = Number(partial[2]);
      year = inferYear(month, day, captureDate, dateContext);
    } else {
      const dayOnly = normalized.match(/(\d{1,2})\s*日/);
      if (dayOnly !== null && dateContext !== undefined) {
        month = dateContext.month;
        day = Number(dayOnly[1]);
        year = dateContext.year;
      } else if ((normalized.indexOf('今天') >= 0 || normalized.indexOf('昨天') >= 0) && captureDate !== undefined) {
        const date = new Date(captureDate.getFullYear(), captureDate.getMonth(),
          captureDate.getDate() + (normalized.indexOf('昨天') >= 0 ? -1 : 0),
          time?.hour ?? 0, time?.minute ?? 0, 0, 0);
        return { timestamp: date.getTime(), hasTime: time !== undefined };
      }
    }
  }
  if (year === undefined || month === undefined || day === undefined) {
    return undefined;
  }
  const timestamp = makeDate(year, month, day, time?.hour ?? 0, time?.minute ?? 0);
  return timestamp === undefined ? undefined : { timestamp: timestamp, hasTime: time !== undefined };
}

function parseConfiguredDate(value: string, timeText: string, captureDate: Date | undefined,
  rule: OcrRule, dateContext?: DateContext): ParsedDate | undefined {
  if (rule.dateFormat === 'auto') {
    return parseAutoDate(value, captureDate, timeText, rule, dateContext);
  }
  const parts = parseOcrDateByFormat(value, rule.dateFormat);
  if (parts === undefined || parts.day === undefined) {
    return undefined;
  }
  const month = parts.month ?? dateContext?.month ?? (captureDate === undefined ? undefined : captureDate.getMonth() + 1);
  if (month === undefined) {
    return undefined;
  }
  const year = parts.year ?? inferYear(month, parts.day, captureDate, dateContext);
  if (year === undefined) {
    return undefined;
  }
  const time = parseOcrTimeByPattern(timeText, rule.timePattern);
  const hour = parts.hour ?? time?.hour ?? 0;
  const minute = parts.minute ?? time?.minute ?? 0;
  const timestamp = makeDate(year, month, parts.day, hour, minute);
  return timestamp === undefined ? undefined : {
    timestamp: timestamp,
    hasTime: (parts.hour !== undefined && parts.minute !== undefined) || time !== undefined
  };
}

function shouldSkipSummary(group: RecordGroup, rows: VisualRow[], rowIndex: number, rawAmount: string,
  rule: OcrRule): boolean {
  if (matchesOcrPatterns(group.text, rule.summaryPatterns)) {
    return true;
  }
  if (/[+-]/.test(rawAmount) || /[()]/.test(rawAmount) ||
    group.text.replace(rawAmount, '').replace(/[¥￥\s]/g, '').length > 0) {
    return false;
  }
  const preceding = rows.slice(Math.max(0, rowIndex - 2), rowIndex).map((row: VisualRow) => row.text).join(' ');
  return matchesOcrPatterns(preceding, rule.summaryPatterns);
}

function isDuplicate(source: EntrySource, date: number, amountFen: number, merchant: string,
  existing: LedgerEntry[], drafts: DraftEntry[]): boolean {
  const normalizedMerchant = merchant.replace(/\s/g, '').toLowerCase();
  const sameDay = (timestamp: number): boolean => {
    const left = new Date(timestamp);
    const right = new Date(date);
    return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() &&
      left.getDate() === right.getDate();
  };
  if (existing.some((entry: LedgerEntry) => entry.source === source && entry.amountFen === amountFen &&
    sameDay(entry.happenedAt) && entry.merchant.replace(/\s/g, '').toLowerCase() === normalizedMerchant)) {
    return true;
  }
  return drafts.some((draft: DraftEntry) => draft.source === source && parseAmountFen(draft.amountText) === amountFen &&
    parseDateTime(draft.dateText) !== undefined && sameDay(parseDateTime(draft.dateText) as number) &&
    draft.merchant.replace(/\s/g, '').toLowerCase() === normalizedMerchant);
}

function formatDate(date: ParsedDate): string {
  return date.hasTime ? formatDateTime(date.timestamp) : formatDateOnly(date.timestamp);
}

function isTimedDateRow(row: VisualRow, rule: OcrRule, imageWidth?: number): boolean {
  const dateValue = matchOcrPattern(fieldText([row], 'date', rule, imageWidth), rule.datePattern);
  if (dateValue === undefined) {
    return false;
  }
  if (parseOcrTimeByPattern(fieldText([row], 'time', rule, imageWidth) + ' ' + dateValue,
    rule.timePattern) !== undefined || /\d{1,2}[:：]\d{2}/.test(dateValue)) {
    return true;
  }
  const parts = rule.dateFormat === 'auto' ? undefined : parseOcrDateByFormat(dateValue, rule.dateFormat);
  return parts?.hour !== undefined && parts.minute !== undefined;
}

function transactionRows(rows: VisualRow[], amountRows: VisualRow[], anchor: VisualRow, rule: OcrRule,
  typicalHeight: number, imageWidth?: number): VisualRow[] {
  const anchorIndex = rows.indexOf(anchor);
  // 附近字段只归属于唯一最近的金额行，同距时不猜测其交易归属。
  const nearby = rows.filter((row: VisualRow) => {
    const distance = Math.abs(row.centerY - anchor.centerY);
    return row !== anchor && distance <= typicalHeight * 2.4 &&
      !amountRows.some((other: VisualRow) => other !== anchor &&
        Math.abs(other.centerY - row.centerY) <= distance);
  });
  // 独立的日期标题仍可供附近的多笔交易共用，当前记录字段始终优先。
  for (let index = anchorIndex - 1; index >= 0; index--) {
    const row = rows[index];
    if (anchor.centerY - row.centerY > typicalHeight * 2.4) {
      break;
    }
    const dateValue = matchOcrPattern(fieldText([row], 'date', rule, imageWidth), rule.datePattern);
    if (dateValue !== undefined && dateValue.trim() === row.text.trim() &&
      !isTimedDateRow(row, rule, imageWidth)) {
      if (!nearby.includes(row)) {
        nearby.push(row);
      }
      break;
    }
  }
  return [anchor, ...nearby];
}

export class GenericOcrParser {
  static parse(lines: OcrLine[], source: EntrySource, rule: OcrRule, existing: LedgerEntry[],
    priorDrafts: DraftEntry[], captureTime?: number, imageWidth?: number): DraftEntry[] {
    const visualRows = buildRows(lines);
    const groups = makeGroups(visualRows, rule);
    const captureDate = captureTime === undefined ? undefined : new Date(captureTime);
    const dateContexts = buildDateContexts(visualRows, captureDate);
    const result: DraftEntry[] = [];
    const typicalHeight = median(visualRows.map((row: VisualRow) => row.height));
    const amountRows = rule.record?.mode === 'anchor' ? [] : visualRows.filter((row: VisualRow, index: number) => {
      const raw = amountMatch(fieldText([row], 'amount', rule, imageWidth), rule);
      return raw !== undefined && parseAmount(raw) !== undefined &&
        !shouldSkipSummary({ text: row.text, rows: [row] }, visualRows, index, raw, rule);
    });

    groups.forEach((group: RecordGroup) => {
      const anchorRow = group.rows[0];
      const amountSource = fieldText(group.rows, 'amount', rule, imageWidth);
      const rawAmount = amountMatch(amountSource, rule);
      const amount = parseAmount(rawAmount);
      if (amount === undefined || rawAmount === undefined || shouldSkipSummary(group, visualRows,
        visualRows.indexOf(anchorRow), rawAmount, rule)) {
        return;
      }
      const contextualRows = rule.record?.mode === 'anchor' ? group.rows :
        transactionRows(visualRows, amountRows, anchorRow, rule, typicalHeight, imageWidth);
      const context = contextualRows.map((row: VisualRow) => row.text).join(' ');
      if (matchesOcrPatterns(context, rule.failurePatterns)) {
        return;
      }

      const dateSource = fieldText(contextualRows, 'date', rule, imageWidth);
      const dateValue = matchOcrPattern(dateSource, rule.datePattern);
      if (dateValue === undefined) {
        return;
      }
      const timeSource = fieldText(contextualRows, 'time', rule, imageWidth) + ' ' + dateSource;
      const date = parseConfiguredDate(dateValue, timeSource, captureDate, rule,
        dateContexts[visualRows.indexOf(anchorRow)]);
      if (date === undefined) {
        return;
      }

      const directionSource = fieldText(contextualRows, 'direction', rule, imageWidth);
      const directionValue = matchOcrPattern(directionSource, rule.directionPattern);
      let direction = amount.direction;
      if (direction === undefined && matchesOcrKeyword(directionValue ?? directionSource, rule.incomeKeywords)) {
        direction = 'income';
      } else if (direction === undefined && matchesOcrKeyword(directionValue ?? directionSource, rule.expenseKeywords)) {
        direction = 'expense';
      }

      const merchantSource = fieldText(contextualRows, 'merchant', rule, imageWidth);
      let merchant = matchOcrPattern(merchantSource, rule.merchantPattern)?.trim() ?? '';
      if (merchant.length === 0 && rule.merchantPattern === undefined) {
        merchant = group.text.replace(rawAmount, ' ')
          .replace(dateValue, ' ')
          .replace(matchOcrPattern(group.text, rule.directionPattern) ?? '', ' ')
          .replace(/[¥￥|]/g, ' ').trim();
        if (merchant.length === 0) {
          const nearest = contextualRows.filter((row: VisualRow) => row !== anchorRow)
            .sort((left: VisualRow, right: VisualRow) =>
              Math.abs(left.centerY - anchorRow.centerY) - Math.abs(right.centerY - anchorRow.centerY));
          for (const row of nearest) {
            if (matchOcrPattern(row.text, rule.datePattern) === undefined &&
              matchOcrPattern(row.text, rule.amountPattern) === undefined &&
              !matchesOcrPatterns(row.text, rule.summaryPatterns) &&
              !matchesOcrPatterns(row.text, rule.failurePatterns) &&
              !matchesOcrKeyword(row.text, rule.incomeKeywords) &&
              !matchesOcrKeyword(row.text, rule.expenseKeywords)) {
              merchant = row.text.trim();
              break;
            }
          }
        }
      }

      const refund = matchesOcrPatterns(context, rule.refundPatterns);
      const warnings: string[] = [];
      if (refund) {
        direction = undefined;
        warnings.push('识别到退款，请确认收入或支出方向');
      } else if (direction === undefined) {
        warnings.push('金额方向不明确，请选择收入或支出');
      }
      if (merchant.length === 0) {
        warnings.push('未识别到商户或摘要');
      }
      if (isDuplicate(source, date.timestamp, amount.fen, merchant, existing, priorDrafts.concat(result))) {
        warnings.push('与已有账目相似，可能是重复记录');
      }

      const categorySource = fieldText(contextualRows, 'category', rule, imageWidth);
      const categoryValue = matchOcrPattern(categorySource, rule.categoryPattern);
      let mappedCategory: string | undefined = undefined;
      for (const row of contextualRows) {
        mappedCategory = mapOcrCategory(row.text, rule);
        if (mappedCategory !== undefined) {
          break;
        }
      }
      const category = refund ? '退款' : categoryValue === undefined ?
        mappedCategory ?? rule.defaultCategory :
        mapOcrCategory(categoryValue, rule) ?? categoryValue;
      result.push({
        id: makeId('draft'),
        source: source,
        merchant: merchant,
        dateText: formatDate(date),
        hasTime: date.hasTime,
        amountText: (amount.fen / 100).toFixed(2),
        direction: direction,
        category: category,
        checked: true,
        isRefund: refund,
        warnings: warnings
      });
    });
    return result;
  }
}
