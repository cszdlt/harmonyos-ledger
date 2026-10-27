import type { EntryProvenance } from '../../model/LedgerModels';

export type NotificationDateStrategy = 'format' | 'infer-year' | 'delivery-time';

export interface NotificationCategoryMapping {
  text: string;
  matchMode: 'startsWith' | 'includes';
  category: string;
}

export interface NotificationRule {
  id: string;
  name: string;
  enabled: boolean;
  isCreditCard?: boolean;
  sourceKeywords: string[];
  bodyPattern: string;
  semanticCaptures?: boolean;
  amountGroup?: number;
  directionGroup?: number;
  incomeText: string;
  expenseText: string;
  dateGroup?: number;
  dateFormat: string;
  dateStrategy: NotificationDateStrategy;
  merchantGroup?: number;
  categoryGroup?: number;
  defaultMerchant: string;
  defaultCategory: string;
  categoryMappings: NotificationCategoryMapping[];
  merchantPrefixToStrip: string;
  noteTemplate: string;
  entrySource?: string;
}

export interface NotificationSemanticCaptures {
  amount?: number;
  direction?: number;
  date?: number;
  merchant?: number;
  category?: number;
}

export interface NotificationInput {
  appName: string;
  bundleName: string;
  title?: string;
  body: string;
  deliveryTime?: number;
  receivedAt: number;
}

export type NotificationEntryDirection = 'income' | 'expense';

export interface ParsedNotificationEntry {
  provenance?: EntryProvenance;
  id: string;
  happenedAt: number;
  hasTime: boolean;
  amountFen: number;
  direction: NotificationEntryDirection;
  accountingType?: 'normal' | 'credit-card' | 'credit-repayment';
  source: string;
  merchant: string;
  category: string;
  note: string;
}

export interface NotificationRuleStore {
  version: 1 | 2;
  rules: NotificationRule[];
  defaultRulesVersion?: number;
}

export interface NotificationRuleLoadResult {
  rules: NotificationRule[];
  persistDefaults: boolean;
  migrated?: boolean;
}

export interface RuleValidationIssue {
  field: string;
  message: string;
}
