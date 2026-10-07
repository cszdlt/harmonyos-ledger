import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import {
  emitNotificationArchiveChanged,
  listenForNotificationArchiveChanges,
  NotificationArchiveEventStore,
  stopListeningForNotificationArchiveChanges
} from './NotificationArchiveChangeEvents';
import {
  NotificationArchiveCursor,
  NotificationArchiveEntry,
  NotificationArchiveFilter,
  NotificationArchivePage,
  NotificationSource
} from '../model/NotificationArchiveModels';

const TABLE_NAME: string = 'notification_events';
const PAGE_SIZE: number = 50;

export class NotificationArchiveRepository {
  private store: relationalStore.RdbStore | undefined = undefined;
  private opening: Promise<void> | undefined = undefined;

  async open(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    if (this.opening === undefined) {
      this.opening = this.initialize(context);
    }
    try {
      await this.opening;
    } finally {
      this.opening = undefined;
    }
  }

  async append(info: notificationExtensionSubscription.NotificationInfo, receivedAt: number): Promise<void> {
    const deliveryTime = typeof info.deliveryTime === 'number' &&
      Number.isFinite(info.deliveryTime) && info.deliveryTime > 0 ? info.deliveryTime : 0;
    await this.requireStore().insert(TABLE_NAME, {
      hash_code: info.hashCode,
      slot_type: info.notificationSlotType,
      bundle_name: info.bundleName,
      app_name: info.appName ?? '',
      delivery_time: deliveryTime,
      group_name: info.groupName ?? '',
      app_index: info.appIndex,
      title: info.content.title,
      body: info.content.text,
      received_at: receivedAt,
      event_time: deliveryTime > 0 ? deliveryTime : receivedAt
    });
  }

  emitArchiveChanged(): void {
    emitNotificationArchiveChanged(this.requireStore() as NotificationArchiveEventStore);
  }

  listenForArchiveChanges(observer: () => void): void {
    listenForNotificationArchiveChanges(this.requireStore() as NotificationArchiveEventStore, observer);
  }

  stopListeningForArchiveChanges(observer: () => void): void {
    if (this.store !== undefined) {
      stopListeningForNotificationArchiveChanges(this.store as NotificationArchiveEventStore, observer);
    }
  }

  async listSources(): Promise<NotificationSource[]> {
    const result = await this.requireStore().querySql(
      'SELECT n.bundle_name, n.app_name FROM notification_events n ' +
      'JOIN (SELECT bundle_name, MAX(id) AS latest_id FROM notification_events GROUP BY bundle_name) latest ' +
      'ON latest.latest_id = n.id ' +
      'ORDER BY n.app_name COLLATE NOCASE, n.bundle_name'
    );
    const sources: NotificationSource[] = [];
    try {
      while (result.goToNextRow()) {
        sources.push({
          bundleName: result.getString(result.getColumnIndex('bundle_name')),
          appName: result.getString(result.getColumnIndex('app_name'))
        });
      }
    } finally {
      result.close();
    }
    return sources;
  }

  async listPage(filter: NotificationArchiveFilter, cursor?: NotificationArchiveCursor): Promise<NotificationArchivePage> {
    const conditions: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    if (filter.bundleName.length > 0) {
      conditions.push('bundle_name = ?');
      args.push(filter.bundleName);
    }
    const keyword = filter.keyword.trim();
    if (keyword.length > 0) {
      const pattern = '%' + this.escapeLike(keyword) + '%';
      conditions.push("(title LIKE ? ESCAPE '!' OR body LIKE ? ESCAPE '!')");
      args.push(pattern, pattern);
    }
    if (filter.startTime !== undefined) {
      conditions.push('event_time >= ?');
      args.push(filter.startTime);
    }
    if (filter.endTimeExclusive !== undefined) {
      conditions.push('event_time < ?');
      args.push(filter.endTimeExclusive);
    }
    if (cursor !== undefined) {
      conditions.push('(event_time < ? OR (event_time = ? AND id < ?))');
      args.push(cursor.eventTime, cursor.eventTime, cursor.id);
    }
    const where = conditions.length > 0 ? ' WHERE ' + conditions.join(' AND ') : '';
    args.push(PAGE_SIZE);
    const result = await this.requireStore().querySql(
      'SELECT id, hash_code, slot_type, bundle_name, app_name, delivery_time, group_name, ' +
      'app_index, title, body, received_at, event_time FROM notification_events' + where +
      ' ORDER BY event_time DESC, id DESC LIMIT ?', args
    );
    const entries: NotificationArchiveEntry[] = [];
    try {
      while (result.goToNextRow()) {
        entries.push({
          id: result.getLong(result.getColumnIndex('id')),
          hashCode: result.getString(result.getColumnIndex('hash_code')),
          slotType: result.getLong(result.getColumnIndex('slot_type')),
          bundleName: result.getString(result.getColumnIndex('bundle_name')),
          appName: result.getString(result.getColumnIndex('app_name')),
          deliveryTime: result.getLong(result.getColumnIndex('delivery_time')),
          groupName: result.getString(result.getColumnIndex('group_name')),
          appIndex: result.getLong(result.getColumnIndex('app_index')),
          title: result.getString(result.getColumnIndex('title')),
          body: result.getString(result.getColumnIndex('body')),
          receivedAt: result.getLong(result.getColumnIndex('received_at')),
          eventTime: result.getLong(result.getColumnIndex('event_time'))
        });
      }
    } finally {
      result.close();
    }
    const last = entries.length > 0 ? entries[entries.length - 1] : undefined;
    return {
      entries: entries,
      nextCursor: entries.length === PAGE_SIZE && last !== undefined ?
        { eventTime: last.eventTime, id: last.id } : undefined
    };
  }

  private async initialize(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'notification_archive.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS notification_events (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      'hash_code TEXT NOT NULL,' +
      'slot_type INTEGER NOT NULL,' +
      'bundle_name TEXT NOT NULL,' +
      'app_name TEXT NOT NULL,' +
      'delivery_time INTEGER NOT NULL,' +
      'group_name TEXT NOT NULL,' +
      'app_index INTEGER NOT NULL,' +
      'title TEXT NOT NULL,' +
      'body TEXT NOT NULL,' +
      'received_at INTEGER NOT NULL,' +
      'event_time INTEGER NOT NULL)'
    );
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_notification_events_time ON notification_events (event_time DESC, id DESC)'
    );
    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_notification_events_source ON notification_events ' +
      '(bundle_name, event_time DESC, id DESC)'
    );
    this.store = store;
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('通知归档尚未初始化');
    }
    return this.store;
  }

  private escapeLike(keyword: string): string {
    return keyword.replace(/!/g, '!!').replace(/%/g, '!%').replace(/_/g, '!_');
  }
}
