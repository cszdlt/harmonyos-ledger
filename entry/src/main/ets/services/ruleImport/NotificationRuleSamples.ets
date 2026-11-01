import { parseAmountFen } from '../notificationRules/AmountParser';
import { notificationRuleExcludesText, notificationRuleMatchesSourceAndTitle, parseNotificationEntry } from '../notificationRules/NotificationRuleEngine';
import type { NotificationInput, NotificationRule } from '../notificationRules/NotificationRuleModels';
import { buildNotificationRulePrompt } from './RuleImportEngine';
import { changeRuleSample, sampleExpected, validateRuleSample, previewNotificationSample } from './RuleImportGuide';
import type { RuleSampleDraft } from './RuleImportGuide';
import type { RuleImportExpectedFields, RuleImportPreview } from './RuleImportModels';

export interface NotificationRuleSample {
  id: number;
  draft: RuleSampleDraft;
}

interface NotificationSampleMaterial {
  source: string;
  title: string;
  input: string;
  excluded: boolean;
  deliveryTime?: number;
  receivedAt?: number;
  expected?: RuleImportExpectedFields;
  amountHint?: string;
  amountLocation?: string;
}

const AMOUNT_VARIANTS: string[] = ['0.01', '7', '18.5', '1234.56', '1,234.56', '1,234,567.89'];

export interface NotificationAmountLocation {
  key: string;
  field: string;
  start: number;
  end: number;
  label: string;
}

export function notificationAmountLocations(sample: RuleSampleDraft): NotificationAmountLocation[] {
  const amountFen = parseAmountFen(sample.amount);
  if (amountFen === undefined || amountFen <= 0) { return []; }
  const locations: NotificationAmountLocation[] = [];
  for (const field of ['input', 'title']) {
    const text = field === 'input' ? sample.input : sample.title;
    const numbers = /\d+(?:[.,]\d+)*/g;
    let match = numbers.exec(text);
    while (match !== null) {
      if (parseAmountFen(match[0]) === amountFen) {
        locations.push({ key: field + ':' + match.index, field: field, start: match.index,
          end: match.index + match[0].length,
          label: (field === 'input' ? '正文' : '标题') + '：' +
            text.slice(Math.max(0, match.index - 10), match.index) + '【' + match[0] + '】' +
            text.slice(match.index + match[0].length, match.index + match[0].length + 10) });
      }
      match = numbers.exec(text);
    }
  }
  return locations;
}

export function validateNotificationSamples(samples: RuleSampleDraft[]): string {
  if (samples.length === 0) { return '请先选择或提供通知样例。'; }
  if (!samples.some((sample: RuleSampleDraft) => sample.excluded !== true)) {
    return '至少保留一条包含样例，才能生成入账规则。';
  }
  for (let index = 0; index < samples.length; index++) {
    if (samples[index].source !== samples[0].source) { return '请选择同一应用包名下的通知样例。'; }
    if (samples[index].excluded === true) {
      if (samples[index].source.trim().length === 0) { return '样例 ' + (index + 1) + '：请填写来源名称。'; }
      if (samples[index].input.trim().length === 0) { return '样例 ' + (index + 1) + '：请提供通知原文。'; }
      continue;
    }
    const issue = validateRuleSample(samples[index], 'notification');
    if (issue.length > 0) { return '样例 ' + (index + 1) + '：' + issue; }
    const locations = notificationAmountLocations(samples[index]);
    if (locations.length > 1 && !locations.some((location: NotificationAmountLocation) => location.key === samples[index].amountLocation)) {
      return '样例 ' + (index + 1) + '：存在多处等值数字，请确认交易金额位置，不要选择余额或卡号。';
    }
  }
  return '';
}

export function notificationSampleStatus(sample: RuleSampleDraft): string {
  if (sample.excluded === true) { return '排除'; }
  if (validateRuleSample(sample, 'notification').length > 0) { return '待配置'; }
  const locations = notificationAmountLocations(sample);
  if (locations.length > 1 && !locations.some((location: NotificationAmountLocation) =>
    location.key === sample.amountLocation)) { return '待配置'; }
  return '已填写';
}

export function buildNotificationSamplesPrompt(samples: RuleSampleDraft[]): string {
  return buildNotificationRulePrompt() + '\n\n' +
    '【批量样例】excluded=false 为入账样例，excluded=true 为排除样例；保留全部 expected。只生成一条 rule。\n' +
    JSON.stringify(samples.map((sample: RuleSampleDraft): NotificationSampleMaterial => {
      const material: NotificationSampleMaterial = { source: sample.source, title: sample.title, input: sample.input,
        excluded: sample.excluded === true, deliveryTime: sample.deliveryTime, receivedAt: sample.receivedAt };
      if (sample.excluded !== true) {
        material.expected = sampleExpected(sample);
        material.amountLocation = sample.amountLocation;
      } else if (sample.amount.trim().length > 0) {
        material.amountHint = sample.amount;
        material.amountLocation = sample.amountLocation;
      }
      return material;
    }), null, 2) + '\n' +
    '要求：rule 须匹配全部入账样例；excludeBodyPatterns 须拦截全部排除样例。sourceKeywords 用完整包名。' +
    '金额与排除正则均须通配，禁止写死样例数字。有 amountLocation 时只提取该处金额。' +
    'delivery-time 时按各条 deliveryTime（否则 receivedAt）理解日期。只返回 JSON；一次不过预览很正常，按应用内提示迭代。';
}

function notificationInput(sample: RuleSampleDraft): NotificationInput {
  const timestamp = new Date(2026, 9, 6, 12, 0, 0, 0).getTime();
  return { appName: sample.source, bundleName: sample.source, title: sample.title, body: sample.input,
    deliveryTime: sample.deliveryTime ?? timestamp, receivedAt: sample.receivedAt ?? sample.deliveryTime ?? timestamp };
}

function previewExcludedNotificationSample(rule: NotificationRule, sample: RuleSampleDraft,
  existingRules: NotificationRule[]): RuleImportPreview {
  const input = notificationInput(sample);
  const text = sample.title.length === 0 ? sample.input : sample.title + '\n' + sample.input;
  const sourceAndTitleMatch = notificationRuleMatchesSourceAndTitle(rule, input);
  const exclusionMatch = notificationRuleExcludesText(rule, text);
  const parsed = parseNotificationEntry(input, [rule].concat(existingRules));
  let matched = sourceAndTitleMatch && exclusionMatch && parsed === undefined;
  let message = matched ? '排除正则命中，正式解析不会入账，也不会尝试后续规则。' :
    '排除验证未通过：需要命中排除正则，并确认通知不会生成账目。';
  if (matched && notificationAmountLocations(sample).length > 0) {
    const failures = AMOUNT_VARIANTS.filter((amount: string) =>
      !matchesExcludedAmountVariant(rule, sample, amount, existingRules));
    if (failures.length > 0) {
      matched = false;
      message = '排除正则金额泛化检查未通过：' + failures.join('、') + ' 元。请勿写死样例金额。';
    } else {
      message += ' 金额泛化检查通过。';
    }
  }
  return { input: sample.input, expected: {}, actual: undefined, matched: matched,
    message: message };
}

function matchesExcludedAmountVariant(rule: NotificationRule, sample: RuleSampleDraft, amount: string,
  existingRules: NotificationRule[]): boolean {
  const locations = notificationAmountLocations(sample);
  const location = locations.length === 1 ? locations[0] :
    locations.find((item: NotificationAmountLocation) => item.key === sample.amountLocation);
  if (location === undefined) { return true; }
  const text = location.field === 'input' ? sample.input : sample.title;
  const replaced = text.slice(0, location.start) + amount + text.slice(location.end);
  const candidate = changeRuleSample(changeRuleSample(sample, location.field, replaced), 'amount', amount);
  const input = notificationInput(candidate);
  const notificationText = candidate.title.length === 0 ? candidate.input : candidate.title + '\n' + candidate.input;
  return notificationRuleMatchesSourceAndTitle(rule, input) && notificationRuleExcludesText(rule, notificationText) &&
    parseNotificationEntry(input, [rule].concat(existingRules)) === undefined;
}

// 多处数字等值时只替换人工指定的位置，不能用余额替换代替交易金额验证。
function matchesAmountVariant(rule: NotificationRule, sample: RuleSampleDraft, amount: string): boolean {
  const locations = notificationAmountLocations(sample);
  const location = locations.length === 1 ? locations[0] :
    locations.find((item: NotificationAmountLocation) => item.key === sample.amountLocation);
  if (location === undefined) { return false; }
  const text = location.field === 'input' ? sample.input : sample.title;
  const replaced = text.slice(0, location.start) + amount + text.slice(location.end);
  const candidate = changeRuleSample(changeRuleSample(sample, location.field, replaced), 'amount', amount);
  return previewNotificationSample(rule, candidate).matched;
}

export function previewNotificationSamples(rule: NotificationRule, samples: RuleSampleDraft[],
  existingRules: NotificationRule[] = []): RuleImportPreview[] {
  return samples.map((sample: RuleSampleDraft): RuleImportPreview => {
    if (sample.excluded === true) {
      return previewExcludedNotificationSample(rule, sample, existingRules);
    }
    const preview = previewNotificationSample(rule, sample, existingRules);
    if (!preview.matched) { return preview; }
    const failures = AMOUNT_VARIANTS.filter((amount: string) => !matchesAmountVariant(rule, sample, amount));
    if (failures.length > 0) {
      preview.matched = false;
      preview.message = '原通知字段一致；金额泛化检查未通过：' + failures.join('、') +
        ' 元。请让 AI 调整金额正则，不要写死金额或位数。';
    } else {
      preview.message = '原通知字段一致；整数、小数、千分位及较大金额泛化检查通过。';
    }
    return preview;
  });
}
