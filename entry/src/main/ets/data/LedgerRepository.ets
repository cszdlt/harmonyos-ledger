import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { AccountingType, EntryDirection, EntrySource, LedgerEntry, accountingTypeOf, decodeEntryProvenance, isFixedExpense } from '../model/LedgerModels';
import { BackupRestoreResult, planBackupRestore } from '../model/BackupModels';

const LEDGER_ENTRIES_CHANGED_EVENT: string = 'dataability:///com.gyg.harmonyledger/ledger_entries';

export class LedgerRepository {
  private store: relationalStore.RdbStore | undefined = undefined;

  async open(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'harmony_ledger.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(
      'CREATE TABLE IF NOT EXISTS ledger_entries (' +
      'id TEXT PRIMARY KEY NOT NULL,' +
      'happened_at INTEGER NOT NULL,' +
      'amount_fen INTEGER NOT NULL,' +
      'direction TEXT NOT NULL,' +
      'source TEXT NOT NULL,' +
      'merchant TEXT NOT NULL,' +
      'category TEXT NOT NULL,' +
      'note TEXT NOT NULL DEFAULT \"\",' +
      'has_time INTEGER NOT NULL DEFAULT 1,' +
      "accounting_type TEXT NOT NULL DEFAULT 'normal'," +
      'is_fixed_expense INTEGER NOT NULL DEFAULT 0)'
    );
    const columns = await this.store.querySql('PRAGMA table_info(ledger_entries)');
    let hasTimeColumn = false;
    let hasAccountingTypeColumn = false;
    let hasProvenanceColumn = false;
    let hasFixedExpenseColumn = false;
    try {
      while (columns.goToNextRow()) {
        if (columns.getString(columns.getColumnIndex('name')) === 'provenance') {
          hasProvenanceColumn = true;
        }
        if (columns.getString(columns.getColumnIndex('name')) === 'has_time') {
          hasTimeColumn = true;
        }
        if (columns.getString(columns.getColumnIndex('name')) === 'accounting_type') {
          hasAccountingTypeColumn = true;
        }
        if (columns.getString(columns.getColumnIndex('name')) === 'is_fixed_expense') {
          hasFixedExpenseColumn = true;
        }
      }
    } finally {
      columns.close();
    }
    if (!hasTimeColumn) {
      await this.store.executeSql('ALTER TABLE ledger_entries ADD COLUMN has_time INTEGER NOT NULL DEFAULT 1');
    }
    if (!hasAccountingTypeColumn) {
      await this.store.executeSql("ALTER TABLE ledger_entries ADD COLUMN accounting_type TEXT NOT NULL DEFAULT 'normal'");
    }
    if (!hasProvenanceColumn) {
      await this.store.executeSql("ALTER TABLE ledger_entries ADD COLUMN provenance TEXT NOT NULL DEFAULT ''");
    }
    if (!hasFixedExpenseColumn) {
      await this.store.executeSql('ALTER TABLE ledger_entries ADD COLUMN is_fixed_expense INTEGER NOT NULL DEFAULT 0');
    }
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS credit_history_undo (' +
      'entry_id TEXT PRIMARY KEY NOT NULL, snapshot TEXT NOT NULL)');
  }

  async listEntries(): Promise<LedgerEntry[]> {
    const store = this.requireStore();
    const result = await store.querySql(
      'SELECT id, happened_at, amount_fen, direction, source, merchant, category, note, has_time, accounting_type, provenance, is_fixed_expense ' +
      'FROM ledger_entries ORDER BY happened_at DESC'
    );
    const entries: LedgerEntry[] = [];
    try {
      while (result.goToNextRow()) {
        entries.push({
          id: result.getString(result.getColumnIndex('id')),
          happenedAt: result.getLong(result.getColumnIndex('happened_at')),
          hasTime: result.getLong(result.getColumnIndex('has_time')) === 1,
          amountFen: result.getLong(result.getColumnIndex('amount_fen')),
          direction: result.getString(result.getColumnIndex('direction')) as EntryDirection,
          accountingType: result.getString(result.getColumnIndex('accounting_type')) as AccountingType,
          isFixedExpense: result.getLong(result.getColumnIndex('is_fixed_expense')) === 1,
          provenance: decodeEntryProvenance(result.getString(result.getColumnIndex('provenance'))),
          source: result.getString(result.getColumnIndex('source')) as EntrySource,
          merchant: result.getString(result.getColumnIndex('merchant')),
          category: result.getString(result.getColumnIndex('category')),
          note: result.getString(result.getColumnIndex('note'))
        });
      }
    } finally {
      result.close();
    }
    return entries;
  }

  async addEntry(entry: LedgerEntry): Promise<void> {
    const store = this.requireStore();
    await store.insert('ledger_entries', this.toValues(entry));
    this.emitLedgerEntriesChanged();
  }

  async addNotificationEntry(entry: LedgerEntry): Promise<void> {
    const store = this.requireStore();
    const transaction = await this.acquireNotificationEntryTransaction(store);
    const minuteStart = Math.floor(entry.happenedAt / 60000) * 60000;
    let changed = false;
    try {
      const matches = await transaction.querySql(
        'SELECT id, category, accounting_type FROM ledger_entries WHERE happened_at >= ? AND happened_at < ? ' +
        'AND amount_fen = ? AND direction = ? AND has_time = 1 LIMIT 1',
        [minuteStart, minuteStart + 60000, entry.amountFen, entry.direction]
      );
      let existingId = '';
      let existingCategory = '';
      let existingAccountingType = '';
      try {
        if (matches.goToNextRow()) {
          existingId = matches.getString(matches.getColumnIndex('id'));
          existingCategory = matches.getString(matches.getColumnIndex('category'));
          existingAccountingType = matches.getString(matches.getColumnIndex('accounting_type'));
        }
      } finally {
        matches.close();
      }
      if (existingId.length > 0) {
        const updates: relationalStore.ValuesBucket = {};
        if (existingCategory === '其他' && entry.category !== '其他') {
          updates['category'] = entry.category;
        }
        if (existingAccountingType === 'normal' && accountingTypeOf(entry) === 'credit-card') {
          updates['accounting_type'] = 'credit-card';
        }
        if (Object.keys(updates).length > 0) {
          const predicates = new relationalStore.RdbPredicates('ledger_entries');
          predicates.equalTo('id', existingId);
          await transaction.update(updates, predicates);
          await transaction.execute('DELETE FROM credit_history_undo WHERE entry_id = ?', [existingId]);
          changed = true;
        }
      } else {
        await transaction.insert('ledger_entries', this.toValues(entry), relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        changed = true;
      }
      await transaction.commit();
    } catch (error) {
      try { await transaction.rollback(); } catch (_rollbackError) {}
      throw new Error((error as Error).message);
    }
    if (changed) {
      this.emitLedgerEntriesChanged();
    }
  }

  private async acquireNotificationEntryTransaction(store: relationalStore.RdbStore): Promise<relationalStore.Transaction> {
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        return await store.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
      } catch (error) {
        const failure = error as BusinessError;
        if (failure.code !== 14800024 || attempt === 19) {
          throw error as Error;
        }
        await new Promise<void>((resolve) => setTimeout(resolve, 100));
      }
    }
    throw new Error('账本正忙，请稍后重试');
  }

  observeLedgerEntriesChanged(observer: () => void): void {
    this.requireStore().on(LEDGER_ENTRIES_CHANGED_EVENT, true, observer);
  }

  removeLedgerEntriesChangedObserver(observer: () => void): void {
    this.requireStore().off(LEDGER_ENTRIES_CHANGED_EVENT, true, observer);
  }

  async addEntries(entries: LedgerEntry[]): Promise<void> {
    if (entries.length === 0) {
      return;
    }
    const store = this.requireStore();
    const rows: relationalStore.ValuesBucket[] = [];
    entries.forEach((entry: LedgerEntry) => {
      rows.push(this.toValues(entry));
    });
    await store.batchInsert('ledger_entries', rows);
    this.emitLedgerEntriesChanged();
  }

  async markCreditCardEntries(entries: LedgerEntry[]): Promise<number> {
    if (entries.length === 0) {
      return 0;
    }
    const store = this.requireStore();
    const handledIds: Set<string> = new Set<string>();
    const changedEntries: LedgerEntry[] = [];
    let updatedCount = 0;
    store.beginTransaction();
    try {
      for (const entry of entries) {
        if (handledIds.has(entry.id) || entry.direction !== 'expense' || accountingTypeOf(entry) !== 'normal') {
          continue;
        }
        handledIds.add(entry.id);
        const changed = await store.update({ accounting_type: 'credit-card' }, this.snapshotPredicates(entry, 'normal'));
        if (changed > 0) { changedEntries.push(entry); }
        updatedCount += changed;
      }
      if (updatedCount > 0) {
        await store.executeSql('DELETE FROM credit_history_undo');
        for (const entry of changedEntries) {
          await store.insert('credit_history_undo', { entry_id: entry.id, snapshot: JSON.stringify(entry) });
        }
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error((error as Error).message);
    }
    if (updatedCount > 0) {
      this.emitLedgerEntriesChanged();
    }
    return updatedCount;
  }

  async creditHistoryUndoCount(): Promise<number> {
    const result = await this.requireStore().querySql('SELECT COUNT(*) AS total FROM credit_history_undo');
    try { return result.goToNextRow() ? result.getLong(result.getColumnIndex('total')) : 0; }
    finally { result.close(); }
  }

  async importBackupEntries(entries: LedgerEntry[], applyConfiguration: () => Promise<void>): Promise<BackupRestoreResult> {
    const store = this.requireStore();
    let summary: BackupRestoreResult;
    store.beginTransaction();
    try {
      const existing = await this.listEntries();
      summary = planBackupRestore(entries, existing);
      const ids = new Set<string>(existing.map((entry: LedgerEntry) => entry.id));
      for (const entry of entries) {
        if (!ids.has(entry.id)) { await store.insert('ledger_entries', this.toValues(entry)); }
      }
      await applyConfiguration();
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error((error as Error).message);
    }
    try { this.emitLedgerEntriesChanged(); } catch (_error) { /* 页面在恢复后主动重载。 */ }
    return summary;
  }

  async undoCreditCardEntries(): Promise<number> {
    const store = this.requireStore();
    let updated = 0;
    store.beginTransaction();
    try {
      const result = await store.querySql('SELECT snapshot FROM credit_history_undo');
      const snapshots: LedgerEntry[] = [];
      try {
        while (result.goToNextRow()) {
          snapshots.push(JSON.parse(result.getString(result.getColumnIndex('snapshot'))) as LedgerEntry);
        }
      } finally { result.close(); }
      for (const entry of snapshots) {
        updated += await store.update({ accounting_type: 'normal' }, this.snapshotPredicates(entry, 'credit-card'));
      }
      await store.executeSql('DELETE FROM credit_history_undo');
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error((error as Error).message);
    }
    if (updated > 0) { this.emitLedgerEntriesChanged(); }
    return updated;
  }

  private snapshotPredicates(entry: LedgerEntry, type: AccountingType): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates('ledger_entries');
    predicates.equalTo('id', entry.id);
    predicates.equalTo('direction', entry.direction);
    predicates.equalTo('accounting_type', type);
    predicates.equalTo('happened_at', entry.happenedAt);
    predicates.equalTo('has_time', entry.hasTime ? 1 : 0);
    predicates.equalTo('amount_fen', entry.amountFen);
    predicates.equalTo('source', entry.source);
    predicates.equalTo('merchant', entry.merchant);
    predicates.equalTo('category', entry.category);
    predicates.equalTo('note', entry.note);
    predicates.equalTo('provenance', entry.provenance === undefined ? '' : JSON.stringify(entry.provenance));
    return predicates;
  }

  async updateEntry(entry: LedgerEntry): Promise<void> {
    const store = this.requireStore();
    const predicates = new relationalStore.RdbPredicates('ledger_entries');
    predicates.equalTo('id', entry.id);
    await store.update(this.toValues(entry), predicates);
    await store.executeSql('DELETE FROM credit_history_undo WHERE entry_id = ?', [entry.id]);
    this.emitLedgerEntriesChanged();
  }

  async deleteEntry(id: string): Promise<void> {
    const store = this.requireStore();
    const predicates = new relationalStore.RdbPredicates('ledger_entries');
    predicates.equalTo('id', id);
    await store.delete(predicates);
    await store.executeSql('DELETE FROM credit_history_undo WHERE entry_id = ?', [id]);
    this.emitLedgerEntriesChanged();
  }

  private emitLedgerEntriesChanged(): void {
    this.requireStore().emit(LEDGER_ENTRIES_CHANGED_EVENT);
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('本地账本尚未初始化');
    }
    return this.store;
  }

  private toValues(entry: LedgerEntry): relationalStore.ValuesBucket {
    return {
      id: entry.id,
      happened_at: entry.happenedAt,
      has_time: entry.hasTime ? 1 : 0,
      amount_fen: entry.amountFen,
      direction: entry.direction,
      accounting_type: accountingTypeOf(entry),
      is_fixed_expense: isFixedExpense(entry) ? 1 : 0,
      provenance: entry.provenance === undefined ? '' : JSON.stringify(entry.provenance),
      source: entry.source,
      merchant: entry.merchant,
      category: entry.category,
      note: entry.note
    };
  }
}
