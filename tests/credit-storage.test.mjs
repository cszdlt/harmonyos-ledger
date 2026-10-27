import test from 'node:test';
import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import { DatabaseSync } from 'node:sqlite';

let activeStore;
let backupText = '';
globalThis.creditTestKit = {
  relationalStore: { SecurityLevel: { S1: 1 }, getRdbStore: async () => activeStore,
    RdbPredicates: class {
      conditions = [];
      equalTo(key, value) { this.conditions.push([key, value]); return this; }
    } },
  fileIo: { OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 }, open: async () => ({}),
    writeSync: (_file, text) => { backupText = text; }, closeSync: () => {} },
  picker: { DocumentSaveOptions: class {}, DocumentViewPicker: class { async save() { return ['memory:csv']; } } }
};
registerHooks({
  load(url, context, nextLoad) {
    const result = nextLoad(url, context);
    if (!url.endsWith('.ets')) return result;
    const source = String(result.source).replace(/import\s*\{([^}]+)\}\s*from\s*(['"][^'"]+['"]);/g,
      (statement, names, from) => {
        const kept = names.split(',').map((name) => name.trim())
          .filter((name) => !['AccountingType', 'EntryDirection', 'EntrySource', 'LedgerEntry'].includes(name));
        return kept.length > 0 ? `import { ${kept.join(', ')} } from ${from};` : '';
      });
    return { ...result, source };
  },
  resolve(specifier, context, nextResolve) {
    if (!specifier.startsWith('@kit.')) return nextResolve(specifier, context);
    const code = 'export const relationalStore = globalThis.creditTestKit.relationalStore;'
      + 'export const fileIo = globalThis.creditTestKit.fileIo; export const picker = globalThis.creditTestKit.picker;'
      + 'export const common = {}; export const util = {};';
    return { url: 'data:text/javascript,' + encodeURIComponent(code), shortCircuit: true };
  }
});

function sqlStore(db) {
  return {
    async executeSql(sql) { db.exec(sql); },
    async querySql(sql, args = []) {
      const rows = db.prepare(sql).all(...args);
      let index = -1;
      return { goToNextRow: () => ++index < rows.length, getColumnIndex: (name) => name,
        getString: (name) => String(rows[index][name]), getLong: (name) => Number(rows[index][name]), close() {} };
    },
    async insert(table, values) {
      const keys = Object.keys(values);
      db.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`)
        .run(...Object.values(values));
    },
    async update(values, predicates) {
      const where = predicates.conditions.map(([key]) => key + '=?').join(' AND ');
      const result = db.prepare(`UPDATE ledger_entries SET ${Object.keys(values).map((key) => key + '=?').join(',')} WHERE ${where}`)
        .run(...Object.values(values), ...predicates.conditions.map(([, value]) => value));
      return Number(result.changes);
    },
    beginTransaction() { db.exec('BEGIN IMMEDIATE'); },
    commit() { db.exec('COMMIT'); },
    rollBack() { db.exec('ROLLBACK'); },
    emit() {}
  };
}

test('旧数据库原地迁移，原记录保留且默认普通，信用卡类型可保存并重新读取', async () => {
  const { LedgerRepository } = await import('../entry/src/main/ets/data/LedgerRepository.ets');
  const db = new DatabaseSync(':memory:');
  try {
    db.exec(`CREATE TABLE ledger_entries (id TEXT PRIMARY KEY, happened_at INTEGER, amount_fen INTEGER,
      direction TEXT, source TEXT, merchant TEXT, category TEXT, note TEXT);
      INSERT INTO ledger_entries VALUES ('old', 1792404000000, 50000, 'expense', 'manual', '还款', '其他', '保留备注');`);
    activeStore = sqlStore(db);
    const repository = new LedgerRepository();
    await repository.open({});
    const [entry] = await repository.listEntries();
    assert.equal(entry.accountingType, 'normal');
    assert.equal(entry.note, '保留备注');
    await repository.updateEntry({ ...entry, accountingType: 'credit-repayment' });
    const reopened = new LedgerRepository();
    await reopened.open({});
    assert.equal((await reopened.listEntries())[0].accountingType, 'credit-repayment');
    assert.equal(db.prepare('SELECT COUNT(*) AS count FROM ledger_entries').get().count, 1);
  } finally { db.close(); }
});

test('CSV 备份恢复信用卡类型且兼容旧七列表头', async () => {
  const { CsvExporter } = await import('../entry/src/main/ets/services/CsvExporter.ets');
  const { CsvImporter } = await import('../entry/src/main/ets/services/CsvImporter.ets');
  const entries = ['normal', 'credit-card', 'credit-repayment'].map((accountingType, index) => ({
    id: String(index), happenedAt: new Date(2026, 9, 20).getTime(), hasTime: false,
    amountFen: 10000 + index, direction: 'expense', source: 'manual', merchant: '测试',
    category: '其他', note: '保留原文', accountingType
  }));
  await CsvExporter.export({}, entries);
  assert.deepEqual(CsvImporter.preview(backupText, []).entries.map((entry) => entry.accountingType),
    ['normal', 'credit-card', 'credit-repayment']);
  assert.equal(CsvImporter.preview(backupText, entries).duplicateCount, 3);
  const legacy = '日期,方向,金额,商户/摘要,分类,来源,备注\n2026-10-20,支出,¥100.00,测试,其他,手动,保留原文';
  const restored = CsvImporter.preview(legacy, []).entries[0];
  assert.equal(restored.accountingType, 'normal');
  assert.equal(restored.note, '保留原文');
});

test('重复信用卡通知只补充普通记录的消费标记，不新增也不覆盖人工还款标记', async () => {
  const { LedgerRepository } = await import('../entry/src/main/ets/data/LedgerRepository.ets');
  const db = new DatabaseSync(':memory:');
  try {
    activeStore = sqlStore(db);
    const repository = new LedgerRepository();
    await repository.open({});
    const original = { id: 'payment', happenedAt: new Date(2026, 9, 20, 12).getTime(), hasTime: true,
      amountFen: 10000, direction: 'expense', source: 'alipay', merchant: '午餐', category: '其他', note: '' };
    await repository.addEntry(original);
    const notice = { ...original, id: 'bank', source: 'icbc', accountingType: 'credit-card', category: '餐饮' };
    await repository.addNotificationEntry(notice);
    const [matched] = await repository.listEntries();
    assert.equal(matched.accountingType, 'credit-card');
    assert.equal(matched.category, '餐饮');
    assert.equal(matched.source, 'alipay');
    await repository.updateEntry({ ...matched, accountingType: 'credit-repayment' });
    await repository.addNotificationEntry(notice);
    const remaining = await repository.listEntries();
    assert.equal(remaining.length, 1);
    assert.equal(remaining[0].accountingType, 'credit-repayment');
  } finally { db.close(); }
});

test('历史批量标记只改类型，跳过预览后已变更的记录并且不重复更新', async () => {
  const { LedgerRepository } = await import('../entry/src/main/ets/data/LedgerRepository.ets');
  const db = new DatabaseSync(':memory:');
  try {
    activeStore = sqlStore(db);
    const repository = new LedgerRepository();
    await repository.open({});
    const snapshots = ['normal', 'repayment', 'edited'].map((id) => ({ id, happenedAt: 1792404000000,
      hasTime: true, amountFen: 1850, direction: 'expense', source: 'icbc', merchant: '午餐',
      category: '餐饮', note: '保留备注', accountingType: 'normal' }));
    for (const item of snapshots) await repository.addEntry(item);
    await repository.updateEntry({ ...snapshots[1], accountingType: 'credit-repayment' });
    await repository.updateEntry({ ...snapshots[2], note: '预览后已修改' });
    assert.equal(await repository.markCreditCardEntries([...snapshots, snapshots[0]]), 1);
    const entries = await repository.listEntries();
    assert.equal(entries.find((item) => item.id === 'normal').accountingType, 'credit-card');
    assert.equal(entries.find((item) => item.id === 'normal').note, '保留备注');
    assert.equal(entries.find((item) => item.id === 'repayment').accountingType, 'credit-repayment');
    assert.equal(entries.find((item) => item.id === 'edited').accountingType, 'normal');
    assert.equal(await repository.markCreditCardEntries(snapshots), 0);
  } finally { db.close(); }
});

test('历史批量标记中途失败时整批回滚', async () => {
  const { LedgerRepository } = await import('../entry/src/main/ets/data/LedgerRepository.ets');
  const db = new DatabaseSync(':memory:');
  try {
    activeStore = sqlStore(db);
    const repository = new LedgerRepository();
    await repository.open({});
    const snapshots = ['one', 'two'].map((id) => ({ id, happenedAt: 1792404000000, hasTime: true,
      amountFen: 1850, direction: 'expense', source: 'icbc', merchant: '午餐', category: '餐饮', note: '' }));
    for (const item of snapshots) await repository.addEntry(item);
    const update = activeStore.update;
    let calls = 0;
    activeStore.update = async (...args) => { if (++calls === 2) throw new Error('模拟写入失败'); return update(...args); };
    await assert.rejects(repository.markCreditCardEntries(snapshots), /模拟写入失败/);
    assert.ok((await repository.listEntries()).every((item) => item.accountingType === 'normal'));
  } finally { db.close(); }
});
