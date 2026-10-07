export interface NotificationArchiveEntry {
  id: number;
  hashCode: string;
  slotType: number;
  bundleName: string;
  appName: string;
  deliveryTime: number;
  groupName: string;
  appIndex: number;
  title: string;
  body: string;
  receivedAt: number;
  eventTime: number;
}

export interface NotificationSource {
  bundleName: string;
  appName: string;
}

export function filterNotificationSources(sources: NotificationSource[], query: string): NotificationSource[] {
  const normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.length === 0) {
    return sources;
  }
  return sources.filter((source: NotificationSource) =>
    source.appName.toLowerCase().includes(normalizedQuery) ||
      source.bundleName.toLowerCase().includes(normalizedQuery));
}

export interface NotificationArchiveFilter {
  bundleName: string;
  keyword: string;
  startTime?: number;
  endTimeExclusive?: number;
}

export interface NotificationArchiveCursor {
  eventTime: number;
  id: number;
}

export interface NotificationArchivePage {
  entries: NotificationArchiveEntry[];
  nextCursor?: NotificationArchiveCursor;
}
