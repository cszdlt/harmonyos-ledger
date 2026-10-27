import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import type { LedgerBackup } from '../model/BackupModels';
import { formatDateOnly } from '../model/LedgerModels';
import { MAX_BACKUP_BYTES, parseBackup, validateBackup } from './BackupFormat';

export class BackupFile {
  static async save(context: common.UIAbilityContext, backup: LedgerBackup): Promise<boolean> {
    validateBackup(backup);
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(backup));
    if (bytes.byteLength > MAX_BACKUP_BYTES) { throw new Error('完整备份超过 64 MB，请分批使用 CSV 导出账目'); }
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = ['通知记账完整备份-' + formatDateOnly(backup.createdAt)];
    options.fileSuffixChoices = ['json'];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) { return false; }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      let written = 0;
      while (written < bytes.byteLength) {
        const chunk = bytes.slice(written, Math.min(written + 65536, bytes.byteLength));
        const count = fileIo.writeSync(file.fd, chunk.buffer);
        if (count <= 0) { throw new Error('备份文件未能完整写入'); }
        written += count;
      }
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    return true;
  }

  static async select(context: common.UIAbilityContext): Promise<LedgerBackup | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['.json'];
    options.maxSelectNumber = 1;
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) { return undefined; }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const info = await fileIo.stat(file.fd);
      if (info.size <= 0 || info.size > MAX_BACKUP_BYTES) { throw new Error('备份文件为空或超过 64 MB'); }
      const bytes = new Uint8Array(info.size);
      let read = 0;
      while (read < info.size) {
        const buffer = new ArrayBuffer(Math.min(65536, info.size - read));
        const count = fileIo.readSync(file.fd, buffer, { length: buffer.byteLength });
        if (count <= 0) { throw new Error('备份文件未能完整读取'); }
        bytes.set(new Uint8Array(buffer, 0, count), read);
        read += count;
      }
      return parseBackup(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes));
    } finally { fileIo.closeSync(file); }
  }
}
