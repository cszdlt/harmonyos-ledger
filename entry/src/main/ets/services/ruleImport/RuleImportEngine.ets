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
import { isBuiltInNotificationRuleName } from '../notificationRules/NotificationRuleEngine';

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
  if (dateStrategy !== 'delivery-time' && typeof rule['dateFormat'] === 'string' &&
    (!(rule['dateFormat'] as string).includes('HH') || !(rule['dateFormat'] as string).includes('mm'))) {
    issues.push({ field: 'rule.dateFormat', message: '日期格式必须包含 HH 和 mm' });
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
      "amount": "金额[:：]\\s*([+-]?\\s*[¥￥]?\\s*[\\d,.]+)",
      "date": "日期[:：]\\s*((?:20\\d{2}[-/.年])?\\d{1,2}[-/.月]\\d{1,2}日?)",
      "direction": "(收入|支出)",
      "merchant": "商户[:：]\\s*(.+)"
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
    '根据我提供的 OCR 原文和期望结果生成一条账单识别规则。只返回一个 JSON 对象，不要代码围栏或解释。',
    '可选字段 rule.isCreditCard 为布尔值，只有明确为信用卡消费的来源或版式才填 true；它只标记支出，不改变收入方向。',
    '金额与日期表达式必须把要提取的值放在第一个捕获组中；其他结构括号使用非捕获组。来源 patterns、anchor 和字段值都是正则表达式。',
    'record.mode 只能是 row（每个视觉行一条记录）或 anchor（匹配 anchor 后至下一锚点组成一条记录）。只填写样例能支持判断的字段；不要猜日期、商户或方向。',
    '表达式不确定时请在预期样例中如实保留空缺，不要声称可稳定识别。格式示例：',
    example,
    '把你的真实 OCR 原文及人工确认的预期解析结果补入 examples。金额使用原文形式，direction 使用 income 或 expense。'
  ].join('\n\n');
}

export const NOTIFICATION_RULE_PROMPT_JSON_EXAMPLE: string = String.raw`{
  "schemaVersion": 1,
  "kind": "notification",
  "rule": {
    "name": "工行自动入账恢复",
    "sourceKeywords": ["工商银行", "icbc"],
    "bodyPattern": "尾号\\s*\\d{4}\\s*卡\\s*(?<date>\\d{1,2}月\\d{1,2}日\\s*\\d{1,2}:\\d{2})\\s*(?:ATM)?\\s*(?<direction>支出|收入)\\s*(?=[（(]\\s*(?<category>[^）)]*?)\\s*[）)])\\s*[（(]\\s*(?<merchant>[^）)]*?)\\s*[）)]\\s*(?<amount>(?:\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?|\\d+(?:[.,]\\d{1,2})?))\\s*元",
    "incomeText": "收入",
    "expenseText": "支出",
    "dateFormat": "M月d日 HH:mm",
    "dateStrategy": "infer-year",
    "defaultMerchant": "工商银行账户",
    "defaultCategory": "其他",
    "entrySource": "icbc"
  },
  "examples": [
    {
      "input": "尾号0000卡1月2日03:04ATM支出(ATM取款)1,000元。请点击查看详情。",
      "expected": {
        "amount": "1000",
        "date": "2027-01-02",
        "direction": "expense",
        "merchant": "ATM取款"
      }
    },
    {
      "input": "尾号1111卡1月1日02:03支出(超市)12.34元",
      "expected": {
        "amount": "12.34",
        "date": "2027-01-01",
        "direction": "expense",
        "merchant": "超市"
      }
    }
  ]
}`;

export function buildNotificationRulePrompt(): string {
  return [
    '请根据我提供的通知来源信息、通知正文和人工确认结果，生成一条可被本应用通知规则导入器接受并通过预览的规则。',
    '只输出一个合法 JSON 对象，不要 Markdown 代码围栏、注释、尾随逗号或解释。若样例不足以确定来源、金额、方向或日期，请先向我提问，不要编造规则。',
    '顶层只能包含 schemaVersion、kind、rule、examples；schemaVersion 固定为 1，kind 固定为 "notification"。rule 必填字段为 name、sourceKeywords、bodyPattern、incomeText、expenseText、dateFormat、dateStrategy、defaultMerchant、defaultCategory；entrySource 可选，用于账目来源，工商银行填 "icbc"；isCreditCard 可选，只有明确属于信用卡消费的规则才填 true，它只标记支出。不要输出未列出的 rule 字段。',
    'sourceKeywords 用于匹配通知应用名或包名，不是标题或正文关键词。examples[].input 填完整原始通知正文；标题不能代替正文。正文末尾可能有“请点击查看详情”等无关文案，正则应只匹配交易部分，除非样例能证明后缀是必需内容，不要用 $ 强制正文结束。',
    'bodyPattern 是 JavaScript RegExp。必须以唯一的命名捕获组提取 amount 和 direction；有可靠交易日期时再提取 date，可选 merchant 和 category。捕获名仅允许 amount、direction、date、merchant、category。所有结构括号写成非捕获组 (?:...)，不能使用未命名捕获组、数字组编号或重复命名组。',
    'amount 应只捕获交易金额，并按样例支持千位分隔符和小数；不要把积分、余额、尾号等数字匹配为金额。direction 捕获值必须与 incomeText 或 expenseText 中的某一项完全相同；examples.expected.direction 使用 income 或 expense。',
    'dateStrategy 只能是 format、infer-year、delivery-time。通知正文含完整年月日和时分时用 format；含月日和时分但没有年份时用 infer-year；正文没有可靠交易时间时才用 delivery-time。非 delivery-time 必须有 date 命名捕获，dateFormat 必须与捕获原文一致并含 HH、mm；只使用 yyyy、MM、dd、M、d、HH、mm 这些日期格式符号。不得用投递时间冒充正文中的交易时间，也不得猜测缺失日期。',
    'defaultMerchant 是未提取到商户时的回退值；defaultCategory 是未提取到分类时的回退值。若使用 category 捕获且没有分类映射，捕获文本会直接成为分类。',
    'examples 必须使用原始正文和人工确认的预期值；expected 只能包含 amount、date、direction、merchant、category，且只填写样例能确认的字段。保留原文中的商户文字，不要擅自改写。',
    '本导入格式不支持 categoryMappings、merchantPrefixToStrip、noteTemplate 等运行时字段，不要输出它们；需要分类映射或商户前缀处理时，在规则导入后通过编辑器设置。工商银行括号里的“ATM取款”需映射为“取现”时，导入后添加对应分类映射。',
    '下面是工商银行规则示例。它兼容交易时间后没有 ATM 和紧跟 ATM 两种正文写法；生成其他来源规则时，只借鉴 JSON 结构与正则写法，不要照搬工商银行关键词或表达式：',
    NOTIFICATION_RULE_PROMPT_JSON_EXAMPLE
  ].join('\n\n');
}
