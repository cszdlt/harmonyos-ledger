import test from 'node:test';
import assert from 'node:assert/strict';
import {
  emitNotificationArchiveChanged,
  listenForNotificationArchiveChanges,
  stopListeningForNotificationArchiveChanges
} from '../entry/src/main/ets/data/NotificationArchiveChangeEvents.ets';

test('archive changes notify an interprocess listener and can be unsubscribed', () => {
  const listeners = new Set();
  const events = [];
  const store = {
    emit(event) {
      events.push(event);
      for (const listener of listeners) {
        listener();
      }
    },
    on(event, interProcess, observer) {
      assert.equal(interProcess, true);
      listeners.add(observer);
    },
    off(event, interProcess, observer) {
      assert.equal(interProcess, true);
      listeners.delete(observer);
    }
  };
  let refreshCount = 0;
  const refresh = () => refreshCount++;

  listenForNotificationArchiveChanges(store, refresh);
  emitNotificationArchiveChanged(store);
  assert.equal(refreshCount, 1);
  assert.deepEqual(events, ['notification_archive_changed']);

  stopListeningForNotificationArchiveChanges(store, refresh);
  emitNotificationArchiveChanged(store);
  assert.equal(refreshCount, 1);
});
