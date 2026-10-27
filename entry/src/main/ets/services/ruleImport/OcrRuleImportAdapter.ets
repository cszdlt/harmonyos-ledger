import { parseAmountFen } from '../../model/LedgerModels';
import type { DraftEntry } from '../../model/LedgerModels';
import type { OcrLine } from '../../model/OcrModels';
import type { OcrCategoryMapping, OcrColumnRange, OcrColumns, OcrPattern, OcrRecordConfig, OcrRule, OcrSourceMatcher } from '../ocrRules/OcrRuleModels';
import { GenericOcrParser } from '../GenericOcrParser';
import type { CompactOcrColumnRange, CompactOcrColumns, CompactOcrRule, RuleImportExample, RuleImportExpectedFields, RuleImportPreview } from './RuleImportModels';

function pattern(value: string | undefined): OcrPattern | undefined {
  if (value === undefined) {
    return undefined;
  }
  const result: OcrPattern = { pattern: value, groupIndex: 1 };
  return result;
}

function uniqueRuleId(sourceId: string, existingRules: OcrRule[]): string {
  const base = 'ocr-ai-' + sourceId.replace(/[^a-zA-Z0-9_-]/g, '-');
  let candidate = base;
  let suffix = 2;
  while (existingRules.some((rule: OcrRule) => rule.id === candidate)) {
    candidate = base + '-' + suffix;
    suffix++;
  }
  return candidate;
}

function columnRange(range: CompactOcrColumnRange | undefined): OcrColumnRange | undefined {
  if (range === undefined) {
    return undefined;
  }
  const result: OcrColumnRange = { left: range.left, right: range.right };
  return result;
}

function columns(source: CompactOcrColumns | undefined): OcrColumns | undefined {
  if (source === undefined) {
    return undefined;
  }
  const result: OcrColumns = {
    amount: columnRange(source.amount),
    date: columnRange(source.date),
    time: columnRange(source.time),
    direction: columnRange(source.direction),
    merchant: columnRange(source.merchant),
    category: columnRange(source.category)
  };
  return result;
}

export function createOcrRule(description: CompactOcrRule, existingRules: OcrRule[]): OcrRule {
  const matchers: OcrSourceMatcher[] = description.source.patterns.map((item: string): OcrSourceMatcher => {
    const matcher: OcrSourceMatcher = { pattern: item };
    return matcher;
  });
  const record: OcrRecordConfig = {
    mode: description.record.mode,
    anchorPattern: description.record.mode === 'anchor' ? description.record.anchor : undefined
  };
  const categoryMappings: OcrCategoryMapping[] = description.categoryMappings === undefined ? [] :
    description.categoryMappings.map((mapping): OcrCategoryMapping => {
      const copied: OcrCategoryMapping = { pattern: mapping.pattern, category: mapping.category };
      return copied;
    });
  const amountPattern: OcrPattern = { pattern: description.fields.amount, groupIndex: 1 };
  const datePattern: OcrPattern = { pattern: description.fields.date, groupIndex: 1 };
  return {
    id: uniqueRuleId(description.source.id, existingRules),
    name: description.name,
    enabled: true,
    isCreditCard: description.isCreditCard,
    source: description.source.id,
    sourceName: description.source.name,
    layoutStrategy: 'generic',
    record: record,
    columns: columns(description.columns),
    sourceMatchers: matchers,
    amountPattern: amountPattern,
    datePattern: datePattern,
    timePattern: pattern(description.fields.time),
    directionPattern: pattern(description.fields.direction),
    merchantPattern: pattern(description.fields.merchant),
    categoryPattern: pattern(description.fields.category),
    dateFormat: description.dateFormat === undefined || description.dateFormat.trim().length === 0 ?
      'auto' : description.dateFormat,
    incomeKeywords: description.incomeKeywords.slice(),
    expenseKeywords: description.expenseKeywords.slice(),
    failurePatterns: description.failurePatterns?.slice() ?? [],
    refundPatterns: description.refundPatterns?.slice() ?? [],
    summaryPatterns: description.summaryPatterns?.slice() ?? [],
    defaultCategory: description.defaultCategory,
    categoryMappings: categoryMappings
  };
}

function sampleLines(input: string): OcrLine[] {
  return input.split(/\r?\n/).filter((text: string) => text.trim().length > 0)
    .map((text: string, index: number): OcrLine => {
      const line: OcrLine = {
        text: text,
        left: 0,
        top: index * 24,
        right: 1000,
        bottom: index * 24 + 20,
        centerY: index * 24 + 10,
        height: 20
      };
      return line;
    });
}

function draftFields(draft: DraftEntry): RuleImportExpectedFields {
  return {
    amount: draft.amountText,
    date: draft.dateText,
    direction: draft.direction,
    merchant: draft.merchant,
    category: draft.category
  };
}

function sameExpected(actual: RuleImportExpectedFields, expected: RuleImportExpectedFields): boolean {
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
  if (expected.date !== undefined && actual.date !== expected.date) {
    return false;
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

export function previewOcrRule(rule: OcrRule, examples: RuleImportExample[]): RuleImportPreview[] {
  const previewRule: OcrRule = {
    id: rule.id,
    name: rule.name,
    enabled: rule.enabled,
    isCreditCard: rule.isCreditCard,
    source: rule.source,
    sourceName: rule.sourceName,
    layoutStrategy: rule.layoutStrategy,
    record: rule.record,
    columns: undefined,
    sourceMatchers: rule.sourceMatchers,
    minimumScore: rule.minimumScore,
    scoreMargin: rule.scoreMargin,
    amountPattern: rule.amountPattern,
    datePattern: rule.datePattern,
    timePattern: rule.timePattern,
    directionPattern: rule.directionPattern,
    merchantPattern: rule.merchantPattern,
    categoryPattern: rule.categoryPattern,
    dateFormat: rule.dateFormat,
    incomeKeywords: rule.incomeKeywords,
    expenseKeywords: rule.expenseKeywords,
    failurePatterns: rule.failurePatterns,
    refundPatterns: rule.refundPatterns,
    summaryPatterns: rule.summaryPatterns,
    defaultCategory: rule.defaultCategory,
    categoryMappings: rule.categoryMappings
  };
  return examples.map((example: RuleImportExample) => {
    const drafts = GenericOcrParser.parse(sampleLines(example.input), rule.source, previewRule, [], [], undefined, 1000);
    const expectedDraft = drafts.find((draft) => sameExpected(draftFields(draft), example.expected));
    const actualDraft = expectedDraft ?? drafts[0];
    const actual = actualDraft === undefined ? undefined : draftFields(actualDraft);
    const preview: RuleImportPreview = {
      input: example.input,
      expected: example.expected,
      actual: actual,
      matched: expectedDraft !== undefined,
      message: rule.columns === undefined ? undefined : '文本样例不含坐标，列范围未参与预览。'
    };
    return preview;
  });
}
