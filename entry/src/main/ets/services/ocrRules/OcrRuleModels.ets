import type { ImportSource } from '../../model/LedgerModels';

export type OcrLayoutStrategy = 'receipt-list' | 'icbc-statement' | 'generic';
export type OcrRecordMode = 'row' | 'anchor';

export interface OcrPattern {
  pattern: string;
  groupIndex: number;
}

export interface OcrSourceMatcher {
  pattern: string;
  weight?: number;
}

export interface OcrRecordConfig {
  mode: OcrRecordMode;
  anchorPattern?: string;
}

export interface OcrColumnRange {
  left: number;
  right: number;
}

export interface OcrColumns {
  amount?: OcrColumnRange;
  date?: OcrColumnRange;
  time?: OcrColumnRange;
  direction?: OcrColumnRange;
  merchant?: OcrColumnRange;
  category?: OcrColumnRange;
}

export interface OcrCategoryMapping {
  pattern: string;
  category: string;
}

export interface OcrRule {
  id: string;
  name: string;
  enabled: boolean;
  isCreditCard?: boolean;
  source: ImportSource;
  sourceName?: string;
  layoutStrategy: OcrLayoutStrategy;
  record?: OcrRecordConfig;
  columns?: OcrColumns;
  sourceMatchers: OcrSourceMatcher[];
  minimumScore?: number;
  scoreMargin?: number;
  amountPattern: OcrPattern;
  datePattern: OcrPattern;
  timePattern?: OcrPattern;
  directionPattern?: OcrPattern;
  merchantPattern?: OcrPattern;
  categoryPattern?: OcrPattern;
  dateFormat: string;
  incomeKeywords: string[];
  expenseKeywords: string[];
  failurePatterns: string[];
  refundPatterns: string[];
  summaryPatterns: string[];
  defaultCategory: string;
  categoryMappings: OcrCategoryMapping[];
}

export interface OcrRuleStore {
  version: 2;
  rules: OcrRule[];
}

export interface OcrRuleLoadResult {
  rules: OcrRule[];
  persistDefaults: boolean;
  migrated?: boolean;
}

export interface OcrRuleValidationIssue {
  field: string;
  message: string;
}
