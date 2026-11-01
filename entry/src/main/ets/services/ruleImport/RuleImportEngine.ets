import type {
  CompactNotificationRule,
  CompactOcrRule,
  RuleImportExample,
  RuleImportExpectedFields,
  RuleImportIssue,
  RuleImportKind,
  RuleImportParseResult
} from './RuleImportModels';
import { parseRuleImportJson } from './RuleImportJson';
import { isBuiltInNotificationRuleName, validateNotificationDateFormat } from '../notificationRules/NotificationRuleEngine';
import type { NotificationDateStrategy } from '../notificationRules/NotificationRuleModels';

const OCR_FIELDS: string[] = ['amount', 'date', 'time', 'direction', 'merchant', 'category'];
const NOTIFICATION_CAPTURE_NAMES: string[] = ['amount', 'direction', 'date', 'merchant', 'category'];
const EXAMPLE_FIELDS: string[] = ['amount', 'date', 'direction', 'merchant', 'category'];

function recordOf(value: Object | undefined): Record<string, Object> | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as Record<string, Object>;
}

function nonEmptyString(value: Object | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function stringArray(value: Object | undefined): boolean {
  if (!Array.isArray(value)) {
    return false;
  }
  for (const item of value as Object[]) {
    if (typeof item !== 'string') {
      return false;
    }
  }
  return true;
}

function validateRegex(pattern: Object | undefined, field: string, issues: RuleImportIssue[], needsCapture: boolean): void {
  if (typeof pattern !== 'string' || pattern.length === 0) {
    issues.push({ field: field, message: '正则表达式必填' });
    return;
  }
  try {
    new RegExp(pattern);
  } catch (_error) {
    issues.push({ field: field, message: '正则表达式语法无效' });
    return;
  }
  if (needsCapture && scanCaptureGroups(pattern).count === 0) {
    issues.push({ field: field, message: '表达式至少需要一个捕获组，并将值放在第一个捕获组中' });
  }
}

interface CaptureScanResult {
  count: number;
  names: string[];
  unnamedCount: number;
}

function scanCaptureGroups(pattern: string): CaptureScanResult {
  let count = 0;
  let escaped = false;
  let inCharacterClass = false;
  const names: string[] = [];
  let unnamedCount = 0;
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
      unnamedCount++;
      continue;
    }
    if (pattern[index + 2] === '<' && pattern[index + 3] !== '=' && pattern[index + 3] !== '!') {
      const end = pattern.indexOf('>', index + 3);
      if (end > index + 3) {
        count++;
        names.push(pattern.substring(index + 3, end));
        index = end;
      }
    }
  }
  return { count: count, names: names, unnamedCount: unnamedCount };
}

function validatePatternList(value: Object | undefined, field: string, issues: RuleImportIssue[]): void {
  if (value === undefined) {
    return;
  }
  if (!Array.isArray(value)) {
    issues.push({ field: field, message: '此字段必须是正则表达式数组' });
    return;
  }
  const patterns = value as Object[];
  patterns.forEach((pattern: Object, index: number) => {
    validateRegex(pattern, field + '[' + index + ']', issues, false);
  });
}

function validateKeywords(value: Object | undefined, field: string, issues: RuleImportIssue[]): void {
  if (!stringArray(value)) {
    issues.push({ field: field, message: '至少需要一个非空关键词' });
    return;
  }
  const keywords = value as string[];
  if (keywords.length === 0 || keywords.some((item: string) => item.trim().length === 0)) {
    issues.push({ field: field, message: '至少需要一个非空关键词' });
  }
}

function validateOcrColumns(value: Object | undefined, issues: RuleImportIssue[]): void {
  if (value === undefined) {
    return;
  }
  const columns = recordOf(value);
  if (columns === undefined) {
    issues.push({ field: 'rule.columns', message: '列范围必须是对象' });
    return;
  }
  Object.keys(columns).forEach((name: string) => {
    const field = 'rule.columns.' + name;
    if (OCR_FIELDS.indexOf(name) < 0) {
      issues.push({ field: field, message: '不支持此字段的列范围' });
      return;
    }
    const range = recordOf(columns[name]);
    if (range === undefined || typeof range['left'] !== 'number' || typeof range['right'] !== 'number') {
      issues.push({ field: field, message: '需要提供 left 和 right 数值' });
      return;
    }
    const left = range['left'] as number;
    const right = range['right'] as number;
    if (!Number.isFinite(left) || !Number.isFinite(right) || left < 0 || right > 1 || left >= right) {
      issues.push({ field: field, message: '列范围必须满足 0 ≤ left < right ≤ 1' });
    }
  });
}

function validateOcrMappings(value: Object | undefined, issues: RuleImportIssue[]): void {
  if (value === undefined) {
    return;
  }
  if (!Array.isArray(value)) {
    issues.push({ field: 'rule.categoryMappings', message: '分类映射必须是数组' });
    return;
  }
  const mappings = value as Object[];
  mappings.forEach((item: Object, index: number) => {
    const field = 'rule.categoryMappings[' + index + ']';
    const mapping = recordOf(item);
    if (mapping === undefined) {
      issues.push({ field: field, message: '分类映射必须是对象' });
      return;
    }
    validateRegex(mapping['pattern'], field + '.pattern', issues, false);
    if (!nonEmptyString(mapping['category'])) {
      issues.push({ field: field + '.category', message: '分类名称必填' });
    }
  });
}

function validateOcrRule(value: Object | undefined, issues: RuleImportIssue[]): void {
  const rule = recordOf(value);
  if (rule === undefined) {
    issues.push({ field: 'rule', message: 'OCR 规则必须是对象' });
    return;
  }
  if (!nonEmptyString(rule['name'])) {
    issues.push({ field: 'rule.name', message: '规则名称必填' });
  }
  const source = recordOf(rule['source']);
  if (source === undefined) {
    issues.push({ field: 'rule.source', message: '来源必须是对象' });
  } else {
    if (!nonEmptyString(source['id'])) {
      issues.push({ field: 'rule.source.id', message: '来源标识必填' });
    }
    if (!nonEmptyString(source['name'])) {
      issues.push({ field: 'rule.source.name', message: '来源名称必填' });
    }
    const patterns = source['patterns'];
    if (!Array.isArray(patterns) || patterns.length === 0) {
      issues.push({ field: 'rule.source.patterns', message: '至少需要一个来源匹配正则' });
    } else {
      (patterns as Object[]).forEach((pattern: Object, index: number) => {
        validateRegex(pattern, 'rule.source.patterns[' + index + ']', issues, false);
      });
    }
  }

  const record = recordOf(rule['record']);
  if (record === undefined) {
    issues.push({ field: 'rule.record', message: '记录模式必须是对象' });
  } else if (record['mode'] === 'row') {
    // One visually grouped row forms one candidate record.
  } else if (record['mode'] === 'anchor') {
    validateRegex(record['anchor'], 'rule.record.anchor', issues, false);
  } else {
    issues.push({ field: 'rule.record.mode', message: '记录模式必须是 row 或 anchor' });
  }

  const fields = recordOf(rule['fields']);
  if (fields === undefined) {
    issues.push({ field: 'rule.fields', message: '字段配置必须是对象' });
  } else {
    validateRegex(fields['amount'], 'rule.fields.amount', issues, true);
    validateRegex(fields['date'], 'rule.fields.date', issues, true);
    ['time', 'direction', 'merchant', 'category'].forEach((name: string) => {
      if (fields[name] !== undefined) {
        validateRegex(fields[name], 'rule.fields.' + name, issues, true);
      }
    });
  }
  validateOcrColumns(rule['columns'], issues);
  if (rule['dateFormat'] !== undefined && typeof rule['dateFormat'] !== 'string') {
    issues.push({ field: 'rule.dateFormat', message: '日期格式必须是文本' });
  }
  validateKeywords(rule['incomeKeywords'], 'rule.incomeKeywords', issues);
  validateKeywords(rule['expenseKeywords'], 'rule.expenseKeywords', issues);
  if (!nonEmptyString(rule['defaultCategory'])) {
    issues.push({ field: 'rule.defaultCategory', message: '默认分类必填' });
  }
  validatePatternList(rule['failurePatterns'], 'rule.failurePatterns', issues);
  validatePatternList(rule['refundPatterns'], 'rule.refundPatterns', issues);
  validatePatternList(rule['summaryPatterns'], 'rule.summaryPatterns', issues);
  validateOcrMappings(rule['categoryMappings'], issues);
}

function validateNotificationCaptures(pattern: string, issues: RuleImportIssue[]): void {
  const scanned = scanCaptureGroups(pattern);
  const captures = scanned.names;
  if (scanned.unnamedCount > 0) {
    issues.push({ field: 'rule.bodyPattern', message: '通知规则使用语义命名捕获，结构分组请写为 (?:...)' });
  }
  const seen: string[] = [];
  captures.forEach((name: string) => {
    if (seen.indexOf(name) >= 0) {
      issues.push({ field: 'rule.bodyPattern', message: '命名捕获不能重复：' + name });
    }
    seen.push(name);
    if (NOTIFICATION_CAPTURE_NAMES.indexOf(name) < 0) {
      issues.push({ field: 'rule.bodyPattern', message: '不支持此命名捕获：' + name });
    }
  });
  if (captures.indexOf('amount') < 0) {
    issues.push({ field: 'rule.bodyPattern', message: '正文正则必须包含命名捕获 amount' });
  }
  if (captures.indexOf('direction') < 0) {
    issues.push({ field: 'rule.bodyPattern', message: '正文正则必须包含命名捕获 direction' });
  }
}

function validateNotificationRule(value: Object | undefined, issues: RuleImportIssue[]): void {
  const rule = recordOf(value);
  if (rule === undefined) {
    issues.push({ field: 'rule', message: '通知规则必须是对象' });
    return;
  }
  if (!nonEmptyString(rule['name'])) {
    issues.push({ field: 'rule.name', message: '规则名称必填' });
  }
  const entrySource = rule['entrySource'];
  const builtInName = nonEmptyString(rule['name']) &&
    isBuiltInNotificationRuleName(rule['name'] as string);
  if (builtInName && !nonEmptyString(entrySource)) {
    issues.push({
      field: 'rule.entrySource',
      message: '内置来源名称不能直接用作自定义规则名；请填写非空 entrySource 或修改规则名称'
    });
  } else if (entrySource !== undefined && !nonEmptyString(entrySource)) {
    issues.push({ field: 'rule.entrySource', message: '账目来源必须是非空文本' });
  }
  validateKeywords(rule['sourceKeywords'], 'rule.sourceKeywords', issues);
  validateRegex(rule['bodyPattern'], 'rule.bodyPattern', issues, false);
  validatePatternList(rule['excludeBodyPatterns'], 'rule.excludeBodyPatterns', issues);
  if (typeof rule['bodyPattern'] === 'string') {
    validateNotificationCaptures(rule['bodyPattern'] as string, issues);
  }
  if (!nonEmptyString(rule['incomeText'])) {
    issues.push({ field: 'rule.incomeText', message: '收入关键词必填' });
  }
  if (!nonEmptyString(rule['expenseText'])) {
    issues.push({ field: 'rule.expenseText', message: '支出关键词必填' });
  }
  if (typeof rule['dateFormat'] !== 'string') {
    issues.push({ field: 'rule.dateFormat', message: '日期格式必须是文本' });
  }
  const dateStrategy = rule['dateStrategy'];
  if (dateStrategy !== 'format' && dateStrategy !== 'infer-year' && dateStrategy !== 'delivery-time') {
    issues.push({ field: 'rule.dateStrategy', message: '日期策略无效' });
  }
  if (dateStrategy !== 'delivery-time' && typeof rule['bodyPattern'] === 'string' &&
    scanCaptureGroups(rule['bodyPattern'] as string).names.indexOf('date') < 0) {
    issues.push({ field: 'rule.bodyPattern', message: '日期策略不是投递时间时，正文正则必须包含 date 捕获' });
  }
  if ((dateStrategy === 'format' || dateStrategy === 'infer-year' || dateStrategy === 'delivery-time') &&
    typeof rule['dateFormat'] === 'string') {
    const formatIssue = validateNotificationDateFormat(rule['dateFormat'] as string,
      dateStrategy as NotificationDateStrategy);
    if (formatIssue !== undefined) {
      issues.push({ field: 'rule.dateFormat', message: formatIssue });
    }
  }
  if (!nonEmptyString(rule['defaultMerchant'])) {
    issues.push({ field: 'rule.defaultMerchant', message: '默认商户必填' });
  }
  if (!nonEmptyString(rule['defaultCategory'])) {
    issues.push({ field: 'rule.defaultCategory', message: '默认分类必填' });
  }
}

function parseExamples(value: Object | undefined, issues: RuleImportIssue[]): RuleImportExample[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    issues.push({ field: 'examples', message: '样例必须是数组' });
    return [];
  }
  const examples: RuleImportExample[] = [];
  (value as Object[]).forEach((item: Object, index: number) => {
    const field = 'examples[' + index + ']';
    const example = recordOf(item);
    if (example === undefined || typeof example['input'] !== 'string' || example['input'] === '') {
      issues.push({ field: field + '.input', message: '样例原文必填' });
      return;
    }
    const expected = recordOf(example['expected']);
    if (expected === undefined) {
      issues.push({ field: field + '.expected', message: '预期结果必须是对象' });
      return;
    }
    let fieldCount = 0;
    let valid = true;
    Object.keys(expected).forEach((name: string) => {
      const expectedField = field + '.expected.' + name;
      if (EXAMPLE_FIELDS.indexOf(name) < 0) {
        issues.push({ field: expectedField, message: '不支持此预期字段' });
        valid = false;
        return;
      }
      const expectedValue = expected[name];
      if (name === 'direction') {
        if (expectedValue !== 'income' && expectedValue !== 'expense') {
          issues.push({ field: expectedField, message: '方向只能是 income 或 expense' });
          valid = false;
        } else {
          fieldCount++;
        }
      } else if (typeof expectedValue !== 'string') {
        issues.push({ field: expectedField, message: '预期值必须是文本' });
        valid = false;
      } else {
        fieldCount++;
      }
    });
    if (fieldCount === 0) {
      issues.push({ field: field + '.expected', message: '至少填写一个预期字段' });
      valid = false;
    }
    if (valid) {
      examples.push({
        input: example['input'] as string,
        expected: expected as RuleImportExpectedFields
      });
    }
  });
  return examples;
}

export function parseRuleImport(text: string, expectedKind: RuleImportKind): RuleImportParseResult {
  let parsed: Object;
  try {
    parsed = parseRuleImportJson(text, expectedKind);
  } catch (_error) {
    return { valid: false, issues: [{ field: '$', message: '内容不是有效 JSON' }] };
  }
  const root = recordOf(parsed);
  if (root === undefined) {
    return { valid: false, issues: [{ field: '$', message: '规则 JSON 顶层必须是对象' }] };
  }
  const issues: RuleImportIssue[] = [];
  if (root['schemaVersion'] !== 1) {
    issues.push({ field: 'schemaVersion', message: '只支持规则格式版本 1' });
  }
  if (root['kind'] !== expectedKind) {
    issues.push({ field: 'kind', message: '此处需要导入 ' + expectedKind + ' 规则' });
  }
  if (issues.length > 0) {
    return { valid: false, issues: issues };
  }

  const rule = recordOf(root['rule']);
  if (rule !== undefined && rule['isCreditCard'] !== undefined && typeof rule['isCreditCard'] !== 'boolean') {
    issues.push({ field: 'rule.isCreditCard', message: '信用卡消费标记必须为布尔值' });
  }
  if (expectedKind === 'ocr') {
    validateOcrRule(root['rule'], issues);
  } else {
    validateNotificationRule(root['rule'], issues);
  }
  const examples = parseExamples(root['examples'], issues);
  if (issues.length > 0 || rule === undefined) {
    return { valid: false, issues: issues };
  }
  return {
    valid: true,
    kind: expectedKind,
    rule: rule as Object as CompactOcrRule | CompactNotificationRule,
    examples: examples
  };
}

export function buildOcrRulePrompt(): string {
  const example = String.raw`{
  "schemaVersion": 1,
  "kind": "ocr",
  "rule": {
    "name": "示例钱包",
    "source": { "id": "example-wallet", "name": "示例钱包", "patterns": ["Example Wallet"] },
    "record": { "mode": "row" },
    "fields": {
      "amount": "金额[:：]\\s*([\\d,.]+)",
      "date": "((?:20\\d{2}[-/.年])?\\d{1,2}[-/.月]\\d{1,2}日?)",
      "direction": "(收入|支出)"
    },
    "incomeKeywords": ["收入"],
    "expenseKeywords": ["支出"],
    "defaultCategory": "其他"
  },
  "examples": [
    { "input": "示例 OCR 原文", "expected": { "amount": "12.34", "direction": "expense" } }
  ]
}`;
  return [
    '任务：根据下方 OCR 原文和 expected，生成一条 ocr 规则 JSON。只输出 JSON，不要围栏或解释。',
    'record.mode：row（一行一条）或 anchor（需 record.anchor 正则）。fields 里 amount/date 等用正则，提取值放在第一个捕获组；其余括号用 (?:…)。',
    '只填样例能支持的字段；不要猜日期/商户/方向。可选 rule.isCreditCard（仅信用卡消费支出）。',
    '',
    '【结构示例】',
    example
  ].join('\n');
}

export const NOTIFICATION_RULE_PROMPT_JSON_EXAMPLE: string = String.raw`{
  "schemaVersion": 1,
  "kind": "notification",
  "rule": {
    "name": "示例支付",
    "sourceKeywords": ["com.example.pay"],
    "bodyPattern": "(?<direction>收入|支出)(?<amount>\\d+(?:\\.\\d{1,2})?)元",
    "incomeText": "收入",
    "expenseText": "支出",
    "dateFormat": "yyyy-MM-dd HH:mm",
    "dateStrategy": "delivery-time",
    "defaultMerchant": "示例商户",
    "defaultCategory": "其他"
  },
  "examples": [
    {
      "input": "支出12.34元",
      "expected": { "amount": "12.34", "direction": "expense" }
    }
  ]
}`;

export function buildNotificationRulePrompt(): string {
  return [
    '任务：根据下方用户样例，生成一条 notification 规则 JSON。只输出 JSON，不要 Markdown 围栏或解释。',
    '若信息不够做可靠正则，只回复一句需要补充什么，不要编造。',
    '',
    '【顶层】schemaVersion=1，kind="notification"，字段仅 rule + examples（及顶层已有字段）。',
    '【rule 必填】name、sourceKeywords、bodyPattern、incomeText、expenseText、dateFormat、dateStrategy、defaultMerchant、defaultCategory。',
    '【rule 可选】excludeBodyPatterns（排除正文正则数组）、entrySource（如 icbc）、isCreditCard（仅信用卡消费支出）。不要输出 categoryMappings 等未列字段。',
    '【sourceKeywords】匹配应用名或包名，不是标题/正文关键词。',
    '【bodyPattern】JavaScript 正则：必须有命名捕获 (?<amount>…) 和 (?<direction>…)；可选 (?<date>…)、(?<merchant>…)、(?<category>…)。结构用 (?:…)，禁止未命名捕获。amount 只匹配交易金额（可含千分位与小数），不要匹配尾号/余额。direction 捕获值须等于 incomeText 或 expenseText 之一。',
    '【dateStrategy】format（正文有完整年月日时分，dateFormat 含 yyyy）| infer-year（有月日时分无年）| delivery-time（正文无可靠交易时间）。非 delivery-time 时 bodyPattern 须含 (?<date>…)。dateFormat 仅用 yyyy MM dd M d HH mm。',
    '【examples】仅包含样例；input 为完整正文；expected 用 amount/date/direction/merchant/category，direction 为 income 或 expense。排除样例不进 examples，用 excludeBodyPatterns。',
    '【金额】须通配多种金额写法，禁止写死样例数字、固定位数或枚举。',
    '',
    '【最小结构示例（勿照搬关键词，只参考字段与捕获名写法）】',
    NOTIFICATION_RULE_PROMPT_JSON_EXAMPLE
  ].join('\n');
}
