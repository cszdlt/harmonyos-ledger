export type RuleImportKind = 'ocr' | 'notification';

export type RuleImportDirection = 'income' | 'expense';

export interface RuleImportExpectedFields {
  amount?: string;
  date?: string;
  direction?: RuleImportDirection;
  merchant?: string;
  category?: string;
}

export interface RuleImportExample {
  input: string;
  expected: RuleImportExpectedFields;
}

export interface CompactOcrRecord {
  mode: 'row' | 'anchor';
  anchor?: string;
}

export interface CompactOcrSource {
  id: string;
  name: string;
  patterns: string[];
}

export interface CompactOcrFields {
  amount: string;
  date: string;
  time?: string;
  direction?: string;
  merchant?: string;
  category?: string;
}

export interface CompactOcrColumnRange {
  left: number;
  right: number;
}

export interface CompactOcrColumns {
  amount?: CompactOcrColumnRange;
  date?: CompactOcrColumnRange;
  time?: CompactOcrColumnRange;
  direction?: CompactOcrColumnRange;
  merchant?: CompactOcrColumnRange;
  category?: CompactOcrColumnRange;
}

export interface CompactOcrCategoryMapping {
  pattern: string;
  category: string;
}

export interface CompactOcrRule {
  name: string;
  isCreditCard?: boolean;
  source: CompactOcrSource;
  record: CompactOcrRecord;
  fields: CompactOcrFields;
  columns?: CompactOcrColumns;
  dateFormat?: string;
  incomeKeywords: string[];
  expenseKeywords: string[];
  failurePatterns?: string[];
  refundPatterns?: string[];
  summaryPatterns?: string[];
  defaultCategory: string;
  categoryMappings?: CompactOcrCategoryMapping[];
}

export interface CompactNotificationRule {
  name: string;
  isCreditCard?: boolean;
  sourceKeywords: string[];
  bodyPattern: string;
  incomeText: string;
  expenseText: string;
  dateFormat: string;
  dateStrategy: 'format' | 'infer-year' | 'delivery-time';
  defaultMerchant: string;
  defaultCategory: string;
  entrySource?: string;
}

export interface RuleImportIssue {
  field: string;
  message: string;
}

export interface RuleImportSuccess {
  valid: true;
  kind: RuleImportKind;
  rule: CompactOcrRule | CompactNotificationRule;
  examples: RuleImportExample[];
}

export interface RuleImportFailure {
  valid: false;
  issues: RuleImportIssue[];
}

export type RuleImportParseResult = RuleImportSuccess | RuleImportFailure;

export interface RuleImportPreview {
  input: string;
  expected: RuleImportExpectedFields;
  actual?: RuleImportExpectedFields;
  matched: boolean;
  message?: string;
}
