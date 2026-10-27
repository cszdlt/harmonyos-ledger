import type {
  OcrCategoryMapping,
  OcrColumnRange,
  OcrColumns,
  OcrLayoutStrategy,
  OcrPattern,
  OcrRule,
  OcrSourceMatcher
} from '../../services/ocrRules/OcrRuleModels';
import { validateOcrRule } from '../../services/ocrRules/OcrRuleEngine';

@Component
struct OcrRuleTextField {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  onChange: (value: string) => void = (_value: string) => {};

  build() {
    Column({ space: 5 }) {
      Text(this.label)
        .fontSize(12)
        .fontColor('#52606D');
      TextInput({ text: this.value, placeholder: this.placeholder.length > 0 ? this.placeholder : this.label })
        .fontSize(14)
        .backgroundColor('#F6F7F9')
        .borderRadius(8)
        .onChange((value: string) => this.onChange(value));
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}

@Component
struct OcrRuleTextArea {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  onChange: (value: string) => void = (_value: string) => {};

  build() {
    Column({ space: 5 }) {
      Text(this.label)
        .fontSize(12)
        .fontColor('#52606D');
      TextArea({ text: this.value, placeholder: this.placeholder })
        .height(96)
        .fontSize(13)
        .backgroundColor('#F6F7F9')
        .borderRadius(8)
        .onChange((value: string) => this.onChange(value));
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}

@Component
export struct OcrRuleEditor {
  @Prop rule: OcrRule = {
    id: '',
    name: '',
    enabled: true,
    source: 'new-source',
    sourceName: '新来源',
    layoutStrategy: 'generic',
    record: { mode: 'row' },
    sourceMatchers: [],
    amountPattern: { pattern: '', groupIndex: 1 },
    datePattern: { pattern: '', groupIndex: 1 },
    dateFormat: 'auto',
    incomeKeywords: [],
    expenseKeywords: [],
    failurePatterns: [],
    refundPatterns: [],
    summaryPatterns: [],
    defaultCategory: '其他',
    categoryMappings: []
  };
  @State private draft: OcrRule = {
    id: '',
    name: '新 OCR 规则',
    enabled: true,
    source: 'new-source',
    sourceName: '新来源',
    layoutStrategy: 'generic',
    record: { mode: 'row' },
    sourceMatchers: [],
    amountPattern: { pattern: '', groupIndex: 1 },
    datePattern: { pattern: '', groupIndex: 1 },
    dateFormat: 'auto',
    incomeKeywords: [],
    expenseKeywords: [],
    failurePatterns: [],
    refundPatterns: [],
    summaryPatterns: [],
    defaultCategory: '其他',
    categoryMappings: []
  };
  @State private sourceMatcherText: string = '';
  @State private incomeKeywordText: string = '';
  @State private expenseKeywordText: string = '';
  @State private failurePatternText: string = '';
  @State private refundPatternText: string = '';
  @State private summaryPatternText: string = '';
  @State private categoryMappingText: string = '';
  @State private columnRangeText: string = '';
  @State private showAdvanced: boolean = false;
  @State private validationMessage: string = '';
  @State private isSubmitting: boolean = false;
  @Prop isSaving: boolean = false;
  onCancel: () => void = () => {};
  onSave: (rule: OcrRule) => Promise<string | undefined> = (_rule: OcrRule) => Promise.resolve(undefined);
  onDelete: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.draft = this.copyRule(this.rule);
    this.syncTextFields();
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Button('返回')
            .backgroundColor('#FFFFFF')
            .fontColor('#344563')
            .onClick(() => this.onCancel());
          Blank();
          Text(this.onDelete === undefined ? '新增 OCR 规则' : '编辑 OCR 规则')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          Blank();
          Blank().width(48);
        }
        .width('100%');

        Text('新规则使用通用 OCR 解析。正则请把要提取的值放在第一个捕获组；日期格式支持 yyyy、MM、dd、HH、mm、M、d，或使用 auto。')
          .fontSize(12)
          .fontColor('#52606D')
          .width('100%');

        Column({ space: 12 }) {
          OcrRuleTextField({
            label: '规则名称', value: this.draft.name,
            onChange: (value: string) => this.updateRule((rule: OcrRule) => rule.name = value)
          });
          OcrRuleTextField({
            label: '来源标识（账目中保存）', value: this.draft.source,
            onChange: (value: string) => this.updateRule((rule: OcrRule) => rule.source = value.trim())
          });
          OcrRuleTextField({
            label: '来源显示名称', value: this.draft.sourceName ?? '',
            onChange: (value: string) => this.updateRule((rule: OcrRule) => rule.sourceName = value)
          });
          Row() {
            Text('此规则的支出属于信用卡消费')
              .fontSize(13)
              .layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.draft.isCreditCard === true })
              .onChange((value: boolean) => this.updateRule((rule: OcrRule) => rule.isCreditCard = value));
          }
          .width('100%');
          Text('记录模式')
            .fontSize(12)
            .fontColor('#52606D');
          Row({ space: 6 }) {
            this.recordModeButton('视觉行', 'row');
            this.recordModeButton('起始锚点', 'anchor');
          }
          .width('100%');
          if (this.draft.record?.mode === 'anchor') {
            OcrRuleTextField({
              label: '交易起始锚点表达式', value: this.draft.record.anchorPattern ?? '',
              placeholder: '例如：^交易[:：]',
              onChange: (value: string) => this.updateRule((rule: OcrRule) => {
                rule.layoutStrategy = 'generic';
                rule.record = { mode: 'anchor', anchorPattern: value };
              })
            });
          }
          if (this.draft.layoutStrategy === 'icbc-statement' || this.draft.layoutStrategy === 'receipt-list') {
            Text('当前规则仍使用已保存的兼容解析器。选择上方任一模式即可改为通用解析。')
              .fontSize(12)
              .fontColor('#8A4B08');
          }
          OcrRuleTextArea({
            label: '来源匹配表达式（每行一条）', value: this.sourceMatcherText,
            placeholder: '例如：微信支付|微信账单|微信钱包',
            onChange: (value: string) => {
              this.sourceMatcherText = value;
              this.updateRule((rule: OcrRule) => rule.sourceMatchers = this.parseSourceMatchers(value));
            }
          });
          Text('旧版解析器')
            .fontSize(12)
            .fontColor('#52606D');
          Row({ space: 6 }) {
            this.layoutButton('收据兼容', 'receipt-list');
            this.layoutButton('工行兼容', 'icbc-statement');
          }
          .width('100%');
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        Column({ space: 12 }) {
          Text('字段表达式')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          this.patternFields('amountPattern', '金额表达式', this.draft.amountPattern, true);
          this.patternFields('datePattern', '日期表达式', this.draft.datePattern, true);
          OcrRuleTextField({
            label: '日期格式', value: this.draft.dateFormat,
            placeholder: 'auto 或 yyyy年MM月dd日 HH时mm分',
            onChange: (value: string) => this.updateRule((rule: OcrRule) => rule.dateFormat = value)
          });
          this.patternFields('timePattern', '时间表达式（可选）', this.draft.timePattern, false);
          this.patternFields('directionPattern', '方向表达式（可选）', this.draft.directionPattern, false);
          this.patternFields('merchantPattern', '商户表达式（可选）', this.draft.merchantPattern, false);
          this.patternFields('categoryPattern', '分类表达式（可选）', this.draft.categoryPattern, false);
          OcrRuleTextArea({
            label: '可选列范围（每行：字段 left,right，横坐标 0–1）', value: this.columnRangeText,
            placeholder: 'amount 0.65,0.98',
            onChange: (value: string) => {
              this.columnRangeText = value;
              this.updateRule((rule: OcrRule) => rule.columns = this.parseColumns(value));
            }
          });
          OcrRuleTextArea({
            label: '收入关键词（每行或用顿号分隔）', value: this.incomeKeywordText,
            onChange: (value: string) => {
              this.incomeKeywordText = value;
              this.updateRule((rule: OcrRule) => rule.incomeKeywords = this.parseKeywords(value));
            }
          });
          OcrRuleTextArea({
            label: '支出关键词（每行或用顿号分隔）', value: this.expenseKeywordText,
            onChange: (value: string) => {
              this.expenseKeywordText = value;
              this.updateRule((rule: OcrRule) => rule.expenseKeywords = this.parseKeywords(value));
            }
          });
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        Column({ space: 12 }) {
          Button(this.showAdvanced ? '收起高级过滤与分类' : '高级过滤与分类')
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => this.showAdvanced = !this.showAdvanced);
          if (this.showAdvanced) {
            Text('分类与过滤')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            OcrRuleTextField({
              label: '默认分类', value: this.draft.defaultCategory,
              onChange: (value: string) => this.updateRule((rule: OcrRule) => rule.defaultCategory = value)
            });
            OcrRuleTextArea({
              label: '分类映射（每行“正则 => 分类”）', value: this.categoryMappingText,
              placeholder: '例如：^餐饮美食 => 餐饮美食',
              onChange: (value: string) => {
                this.categoryMappingText = value;
                this.updateRule((rule: OcrRule) => rule.categoryMappings = this.parseCategoryMappings(value));
              }
            });
            OcrRuleTextArea({
              label: '失败/取消过滤正则（每行一条）', value: this.failurePatternText,
              onChange: (value: string) => {
                this.failurePatternText = value;
                this.updateRule((rule: OcrRule) => rule.failurePatterns = this.parseExpressions(value));
              }
            });
            OcrRuleTextArea({
              label: '退款识别正则（每行一条）', value: this.refundPatternText,
              onChange: (value: string) => {
                this.refundPatternText = value;
                this.updateRule((rule: OcrRule) => rule.refundPatterns = this.parseExpressions(value));
              }
            });
            OcrRuleTextArea({
              label: '汇总内容过滤正则（每行一条）', value: this.summaryPatternText,
              onChange: (value: string) => {
                this.summaryPatternText = value;
                this.updateRule((rule: OcrRule) => rule.summaryPatterns = this.parseExpressions(value));
              }
            });
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        if (this.validationMessage.length > 0) {
          Text(this.validationMessage)
            .fontSize(13)
            .fontColor('#B42318')
            .width('100%');
        }
        Button('保存规则')
          .width('100%')
          .backgroundColor('#2857C5')
          .fontColor('#FFFFFF')
          .enabled(!this.isSaving && !this.isSubmitting)
          .onClick(() => {
            void this.submitRule();
          });
        if (this.onDelete !== undefined) {
          Button('删除规则')
            .width('100%')
            .backgroundColor('#FCE8E6')
            .fontColor('#B42318')
            .enabled(!this.isSaving && !this.isSubmitting)
            .onClick(() => this.onDelete?.());
        }
      }
      .width('100%')
      .padding(18)
      .alignItems(HorizontalAlign.Start)
      .enabled(!this.isSaving && !this.isSubmitting);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private recordModeButton(label: string, mode: 'row' | 'anchor') {
    Button(label)
      .layoutWeight(1)
      .backgroundColor(this.draft.layoutStrategy === 'generic' && this.draft.record?.mode === mode ?
        '#E9F1FF' : '#F1F3F5')
      .fontColor(this.draft.layoutStrategy === 'generic' && this.draft.record?.mode === mode ? '#2457C5' : '#344563')
      .onClick(() => this.updateRule((rule: OcrRule) => {
        rule.layoutStrategy = 'generic';
        rule.record = mode === 'anchor' ?
          { mode: 'anchor', anchorPattern: rule.record?.anchorPattern ?? '' } : { mode: 'row' };
      }));
  }

  @Builder
  private layoutButton(label: string, strategy: OcrLayoutStrategy) {
    Button(label)
      .layoutWeight(1)
      .backgroundColor(this.draft.layoutStrategy === strategy ? '#E9F1FF' : '#F1F3F5')
      .fontColor(this.draft.layoutStrategy === strategy ? '#2457C5' : '#344563')
      .onClick(() => this.updateRule((rule: OcrRule) => rule.layoutStrategy = strategy));
  }

  @Builder
  private patternFields(field: 'amountPattern' | 'datePattern' | 'timePattern' | 'directionPattern' |
    'merchantPattern' | 'categoryPattern', label: string, pattern: OcrPattern | undefined, required: boolean) {
    Column({ space: 8 }) {
      OcrRuleTextField({
        label: label,
        value: pattern?.pattern ?? '',
        placeholder: required ? '要提取的值放在第一个捕获组；结构括号请用 (?:...)' : '留空表示不使用该字段表达式',
        onChange: (value: string) => this.updatePattern(field, value)
      });
    }
    .width('100%');
  }

  private updatePattern(field: 'amountPattern' | 'datePattern' | 'timePattern' | 'directionPattern' |
    'merchantPattern' | 'categoryPattern', pattern: string): void {
    this.updateRule((rule: OcrRule) => {
      let value: OcrPattern | undefined = undefined;
      if (pattern.trim().length > 0) {
        const nextPattern: OcrPattern = { pattern: pattern, groupIndex: 1 };
        value = nextPattern;
      }
      if (field === 'amountPattern') {
        rule.amountPattern = value ?? { pattern: '', groupIndex: 1 };
      } else if (field === 'datePattern') {
        rule.datePattern = value ?? { pattern: '', groupIndex: 1 };
      } else if (field === 'timePattern') {
        rule.timePattern = value;
      } else if (field === 'directionPattern') {
        rule.directionPattern = value;
      } else if (field === 'merchantPattern') {
        rule.merchantPattern = value;
      } else {
        rule.categoryPattern = value;
      }
    });
  }

  private parseSourceMatchers(value: string): OcrSourceMatcher[] {
    return value.split('\n').map((row: string) => row.trim()).filter((row: string) => row.length > 0)
      .map((row: string): OcrSourceMatcher => ({ pattern: row }));
  }

  private putColumn(columns: OcrColumns, field: string, range: OcrColumnRange): void {
    if (field === 'amount') { columns.amount = range; }
    else if (field === 'date') { columns.date = range; }
    else if (field === 'time') { columns.time = range; }
    else if (field === 'direction') { columns.direction = range; }
    else if (field === 'merchant') { columns.merchant = range; }
    else if (field === 'category') { columns.category = range; }
    else { columns.amount = { left: Number.NaN, right: Number.NaN }; }
  }

  private parseColumns(value: string): OcrColumns | undefined {
    const rows = value.split('\n').map((row: string) => row.trim()).filter((row: string) => row.length > 0);
    if (rows.length === 0) {
      return undefined;
    }
    const columns: OcrColumns = {};
    rows.forEach((row: string) => {
      const match = row.match(/^([a-z]+)\s+([^,]+),\s*(\S+)$/i);
      if (match === null) {
        columns.amount = { left: Number.NaN, right: Number.NaN };
        return;
      }
      this.putColumn(columns, match[1].toLowerCase(), {
        left: Number(match[2]),
        right: Number(match[3])
      });
    });
    return columns;
  }

  private parseCategoryMappings(value: string): OcrCategoryMapping[] {
    return value.split('\n').map((row: string) => row.trim()).filter((row: string) => row.length > 0)
      .map((row: string): OcrCategoryMapping => {
        const separator = row.indexOf('=>');
        let mapping: OcrCategoryMapping;
        if (separator < 0) {
          mapping = { pattern: row, category: '' };
        } else {
          mapping = { pattern: row.slice(0, separator).trim(), category: row.slice(separator + 2).trim() };
        }
        return mapping;
      });
  }

  private parseExpressions(value: string): string[] {
    return value.split('\n').map((pattern: string) => pattern.trim()).filter((pattern: string) => pattern.length > 0);
  }

  private parseKeywords(value: string): string[] {
    return value.split(/[\n、，,]/).map((keyword: string) => keyword.trim()).filter((keyword: string) => keyword.length > 0);
  }

  private syncTextFields(): void {
    this.sourceMatcherText = this.draft.sourceMatchers
      .map((matcher) => matcher.pattern).join('\n');
    this.incomeKeywordText = this.draft.incomeKeywords.join('、');
    this.expenseKeywordText = this.draft.expenseKeywords.join('、');
    this.failurePatternText = this.draft.failurePatterns.join('\n');
    this.refundPatternText = this.draft.refundPatterns.join('\n');
    this.summaryPatternText = this.draft.summaryPatterns.join('\n');
    this.categoryMappingText = this.draft.categoryMappings
      .map((mapping) => mapping.pattern + ' => ' + mapping.category).join('\n');
    const columns: OcrColumns = this.draft.columns ?? {};
    const ranges: string[] = [];
    if (columns.amount !== undefined) { ranges.push('amount ' + columns.amount.left + ',' + columns.amount.right); }
    if (columns.date !== undefined) { ranges.push('date ' + columns.date.left + ',' + columns.date.right); }
    if (columns.time !== undefined) { ranges.push('time ' + columns.time.left + ',' + columns.time.right); }
    if (columns.direction !== undefined) { ranges.push('direction ' + columns.direction.left + ',' + columns.direction.right); }
    if (columns.merchant !== undefined) { ranges.push('merchant ' + columns.merchant.left + ',' + columns.merchant.right); }
    if (columns.category !== undefined) { ranges.push('category ' + columns.category.left + ',' + columns.category.right); }
    this.columnRangeText = ranges.join('\n');
  }

  private updateRule(update: (rule: OcrRule) => void): void {
    const next = this.copyRule(this.draft);
    update(next);
    this.draft = next;
    this.validationMessage = '';
  }

  private copyRule(rule: OcrRule): OcrRule {
    const copyPattern = (pattern: OcrPattern | undefined): OcrPattern | undefined => {
      if (pattern === undefined) {
        return undefined;
      }
      const copy: OcrPattern = { pattern: pattern.pattern, groupIndex: pattern.groupIndex };
      return copy;
    };
    const copyMatcher = (matcher: OcrSourceMatcher): OcrSourceMatcher => {
      const copy: OcrSourceMatcher = { pattern: matcher.pattern, weight: matcher.weight };
      return copy;
    };
    const copyMapping = (mapping: OcrCategoryMapping): OcrCategoryMapping => {
      const copy: OcrCategoryMapping = { pattern: mapping.pattern, category: mapping.category };
      return copy;
    };
    return {
      id: rule.id,
      name: rule.name,
      enabled: rule.enabled,
      isCreditCard: rule.isCreditCard,
      source: rule.source,
      sourceName: rule.sourceName,
      layoutStrategy: rule.layoutStrategy,
      record: rule.record === undefined ? undefined : {
        mode: rule.record.mode,
        anchorPattern: rule.record.anchorPattern
      },
      columns: rule.columns === undefined ? undefined : {
        amount: rule.columns.amount === undefined ? undefined : { left: rule.columns.amount.left, right: rule.columns.amount.right },
        date: rule.columns.date === undefined ? undefined : { left: rule.columns.date.left, right: rule.columns.date.right },
        time: rule.columns.time === undefined ? undefined : { left: rule.columns.time.left, right: rule.columns.time.right },
        direction: rule.columns.direction === undefined ? undefined : { left: rule.columns.direction.left, right: rule.columns.direction.right },
        merchant: rule.columns.merchant === undefined ? undefined : { left: rule.columns.merchant.left, right: rule.columns.merchant.right },
        category: rule.columns.category === undefined ? undefined : { left: rule.columns.category.left, right: rule.columns.category.right }
      },
      sourceMatchers: rule.sourceMatchers.map((matcher: OcrSourceMatcher) => copyMatcher(matcher)),
      minimumScore: rule.minimumScore,
      scoreMargin: rule.scoreMargin,
      amountPattern: copyPattern(rule.amountPattern) as OcrPattern,
      datePattern: copyPattern(rule.datePattern) as OcrPattern,
      timePattern: copyPattern(rule.timePattern),
      directionPattern: copyPattern(rule.directionPattern),
      merchantPattern: copyPattern(rule.merchantPattern),
      categoryPattern: copyPattern(rule.categoryPattern),
      dateFormat: rule.dateFormat,
      incomeKeywords: rule.incomeKeywords.slice(),
      expenseKeywords: rule.expenseKeywords.slice(),
      failurePatterns: rule.failurePatterns.slice(),
      refundPatterns: rule.refundPatterns.slice(),
      summaryPatterns: rule.summaryPatterns.slice(),
      defaultCategory: rule.defaultCategory,
      categoryMappings: rule.categoryMappings.map((mapping: OcrCategoryMapping) => copyMapping(mapping))
    };
  }

  private async submitRule(): Promise<void> {
    if (this.isSaving || this.isSubmitting) {
      return;
    }
    const issue = validateOcrRule(this.draft);
    if (issue !== undefined) {
      this.validationMessage = issue.field + '：' + issue.message;
      return;
    }
    this.isSubmitting = true;
    try {
      this.validationMessage = await this.onSave(this.copyRule(this.draft)) ?? '';
    } catch (error) {
      const failure = error as Error;
      this.validationMessage = failure.message;
    } finally {
      this.isSubmitting = false;
    }
  }
}
