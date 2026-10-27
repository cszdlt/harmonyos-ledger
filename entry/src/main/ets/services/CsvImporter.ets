import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  AccountingType,
  EntryDirection,
  EntrySource,
  LedgerEntry,
  accountingTypeOf,
  formatDateOnly,
  formatDateTime,
  formatMoney,
  makeId,
  parseAmountFen,
  parseDateTime
} from '../model/LedgerModels';
import { CSV_HEADER, LEGACY_CSV_HEADER, csvSourceLabel, decodeCsvCell, parseCsvSourceLabel } from './CsvFormat';

export interface CsvImportProblem {
  recordNumber: number;
  message: string;
}

export interface CsvImportPreview {
  rowCount: number;
  entries: LedgerEntry[];
  duplicateCount: number;
  invalidRows: CsvImportProblem[];
}

interface CsvParsedEntry {
  kind: 'entry';
  value: LedgerEntry;
}

interface CsvParsedProblem {
  kind: 'problem';
  value: CsvImportProblem;
}

type CsvParseResult = CsvParsedEntry | CsvParsedProblem;

function parseCsvRows(content: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;
  let closedQuote = false;

  for (let index = 0; index < content.length; index++) {
    const character = content[index];
    if (inQuotes) {
      if (character === '"') {
        if (content[index + 1] === '"') {
          field += '"';
          index++;
        } else {
          inQuotes = false;
          closedQuote = true;
        }
      } else {
        field += character;
      }
      continue;
    }

    if (character === ',') {
      row.push(field);
      field = '';
      closedQuote = false;
      continue;
    }
    if (character === '\r' || character === '\n') {
      row.push(field);
      if (row.length > 1 || row[0].length > 0) {
        rows.push(row);
      }
      row = [];
      field = '';
      closedQuote = false;
      if (character === '\r' && content[index + 1] === '\n') {
        index++;
      }
      continue;
    }
    if (character === '"') {
      if (field.length > 0 || closedQuote) {
        throw new Error('CSV 引号格式错误');
      }
      inQuotes = true;
      continue;
    }
    if (closedQuote) {
      throw new Error('CSV 引号后出现了多余内容');
    }
    field += character;
  }

  if (inQuotes) {
    throw new Error('CSV 中有未闭合的引号');
  }
  row.push(field);
  if (row.length > 1 || row[0].length > 0) {
    rows.push(row);
  }
  return rows;
}

function entryFingerprint(entry: LedgerEntry): string {
  const dateText = entry.hasTime ? formatDateTime(entry.happenedAt) : formatDateOnly(entry.happenedAt);
  return JSON.stringify([
    dateText,
    entry.direction === 'income' ? '收入' : '支出',
    formatMoney(entry.amountFen),
    entry.merchant,
    entry.category,
    csvSourceLabel(entry.source),
    entry.note,
    accountingTypeOf(entry)
  ]);
}

function parseEntry(row: string[], recordNumber: number, columnCount: number): CsvParseResult {
  const values: string[] = row.map((value: string) => decodeCsvCell(value));
  if (values.length !== columnCount) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '字段数量不正确' } };
  }

  const dateText = values[0];
  const timeMatch = dateText.match(/^\d{4}-\d{2}-\d{2} (\d{2}):(\d{2})$/);
  const hasTime = timeMatch !== null;
  if (!hasTime && !/^\d{4}-\d{2}-\d{2}$/.test(dateText)) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '日期格式无效' } };
  }
  if (timeMatch !== null && (Number(timeMatch[1]) > 23 || Number(timeMatch[2]) > 59)) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '时间无效' } };
  }
  const happenedAt = parseDateTime(dateText);
  if (happenedAt === undefined) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '日期无效' } };
  }

  const directionText = values[1];
  let direction: EntryDirection;
  if (directionText === '收入') {
    direction = 'income';
  } else if (directionText === '支出') {
    direction = 'expense';
  } else {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '收支方向无效' } };
  }

  if (!/^¥\d+\.\d{2}$/.test(values[2])) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '金额格式无效' } };
  }
  const amountFen = parseAmountFen(values[2]);
  if (amountFen === undefined || !Number.isSafeInteger(amountFen)) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '金额无效' } };
  }

  const source: EntrySource | undefined = parseCsvSourceLabel(values[5]);
  if (source === undefined) {
    return { kind: 'problem', value: { recordNumber: recordNumber, message: '来源无效' } };
  }
  let accountingType: AccountingType = 'normal';
  if (columnCount === CSV_HEADER.length) {
    if (values[7] === '信用卡消费') {
      accountingType = 'credit-card';
    } else if (values[7] === '信用卡还款') {
      accountingType = 'credit-repayment';
    } else if (values[7] !== '普通') {
      return { kind: 'problem', value: { recordNumber: recordNumber, message: '记账类型无效' } };
    }
    if (direction === 'income' && accountingType !== 'normal') {
      return { kind: 'problem', value: { recordNumber: recordNumber, message: '信用卡消费和还款必须为支出方向' } };
    }
  }

  return {
    kind: 'entry',
    value: {
      id: makeId('csv') + '-' + recordNumber,
      happenedAt: happenedAt,
      hasTime: hasTime,
      amountFen: amountFen,
      direction: direction,
      accountingType: accountingType,
      provenance: { method: 'csv', basis: '从本应用 CSV 导入；原始识别方式和规则未记录' },
      source: source,
      merchant: values[3],
      category: values[4],
      note: values[6]
    }
  };
}

export class CsvImporter {
  static async selectAndPreview(
    context: common.UIAbilityContext,
    existingEntries: LedgerEntry[]
  ): Promise<CsvImportPreview | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['.csv'];
    options.maxSelectNumber = 1;
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.select(options);
    if (uris.length === 0) {
      return undefined;
    }

    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    let content = '';
    try {
      const fileStat = await fileIo.stat(file.fd);
      const chunks: Uint8Array[] = [];
      let bytesRead = 0;
      while (bytesRead < fileStat.size) {
        const chunkSize = Math.min(64 * 1024, fileStat.size - bytesRead);
        const chunkBuffer = new ArrayBuffer(chunkSize);
        const chunkLength = fileIo.readSync(file.fd, chunkBuffer, { length: chunkSize });
        if (chunkLength <= 0) {
          break;
        }
        chunks.push(new Uint8Array(chunkBuffer, 0, chunkLength));
        bytesRead += chunkLength;
      }
      if (bytesRead !== fileStat.size) {
        throw new Error('CSV 文件未能完整读取');
      }
      const bytes = new Uint8Array(bytesRead);
      let byteOffset = 0;
      chunks.forEach((chunk: Uint8Array) => {
        bytes.set(chunk, byteOffset);
        byteOffset += chunk.length;
      });
      content = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes).replace(/^\uFEFF/, '');
    } finally {
      fileIo.closeSync(file);
    }

    return CsvImporter.preview(content, existingEntries);
  }

  static preview(content: string, existingEntries: LedgerEntry[]): CsvImportPreview {
    const rows = parseCsvRows(content.replace(/^\uFEFF/, ''));
    if (rows.length === 0) {
      throw new Error('CSV 表头不匹配，请选择本应用导出的账目文件');
    }
    const header = rows[0].length === LEGACY_CSV_HEADER.length ? LEGACY_CSV_HEADER : CSV_HEADER;
    if (rows[0].length !== header.length ||
      header.some((name: string, index: number) => rows[0][index] !== name)) {
      throw new Error('CSV 表头不匹配，请选择本应用导出的账目文件');
    }

    const existingFingerprints = new Set<string>();
    existingEntries.forEach((entry: LedgerEntry) => existingFingerprints.add(entryFingerprint(entry)));
    const preview: CsvImportPreview = {
      rowCount: rows.length - 1,
      entries: [],
      duplicateCount: 0,
      invalidRows: []
    };

    for (let index = 1; index < rows.length; index++) {
      const result = parseEntry(rows[index], index, header.length);
      if (result.kind === 'problem') {
        preview.invalidRows.push(result.value);
        continue;
      }
      if (existingFingerprints.has(entryFingerprint(result.value))) {
        preview.duplicateCount++;
        continue;
      }
      preview.entries.push(result.value);
    }
    return preview;
  }
}
