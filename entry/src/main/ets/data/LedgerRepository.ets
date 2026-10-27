import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { AccountingType, EntryDirection, EntrySource, LedgerEntry, accountingTypeOf } from '../model/LedgerModels';

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
      "accounting_type TEXT NOT NULL DEFAULT 'normal')"
    );
    const columns = await this.store.querySql('PRAGMA table_info(ledger_entries)');
    let hasTimeColumn = false;
    let hasAccountingTypeColumn = false;
    try {
      while (columns.goToNextRow()) {
        if (columns.getString(columns.getColumnIndex('name')) === 'has_time') {
          hasTimeColumn = true;
        }
        if (columns.getString(columns.getColumnIndex('name')) === 'accounting_type') {
          hasAccountingTypeColumn = true;
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
  }

  async listEntries(): Promise<LedgerEntry[]> {
    const store = this.requireStore();
    const result = await store.querySql(
      'SELECT id, happened_at, amount_fen, direction, source, merchant, category, note, has_time, accounting_type ' +
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
    const minuteStart = Math.floor(entry.happenedAt / 60000) * 60000;
    const matches = await store.querySql(
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
        await store.update(updates, predicates);
        this.emitLedgerEntriesChanged();
      }
      return;
    }
    await store.insert('ledger_entries', this.toValues(entry), relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
    this.emitLedgerEntriesChanged();
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
    let updatedCount = 0;
    store.beginTransaction();
    try {
      for (const entry of entries) {
        if (handledIds.has(entry.id) || entry.direction !== 'expense' || accountingTypeOf(entry) !== 'normal') {
          continue;
        }
        handledIds.add(entry.id);
        const predicates = new relationalStore.RdbPredicates('ledger_entries');
        predicates.equalTo('id', entry.id);
        predicates.equalTo('direction', 'expense');
        predicates.equalTo('accounting_type', 'normal');
        predicates.equalTo('happened_at', entry.happenedAt);
        predicates.equalTo('has_time', entry.hasTime ? 1 : 0);
        predicates.equalTo('amount_fen', entry.amountFen);
        predicates.equalTo('source', entry.source);
        predicates.equalTo('merchant', entry.merchant);
        predicates.equalTo('category', entry.category);
        predicates.equalTo('note', entry.note);
        updatedCount += await store.update({ accounting_type: 'credit-card' }, predicates);
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

  async updateEntry(entry: LedgerEntry): Promise<void> {
    const store = this.requireStore();
    const predicates = new relationalStore.RdbPredicates('ledger_entries');
    predicates.equalTo('id', entry.id);
    await store.update(this.toValues(entry), predicates);
    this.emitLedgerEntriesChanged();
  }

  async deleteEntry(id: string): Promise<void> {
    const store = this.requireStore();
    const predicates = new relationalStore.RdbPredicates('ledger_entries');
    predicates.equalTo('id', id);
    await store.delete(predicates);
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
      source: entry.source,
      merchant: entry.merchant,
      category: entry.category,
      note: entry.note
    };
  }
}
