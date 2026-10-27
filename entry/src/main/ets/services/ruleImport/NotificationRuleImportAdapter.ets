import { formatDateTime, parseAmountFen } from '../../model/LedgerModels';
import type { NotificationInput, NotificationRule } from '../notificationRules/NotificationRuleModels';
import { parseNotificationEntry } from '../notificationRules/NotificationRuleEngine';
import type { CompactNotificationRule, RuleImportExample, RuleImportExpectedFields, RuleImportPreview } from './RuleImportModels';

function uniqueRuleId(keywords: string[], existingRules: NotificationRule[]): string {
  const firstKeyword = keywords.length > 0 ? keywords[0] : 'custom-rule';
  const base = 'notice-ai-' + firstKeyword.replace(/[^a-zA-Z0-9_-]/g, '-');
  let candidate = base;
  let suffix = 2;
  while (existingRules.some((rule: NotificationRule) => rule.id === candidate)) {
    candidate = base + '-' + suffix;
    suffix++;
  }
  return candidate;
}

export function createNotificationRule(description: CompactNotificationRule,
  existingRules: NotificationRule[]): NotificationRule {
  const rule: NotificationRule = {
    id: uniqueRuleId(description.sourceKeywords, existingRules),
    name: description.name,
    enabled: true,
    isCreditCard: description.isCreditCard,
    sourceKeywords: description.sourceKeywords.slice(),
    bodyPattern: description.bodyPattern,
    semanticCaptures: true,
    incomeText: description.incomeText,
    expenseText: description.expenseText,
    dateFormat: description.dateFormat,
    dateStrategy: description.dateStrategy,
    defaultMerchant: description.defaultMerchant,
    defaultCategory: description.defaultCategory,
    categoryMappings: [],
    merchantPrefixToStrip: '',
    noteTemplate: '',
    entrySource: description.entrySource
  };
  return rule;
}

function previewInput(example: RuleImportExample, sourceKeyword: string): NotificationInput {
  const timestamp = new Date(2026, 9, 6, 12, 0, 0, 0).getTime();
  return {
    appName: sourceKeyword,
    bundleName: 'rule.import.preview',
    body: example.input,
    deliveryTime: timestamp,
    receivedAt: timestamp
  };
}

function expectedMatches(actual: RuleImportExpectedFields, expected: RuleImportExpectedFields): boolean {
  if (expected.amount !== undefined) {
    if (actual.amount === undefined) {
      return false;
    }
    const expectedFen = parseAmountFen(expected.amount);
    const actualFen = parseAmountFen(actual.amount);
    if (expectedFen === undefined || actualFen === undefined || expectedFen !== actualFen) {
      return false;
    }
  }
  if (expected.date !== undefined) {
    if (actual.date === undefined) {
      return false;
    }
    if (expected.date.length === 10 ? !actual.date.startsWith(expected.date) : actual.date !== expected.date) {
      return false;
    }
  }
  if (expected.direction !== undefined && actual.direction !== expected.direction) {
    return false;
  }
  if (expected.merchant !== undefined && actual.merchant !== expected.merchant) {
    return false;
  }
  if (expected.category !== undefined && actual.category !== expected.category) {
    return false;
  }
  return true;
}

export function previewNotificationRule(rule: NotificationRule, examples: RuleImportExample[]): RuleImportPreview[] {
  return examples.map((example: RuleImportExample) => {
    const entry = parseNotificationEntry(previewInput(example, rule.sourceKeywords[0]), [rule]);
    const actual: RuleImportExpectedFields | undefined = entry === undefined ? undefined : {
      amount: (entry.amountFen / 100).toFixed(2),
      date: formatDateTime(entry.happenedAt),
      direction: entry.direction,
      merchant: entry.merchant,
      category: entry.category
    };
    const preview: RuleImportPreview = {
      input: example.input,
      expected: example.expected,
      actual: actual,
      matched: actual !== undefined && expectedMatches(actual, example.expected)
    };
    return preview;
  });
}
