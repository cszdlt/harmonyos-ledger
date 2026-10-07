export const NOTIFICATION_ARCHIVE_CHANGED_EVENT: string = 'notification_archive_changed';

export interface NotificationArchiveEventStore {
  emit(event: string): void;
  on(event: string, interProcess: boolean, observer: () => void): void;
  off(event: string, interProcess: boolean, observer?: () => void): void;
}

export function emitNotificationArchiveChanged(store: NotificationArchiveEventStore): void {
  store.emit(NOTIFICATION_ARCHIVE_CHANGED_EVENT);
}

export function listenForNotificationArchiveChanges(
  store: NotificationArchiveEventStore,
  observer: () => void
): void {
  store.on(NOTIFICATION_ARCHIVE_CHANGED_EVENT, true, observer);
}

export function stopListeningForNotificationArchiveChanges(
  store: NotificationArchiveEventStore,
  observer: () => void
): void {
  store.off(NOTIFICATION_ARCHIVE_CHANGED_EVENT, true, observer);
}
