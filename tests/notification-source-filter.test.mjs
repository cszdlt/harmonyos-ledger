import test from 'node:test';
import assert from 'node:assert/strict';
import { filterNotificationSources } from '../entry/src/main/ets/model/NotificationArchiveModels.ets';

const sources = [
  { bundleName: 'com.alipay.mobile', appName: '支付宝' },
  { bundleName: 'com.tencent.mm', appName: '微信支付' },
  { bundleName: 'com.bank.citic', appName: '中信银行' }
];

test('source search matches app names and bundle names case-insensitively', () => {
  assert.deepEqual(filterNotificationSources(sources, ' 微信 '), [sources[1]]);
  assert.deepEqual(filterNotificationSources(sources, 'CITIC'), [sources[2]]);
});

test('empty source search returns all sources and unmatched search returns none', () => {
  assert.deepEqual(filterNotificationSources(sources, '  '), sources);
  assert.deepEqual(filterNotificationSources(sources, '不存在的应用'), []);
});
