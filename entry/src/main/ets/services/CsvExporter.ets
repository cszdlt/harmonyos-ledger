import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { LedgerEntry, accountingTypeLabel, accountingTypeOf, formatDateOnly, formatDateTime, formatMoney } from '../model/LedgerModels';
import { CSV_HEADER, csvSourceLabel, encodeCsvCell } from './CsvFormat';

export class CsvExporter {
  static async export(context: common.UIAbilityContext, entries: LedgerEntry[]): Promise<boolean> {
    const rows: string[] = [CSV_HEADER.join(',')];
    entries.forEach((entry: LedgerEntry) => {
      rows.push([
        encodeCsvCell(entry.hasTime ? formatDateTime(entry.happenedAt) : formatDateOnly(entry.happenedAt)),
        encodeCsvCell(entry.direction === 'income' ? '收入' : '支出'),
        encodeCsvCell(formatMoney(entry.amountFen)),
        encodeCsvCell(entry.merchant),
        encodeCsvCell(entry.category),
        encodeCsvCell(csvSourceLabel(entry.source)),
        encodeCsvCell(entry.note),
        encodeCsvCell(accountingTypeLabel(accountingTypeOf(entry)))
      ].join(','));
    });
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = ['通知记账'];
    options.fileSuffixChoices = ['csv'];
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return false;
    }
    const file = await fileIo.open(
      uris[0],
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      fileIo.writeSync(file.fd, '\uFEFF' + rows.join('\r\n'));
    } finally {
      fileIo.closeSync(file);
    }
    return true;
  }
}
