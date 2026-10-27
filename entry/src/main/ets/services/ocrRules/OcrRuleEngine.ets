import type { ImportSource } from '../../model/LedgerModels';
import type {
  OcrCategoryMapping,
  OcrColumnRange,
  OcrPattern,
  OcrRule,
  OcrRuleLoadResult,
  OcrRuleValidationIssue,
  OcrSourceMatcher
} from './OcrRuleModels';

const RECEIPT_NUMBER_PATTERN = String.raw`\d+(?:[,.]\d{3})*(?:[,.]\d{1,2})?`;
const RECEIPT_DECIMAL_PATTERN = String.raw`\d+(?:[,.]\d{3})*[,.]\d{1,2}`;
const RECEIPT_AMOUNT_PATTERN = String.raw`([+-]\s*[¥￥]?\s*${RECEIPT_NUMBER_PATTERN}|[¥￥]\s*[+-]?\s*${RECEIPT_NUMBER_PATTERN}|${RECEIPT_DECIMAL_PATTERN}(?![\s\S]*${RECEIPT_DECIMAL_PATTERN}))`;
const RECEIPT_DATE_PATTERN = String.raw`((?:20\d{2}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?|\d{1,2}\s*月\s*\d{1,2}\s*日|\d{1,2}\s*[-/]\s*\d{1,2}|今天|昨天)(?:\s*\d{1,2}[:：]\d{2}(?::\d{2})?)?)`;
const ICBC_AMOUNT_PATTERN = String.raw`([+-]\s*[¥￥]?\s*\d+(?:[,.]\d{3})*(?:[,.]\d{1,2})?)`;
const ICBC_DATE_PATTERN = String.raw`((?:20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}日?|\d{1,2}月\d{1,2}日|\d{1,2}|周[一二三四五六日天]))`;
const TIME_PATTERN = String.raw`(\d{1,2}[:：]\d{2}(?::\d{2})?)`;
const DIRECTION_PATTERN = '(收入|收款|入账|支出|付款|消费)';
const DATE_FORMAT_TOKENS = ['yyyy', 'MM', 'dd', 'HH', 'mm', 'M', 'd'];
const ALIPAY_CATEGORIES = [
  '餐饮美食', '日用百货', '交通出行', '数码电器', '服饰装扮', '文化休闲', '商业服务', '信用借还',
  '充值缴费', '生活服务', '医疗健康', '运动户外', '教育培训', '美容美发', '酒店旅游', '宠物生活',
  '母婴亲子', '食品酒水', '家居家装', '生活缴费', '公益', '保险', '转账'
];

function sourceMatchers(source: ImportSource): OcrSourceMatcher[] {
  if (source === 'wechat') {
    return [
      { pattern: '微信支付|微信账单|微信钱包' },
      { pattern: '全部账单|收支统计|查找交易' },
      { pattern: '(?=[\\s\\S]*全部账单)(?=[\\s\\S]*收支统计)(?=[\\s\\S]*查找交易)' }
    ];
  }
  if (source === 'alipay') {
    return [
      { pattern: '支付宝' },
      { pattern: '搜索交易记录' },
      { pattern: '芝麻|花呗|余额宝' }
    ];
  }
  return [
    { pattern: '中国工商银行' },
    { pattern: '工商银行|工银借记卡|工银信用卡' },
    { pattern: '当页汇总笔数|人民币余额|借记卡\\(i类\\)' }
  ];
}

function categoryMapping(category: string): OcrCategoryMapping {
  const mapping: OcrCategoryMapping = { pattern: '^' + category, category: category };
  return mapping;
}

function commonRule(
  id: string,
  name: string,
  source: ImportSource,
  layoutStrategy: 'receipt-list' | 'icbc-statement' | 'generic',
  amountPattern: string,
  datePattern: string,
  incomeKeywords: string[],
  expenseKeywords: string[],
  failurePatterns: string[],
  refundPatterns: string[],
  summaryPatterns: string[]
): OcrRule {
  return {
    id: id,
    name: name,
    enabled: true,
    source: source,
    sourceName: source === 'wechat' ? '微信支付' : source === 'alipay' ? '支付宝' : '工商银行',
    layoutStrategy: layoutStrategy,
    record: layoutStrategy === 'generic' ? { mode: 'row' } : undefined,
    sourceMatchers: sourceMatchers(source),
    amountPattern: { pattern: amountPattern, groupIndex: 1 },
    datePattern: { pattern: datePattern, groupIndex: 1 },
    timePattern: { pattern: TIME_PATTERN, groupIndex: 1 },
    directionPattern: { pattern: DIRECTION_PATTERN, groupIndex: 1 },
    dateFormat: 'auto',
    incomeKeywords: incomeKeywords,
    expenseKeywords: expenseKeywords,
    failurePatterns: failurePatterns,
    refundPatterns: refundPatterns,
    summaryPatterns: summaryPatterns,
    defaultCategory: '其他',
    categoryMappings: []
  };
}

export function createDefaultOcrRules(): OcrRule[] {
  const wechat = commonRule(
    'wechat-default', '微信账单', 'wechat', 'generic', RECEIPT_AMOUNT_PATTERN, RECEIPT_DATE_PATTERN,
    ['收入', '收款', '入账'], ['支出', '付款', '消费'],
    ['已关闭', '已取消', '支付失败', '交易失败', '已撤销', '交易关闭'],
    ['退款', '退回', '已退'],
    ['收支统计', '月账单', '总支出', '总收入', '本月支出', '本月收入', '合计', '净收入', '余额', '可用金额',
      '收入.*支出', '支出.*收入', '^\\s*(收入|支出)\\s*[¥￥]?\\s*\\d+(?:[,.]\\d{3})*(?:[,.]\\d{1,2})?\\s*$']
  );
  const alipay = commonRule(
    'alipay-default', '支付宝账单', 'alipay', 'generic', RECEIPT_AMOUNT_PATTERN, RECEIPT_DATE_PATTERN,
    ['收入', '收款', '入账'], ['支出', '付款', '消费'],
    ['已关闭', '已取消', '支付失败', '交易失败', '已撤销', '交易关闭'],
    ['退款', '退回', '已退'],
    ['收支统计', '月账单', '总支出', '总收入', '本月支出', '本月收入', '合计', '净收入', '余额', '可用金额',
      '收入.*支出', '支出.*收入', '^\\s*(收入|支出)\\s*[¥￥]?\\s*\\d+(?:[,.]\\d{3})*(?:[,.]\\d{1,2})?\\s*$']
  );
  alipay.categoryMappings = ALIPAY_CATEGORIES.map((category: string) => categoryMapping(category));
  const icbc = commonRule(
    'icbc-default', '工商银行账单', 'icbc', 'icbc-statement', ICBC_AMOUNT_PATTERN, ICBC_DATE_PATTERN,
    ['收入'], ['支出'], ['交易失败', '交易关闭', '已撤销', '已取消', '失败'], ['退款', '退回', '已退'],
    ['当页汇总笔数', '人民币余额', '余额']
  );
  icbc.categoryMappings = [
    { pattern: 'ATM取款', category: '取现' },
    { pattern: '贷款本息', category: '贷款' },
    { pattern: '消费', category: '消费' }
  ];
  return [wechat, alipay, icbc];
}

function captureGroupCount(pattern: string): number {
  let count = 0;
  let inCharacterClass = false;
  let escaped = false;
  for (let index = 0; index < pattern.length; index++) {
    const character = pattern[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (character === '\\') {
      escaped = true;
      continue;
    }
    if (character === '[') {
      inCharacterClass = true;
      continue;
    }
    if (character === ']' && inCharacterClass) {
      inCharacterClass = false;
      continue;
    }
    if (character !== '(' || inCharacterClass) {
      continue;
    }
    if (pattern[index + 1] !== '?') {
      count++;
    } else if (pattern[index + 2] === '<' && pattern[index + 3] !== '=' && pattern[index + 3] !== '!') {
      count++;
    }
  }
  return count;
}

function validatePattern(pattern: OcrPattern | undefined, field: string, required: boolean): OcrRuleValidationIssue | undefined {
  if (pattern === undefined) {
    return required ? { field: field, message: '此字段的表达式必填' } : undefined;
  }
  if (typeof pattern.pattern !== 'string' || pattern.pattern.length === 0 ||
    !Number.isInteger(pattern.groupIndex) || pattern.groupIndex < 1) {
    return { field: field, message: '正则表达式或捕获组编号无效' };
  }
  try {
    new RegExp(pattern.pattern);
  } catch (_error) {
    return { field: field, message: '正则表达式无效' };
  }
  if (pattern.groupIndex > captureGroupCount(pattern.pattern)) {
    return { field: field, message: '捕获组编号超出表达式范围' };
  }
  return undefined;
}

function validateExpressionList(patterns: string[], field: string): OcrRuleValidationIssue | undefined {
  if (!Array.isArray(patterns)) {
    return { field: field, message: '表达式列表无效' };
  }
  for (const pattern of patterns) {
    if (typeof pattern !== 'string' || pattern.length === 0) {
      return { field: field, message: '表达式不能为空' };
    }
    try {
      new RegExp(pattern);
    } catch (_error) {
      return { field: field, message: '正则表达式无效' };
    }
  }
  return undefined;
}

function validateKeywordList(keywords: string[], field: string): OcrRuleValidationIssue | undefined {
  if (!Array.isArray(keywords) || keywords.some((keyword: string) => typeof keyword !== 'string')) {
    return { field: field, message: '关键词列表无效' };
  }
  return undefined;
}

export function validateOcrRule(rule: OcrRule): OcrRuleValidationIssue | undefined {
  if (rule === null || typeof rule !== 'object') {
    return { field: 'rule', message: '规则内容无效' };
  }
  if (typeof rule.id !== 'string' || rule.id.trim().length === 0 ||
    typeof rule.name !== 'string' || rule.name.trim().length === 0) {
    return { field: 'name', message: '规则标识和名称必填' };
  }
  if (typeof rule.enabled !== 'boolean') {
    return { field: 'enabled', message: '启用状态无效' };
  }
  if (rule.isCreditCard !== undefined && typeof rule.isCreditCard !== 'boolean') {
    return { field: 'isCreditCard', message: '信用卡消费标记必须为布尔值' };
  }
  if (typeof rule.source !== 'string' || rule.source.trim().length === 0) {
    return { field: 'source', message: '账单来源无效' };
  }
  if (typeof rule.sourceName !== 'string' || rule.sourceName.trim().length === 0) {
    return { field: 'sourceName', message: '来源名称无效' };
  }
  if (rule.layoutStrategy !== 'receipt-list' && rule.layoutStrategy !== 'icbc-statement' &&
    rule.layoutStrategy !== 'generic') {
    return { field: 'layoutStrategy', message: '布局策略无效' };
  }
  if (rule.minimumScore !== undefined && (!Number.isFinite(rule.minimumScore) || rule.minimumScore <= 0)) {
    return { field: 'minimumScore', message: '最低来源分必须大于 0' };
  }
  if (rule.scoreMargin !== undefined && (!Number.isFinite(rule.scoreMargin) || rule.scoreMargin < 0)) {
    return { field: 'scoreMargin', message: '来源分差不能小于 0' };
  }
  if (!Array.isArray(rule.sourceMatchers) || rule.sourceMatchers.length === 0) {
    return { field: 'sourceMatchers', message: '至少需要一条来源匹配表达式' };
  }
  for (const matcher of rule.sourceMatchers) {
    if (typeof matcher.pattern !== 'string' || matcher.pattern.length === 0 ||
      (matcher.weight !== undefined && (!Number.isFinite(matcher.weight) || matcher.weight <= 0))) {
      return { field: 'sourceMatchers', message: '来源正则表达式无效' };
    }
    try {
      new RegExp(matcher.pattern);
    } catch (_error) {
      return { field: 'sourceMatchers', message: '来源正则表达式无效' };
    }
  }
  const requiredPatterns: Array<[OcrPattern, string]> = [
    [rule.amountPattern, 'amountPattern'],
    [rule.datePattern, 'datePattern']
  ];
  for (const item of requiredPatterns) {
    const issue = validatePattern(item[0], item[1], true);
    if (issue !== undefined) {
      return issue;
    }
  }
  const optionalPatterns: Array<[OcrPattern | undefined, string]> = [
    [rule.timePattern, 'timePattern'],
    [rule.directionPattern, 'directionPattern'],
    [rule.merchantPattern, 'merchantPattern'],
    [rule.categoryPattern, 'categoryPattern']
  ];
  for (const item of optionalPatterns) {
    const issue = validatePattern(item[0], item[1], false);
    if (issue !== undefined) {
      return issue;
    }
  }
  if (rule.layoutStrategy === 'generic') {
    if (rule.record === undefined || (rule.record.mode !== 'row' && rule.record.mode !== 'anchor')) {
      return { field: 'record', message: '通用版式必须选择 row 或 anchor 记录模式' };
    }
    if (rule.record.mode === 'anchor') {
      if (typeof rule.record.anchorPattern !== 'string' || rule.record.anchorPattern.length === 0) {
        return { field: 'record.anchorPattern', message: '锚点模式必须填写起始表达式' };
      }
      try {
        new RegExp(rule.record.anchorPattern);
      } catch (_error) {
        return { field: 'record.anchorPattern', message: '锚点正则表达式无效' };
      }
    }
    const genericPatterns: Array<[OcrPattern | undefined, string]> = [
      [rule.amountPattern, 'amountPattern'], [rule.datePattern, 'datePattern'], [rule.timePattern, 'timePattern'],
      [rule.directionPattern, 'directionPattern'], [rule.merchantPattern, 'merchantPattern'],
      [rule.categoryPattern, 'categoryPattern']
    ];
    for (const item of genericPatterns) {
      if (item[0] !== undefined && item[0].groupIndex !== 1) {
        return { field: item[1], message: '通用规则固定使用第一个捕获组' };
      }
    }
    if (rule.columns !== undefined) {
      const ranges: Array<[string, OcrColumnRange | undefined]> = [
        ['amount', rule.columns.amount], ['date', rule.columns.date], ['time', rule.columns.time],
        ['direction', rule.columns.direction], ['merchant', rule.columns.merchant], ['category', rule.columns.category]
      ];
      for (const item of ranges) {
        const range = item[1];
        if (range !== undefined && (!Number.isFinite(range.left) || !Number.isFinite(range.right) ||
          range.left < 0 || range.right > 1 || range.left >= range.right)) {
          return { field: 'columns.' + item[0], message: '列范围必须满足 0 ≤ left < right ≤ 1' };
        }
      }
    }
  }
  if (typeof rule.dateFormat !== 'string' || rule.dateFormat.trim().length === 0) {
    return { field: 'dateFormat', message: '日期格式必填' };
  }
  const keywordLists: Array<[string[], string]> = [
    [rule.incomeKeywords, 'incomeKeywords'], [rule.expenseKeywords, 'expenseKeywords']
  ];
  for (const item of keywordLists) {
    const issue = validateKeywordList(item[0], item[1]);
    if (issue !== undefined) {
      return issue;
    }
  }
  const expressionLists: Array<[string[], string]> = [
    [rule.failurePatterns, 'failurePatterns'], [rule.refundPatterns, 'refundPatterns'],
    [rule.summaryPatterns, 'summaryPatterns']
  ];
  for (const item of expressionLists) {
    const issue = validateExpressionList(item[0], item[1]);
    if (issue !== undefined) {
      return issue;
    }
  }
  if (typeof rule.defaultCategory !== 'string' || rule.defaultCategory.trim().length === 0) {
    return { field: 'defaultCategory', message: '默认分类必填' };
  }
  if (!Array.isArray(rule.categoryMappings)) {
    return { field: 'categoryMappings', message: '分类映射无效' };
  }
  for (const mapping of rule.categoryMappings) {
    if (typeof mapping.pattern !== 'string' || mapping.pattern.length === 0 ||
      typeof mapping.category !== 'string' || mapping.category.trim().length === 0) {
      return { field: 'categoryMappings', message: '分类映射内容无效' };
    }
    try {
      new RegExp(mapping.pattern);
    } catch (_error) {
      return { field: 'categoryMappings', message: '分类映射正则表达式无效' };
    }
  }
  return undefined;
}

function scoreRule(text: string, rule: OcrRule): number {
  let matches = 0;
  const normalized = text.replace(/\s/g, '').toLowerCase();
  for (const matcher of rule.sourceMatchers) {
    const expression = new RegExp(matcher.pattern, 'i');
    if (expression.test(text) || expression.test(normalized)) {
      matches++;
    }
  }
  return matches;
}

interface ScoredRule {
  rule: OcrRule;
  score: number;
}

function sourceWinners(text: string, rules: OcrRule[]): ScoredRule[] {
  const winners: ScoredRule[] = [];
  for (const rule of rules) {
    if (!rule.enabled) {
      continue;
    }
    const score = scoreRule(text, rule);
    const current = winners.find((candidate: ScoredRule) => candidate.rule.source === rule.source);
    if (current === undefined) {
      winners.push({ rule: rule, score: score });
    } else if (score > current.score) {
      current.rule = rule;
      current.score = score;
    }
  }
  return winners.filter((candidate: ScoredRule) => candidate.score > 0);
}

export function selectOcrRule(text: string, rules: OcrRule[], selectedSource?: ImportSource): OcrRule | undefined {
  if (selectedSource !== undefined) {
    const candidates = rules.filter((rule: OcrRule) => rule.enabled && rule.source === selectedSource);
    if (candidates.length === 0) {
      return undefined;
    }
    let best = candidates[0];
    let bestScore = scoreRule(text, best);
    for (let index = 1; index < candidates.length; index++) {
      const score = scoreRule(text, candidates[index]);
      if (score > bestScore) {
        best = candidates[index];
        bestScore = score;
      }
    }
    return best;
  }
  const candidates = sourceWinners(text, rules);
  let best: ScoredRule | undefined = undefined;
  let matchingSources = 0;
  for (const candidate of candidates) {
    if (best === undefined || candidate.score > best.score) {
      best = candidate;
      matchingSources = 1;
    } else if (candidate.score === best.score) {
      matchingSources++;
    }
  }
  if (best === undefined || best.score === 0 || matchingSources !== 1) {
    return undefined;
  }
  return best.rule;
}

export function matchOcrPattern(text: string, pattern: OcrPattern | undefined): string | undefined {
  if (pattern === undefined) {
    return undefined;
  }
  const match = new RegExp(pattern.pattern, 'i').exec(text);
  return match === null ? undefined : match[pattern.groupIndex];
}

export function matchesOcrPatterns(text: string, patterns: string[]): boolean {
  return patterns.some((pattern: string) => new RegExp(pattern, 'i').test(text));
}

export function matchesOcrKeyword(text: string, keywords: string[]): boolean {
  const normalized = text.toLowerCase();
  return keywords.some((keyword: string) => keyword.length > 0 && normalized.indexOf(keyword.toLowerCase()) >= 0);
}

export function mapOcrCategory(text: string, rule: OcrRule): string | undefined {
  for (const mapping of rule.categoryMappings) {
    if (new RegExp(mapping.pattern, 'i').test(text)) {
      return mapping.category;
    }
  }
  return undefined;
}

export interface OcrDateParts {
  year?: number;
  month?: number;
  day?: number;
  hour?: number;
  minute?: number;
}

export interface OcrTimeParts {
  hour: number;
  minute: number;
}

export function parseOcrTimeByPattern(text: string, pattern: OcrPattern | undefined): OcrTimeParts | undefined {
  const captured = matchOcrPattern(text, pattern);
  if (captured === undefined) {
    return undefined;
  }
  const normalized = captured.replace(/[：时]/g, ':').replace(/分/g, '');
  const match = normalized.match(/(\d{1,2}):(\d{2})(?::\d{2})?/);
  if (match === null) {
    return undefined;
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour > 23 || minute > 59 ? undefined : { hour: hour, minute: minute };
}

function escapeRegexCharacter(character: string): string {
  return '\\.^$|?*+()[]{}'.indexOf(character) >= 0 ? '\\' + character : character;
}

export function parseOcrDateByFormat(text: string, format: string): OcrDateParts | undefined {
  if (format === 'auto') {
    return undefined;
  }
  let expression = '^';
  const fields: string[] = [];
  for (let index = 0; index < format.length;) {
    const token = DATE_FORMAT_TOKENS.find((candidate: string) => format.startsWith(candidate, index));
    if (token === undefined) {
      expression += format[index] === ' ' ? '\\s+' : escapeRegexCharacter(format[index]);
      index++;
      continue;
    }
    fields.push(token);
    if (token === 'yyyy') {
      expression += '(\\d{4})';
    } else if (token === 'M' || token === 'd') {
      expression += '(\\d{1,2})';
    } else {
      expression += '(\\d{2})';
    }
    index += token.length;
  }
  expression += '$';
  const match = new RegExp(expression).exec(text.trim());
  if (match === null) {
    return undefined;
  }
  const result: OcrDateParts = {};
  fields.forEach((field: string, index: number) => {
    const value = Number(match[index + 1]);
    if (field === 'yyyy') {
      result.year = value;
    } else if (field === 'M' || field === 'MM') {
      result.month = value;
    } else if (field === 'd' || field === 'dd') {
      result.day = value;
    } else if (field === 'HH') {
      result.hour = value;
    } else if (field === 'mm') {
      result.minute = value;
    }
  });
  return result;
}

export function decodeOcrRuleStore(value: string | undefined): OcrRuleLoadResult {
  if (value === undefined) {
    return { rules: createDefaultOcrRules(), persistDefaults: true };
  }
  let stored: Object;
  try {
    stored = JSON.parse(value) as Object;
  } catch (_error) {
    throw new Error('OCR 识别规则数据格式无效');
  }
  if (!(stored instanceof Object) || Array.isArray(stored)) {
    throw new Error('OCR 识别规则数据版本或内容无效');
  }
  const record = stored as Record<string, Object>;
  const version = record['version'];
  const rawRules = record['rules'];
  if ((version !== 1 && version !== 2) || !Array.isArray(rawRules)) {
    throw new Error('OCR 识别规则数据版本或内容无效');
  }
  const legacy = version === 1;
  const rules: OcrRule[] = [];
  for (const value of rawRules as Object[]) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('已保存的 OCR 识别规则无效');
    }
    const storedRule = value as OcrRule;
    const rule: OcrRule = storedRule;
    if (legacy && (typeof rule.sourceName !== 'string' || rule.sourceName.trim().length === 0)) {
      rule.sourceName = rule.source === 'wechat' ? '微信支付' :
        rule.source === 'alipay' ? '支付宝' : rule.source === 'icbc' ? '工商银行' : rule.name;
    }
    const issue = validateOcrRule(rule);
    if (issue !== undefined) {
      throw new Error('已保存的 OCR 识别规则无效：' + issue.message);
    }
    if (!legacy && (typeof rule.sourceName !== 'string' || rule.sourceName.trim().length === 0)) {
      throw new Error('已保存的 OCR 识别规则无效：来源名称必填');
    }
    rules.push(rule);
  }
  return { rules: rules, persistDefaults: false, migrated: legacy };
}
