import { NotificationCategoryMapping, NotificationDateStrategy, NotificationRule } from '../../services/notificationRules/NotificationRuleModels';
import { validateNotificationRule } from '../../services/notificationRules/NotificationRuleEngine';

@Component
struct RuleTextField {
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
        .onChange((value: string) => {
          this.onChange(value);
        });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}

@Component
export struct NotificationRuleEditor {
  @Prop rule: NotificationRule = {
    id: '',
    name: '',
    enabled: true,
    sourceKeywords: [],
    bodyPattern: '',
    semanticCaptures: true,
    incomeText: '收入',
    expenseText: '支出',
    dateFormat: '',
    dateStrategy: 'delivery-time',
    defaultMerchant: '',
    defaultCategory: '其他',
    categoryMappings: [],
    merchantPrefixToStrip: '',
    noteTemplate: ''
  };
  @State private draft: NotificationRule = {
    id: '',
    name: '',
    enabled: true,
    sourceKeywords: [],
    bodyPattern: '',
    semanticCaptures: true,
    incomeText: '收入',
    expenseText: '支出',
    dateFormat: '',
    dateStrategy: 'delivery-time',
    defaultMerchant: '',
    defaultCategory: '其他',
    categoryMappings: [],
    merchantPrefixToStrip: '',
    noteTemplate: ''
  };
  @State private validationMessage: string = '';
  @State private sourceKeywordText: string = '';
  @State private isSubmitting: boolean = false;
  @Prop isSaving: boolean = false;
  onCancel: () => void = () => {};
  onSave: (rule: NotificationRule) => Promise<string | undefined> =
    (_rule: NotificationRule) => Promise.resolve(undefined);
  onDelete: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.draft = this.copyRule(this.rule);
    this.sourceKeywordText = this.rule.sourceKeywords.join('，');
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Button('返回')
            .backgroundColor('#FFFFFF')
            .fontColor('#344563')
            .onClick(() => {
              this.onCancel();
            });
          Blank();
          Text(this.onDelete === undefined ? '新增识别规则' : '编辑识别规则')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          Blank();
          Blank().width(48);
        }
        .width('100%');

        Text('来源关键词、正文正则和方向词共同决定规则。新规则使用 amount、direction 等命名字段；旧规则仍保留数字捕获兼容编辑。')
          .fontSize(12)
          .fontColor('#52606D')
          .width('100%');

        Column({ space: 12 }) {
          RuleTextField({
            label: '规则名称',
            value: this.draft.name,
            onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.name = value)
          });
          RuleTextField({
            label: '来源关键词（逗号分隔）',
            value: this.sourceKeywordText,
            placeholder: '例如：银行名称，bundle 名称片段',
            onChange: (value: string) => {
              this.sourceKeywordText = value;
              const keywords = value.split(/[，,\n]/).map((keyword: string) => keyword.trim()).filter((keyword: string) => keyword.length > 0);
              this.updateRule((draft: NotificationRule) => draft.sourceKeywords = keywords);
            }
          });
          Row() {
            Text('此规则的支出属于信用卡消费')
              .fontSize(13)
              .layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.draft.isCreditCard === true })
              .onChange((value: boolean) => this.updateRule((draft: NotificationRule) => draft.isCreditCard = value));
          }
          .width('100%');
          RuleTextField({
            label: '通知正文正则',
            value: this.draft.bodyPattern,
            placeholder: this.draft.semanticCaptures ?
              '(?<direction>收入|支出).*?(?<amount>[\\d,.]+)元' : '兼容旧规则的正文正则',
            onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.bodyPattern = value)
          });
          Button(this.draft.semanticCaptures ? '切换到数字捕获兼容' : '改用语义命名捕获')
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => this.updateRule((draft: NotificationRule) =>
              draft.semanticCaptures = !draft.semanticCaptures));
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        Column({ space: 12 }) {
          Text(this.draft.semanticCaptures ? '交易语义字段' : '旧版数字捕获组')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          if (this.draft.semanticCaptures) {
            Text('正文正则必须包含 (?<amount>...) 和 (?<direction>...)。可选字段使用 date、merchant、category 命名。')
              .fontSize(12)
              .fontColor('#52606D')
              .width('100%');
          } else {
            RuleTextField({
              label: '金额组编号（必填）',
              value: this.groupText(this.draft.amountGroup),
              onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.amountGroup = Number(value))
            });
            RuleTextField({
              label: '方向组编号（必填）',
              value: this.groupText(this.draft.directionGroup),
              onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.directionGroup = Number(value))
            });
          }
          Column({ space: 8 }) {
            RuleTextField({
              label: '收入通知关键词（多个用 | 分隔）',
              value: this.draft.incomeText,
              onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.incomeText = value)
            });
            RuleTextField({
              label: '支出通知关键词（多个用 | 分隔）',
              value: this.draft.expenseText,
              onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.expenseText = value)
            });
          }
          .width('100%');
          Text('方向字段需与对应列表中的某个关键词完全一致。')
            .fontSize(12)
            .fontColor('#52606D')
            .width('100%');
          if (this.draft.dateStrategy !== 'delivery-time') {
            if (!this.draft.semanticCaptures) {
              RuleTextField({
                label: '日期组编号',
                value: this.draft.dateGroup === undefined ? '' : String(this.draft.dateGroup),
                onChange: (value: string) => this.updateDateGroup(value)
              });
            } else {
              Text('正文正则需包含命名捕获 date。')
                .fontSize(12)
                .fontColor('#52606D');
            }
            RuleTextField({
              label: '日期格式',
              value: this.draft.dateFormat,
              placeholder: '例如：M月d日 HH:mm 或 yyyy-MM-dd HH:mm',
              onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.dateFormat = value)
            });
          }
          Text('日期策略')
            .fontSize(12)
            .fontColor('#52606D');
          Row({ space: 6 }) {
            this.dateStrategyButton('完整日期', 'format');
            this.dateStrategyButton('推断年份', 'infer-year');
            this.dateStrategyButton('投递时间', 'delivery-time');
          }
          .width('100%');
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        Column({ space: 12 }) {
          Text('商户与分类')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          RuleTextField({
            label: '默认商户',
            value: this.draft.defaultMerchant,
            onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.defaultMerchant = value)
          });
          if (!this.draft.semanticCaptures) {
            RuleTextField({
              label: '商户捕获组（可选）',
              value: this.groupText(this.draft.merchantGroup),
              onChange: (value: string) => this.updateOptionalGroup(value, 'merchant')
            });
          }
          RuleTextField({
            label: '移除商户前缀',
            value: this.draft.merchantPrefixToStrip,
            onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.merchantPrefixToStrip = value)
          });
          RuleTextField({
            label: '默认分类',
            value: this.draft.defaultCategory,
            onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.defaultCategory = value)
          });
          if (!this.draft.semanticCaptures) {
            RuleTextField({
              label: '分类捕获组（可选）',
              value: this.groupText(this.draft.categoryGroup),
              onChange: (value: string) => this.updateOptionalGroup(value, 'category')
            });
          }
          Text('有序分类映射：先匹配的规则优先；没有命中时使用默认分类。')
            .fontSize(12)
            .fontColor('#52606D');
          ForEach(this.draft.categoryMappings, (_mapping: NotificationCategoryMapping, index: number) => {
            this.categoryMappingRow(index);
          }, (_mapping: NotificationCategoryMapping, index: number) => 'category-' + index);
          Button('添加分类映射')
            .width('100%')
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => {
              this.updateRule((draft: NotificationRule) => draft.categoryMappings.push({ text: '', matchMode: 'includes', category: '' }));
            });
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        Column({ space: 12 }) {
          RuleTextField({
            label: this.draft.semanticCaptures ? '备注' : '备注模板（可引用 {{1}}、{{2}} 等捕获组）',
            value: this.draft.noteTemplate,
            placeholder: this.draft.semanticCaptures ? '语义规则不引用数字捕获组' : '例如：尾号{{1}}账户通知',
            onChange: (value: string) => this.updateRule((draft: NotificationRule) => draft.noteTemplate = value)
          });
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
            .onClick(() => {
              this.onDelete?.();
            });
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
  private dateStrategyButton(label: string, strategy: NotificationDateStrategy) {
    Button(label)
      .layoutWeight(1)
      .backgroundColor(this.draft.dateStrategy === strategy ? '#E9F1FF' : '#F1F3F5')
      .fontColor(this.draft.dateStrategy === strategy ? '#2457C5' : '#344563')
      .onClick(() => {
        this.updateRule((draft: NotificationRule) => draft.dateStrategy = strategy);
      });
  }

  @Builder
  private categoryMappingRow(index: number) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.draft.categoryMappings[index].text, placeholder: '匹配文字' })
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#F6F7F9')
          .borderRadius(8)
          .onChange((value: string) => {
            this.updateRule((draft: NotificationRule) => draft.categoryMappings[index].text = value);
          });
        Button(this.draft.categoryMappings[index].matchMode === 'startsWith' ? '开头' : '包含')
          .backgroundColor('#E9F1FF')
          .fontColor('#2457C5')
          .onClick(() => {
            this.updateRule((draft: NotificationRule) => draft.categoryMappings[index].matchMode =
              this.draft.categoryMappings[index].matchMode === 'startsWith' ? 'includes' : 'startsWith');
          });
      }
      .width('100%');
      Row({ space: 6 }) {
        TextInput({ text: this.draft.categoryMappings[index].category, placeholder: '分类名称' })
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#F6F7F9')
          .borderRadius(8)
          .onChange((value: string) => {
            this.updateRule((draft: NotificationRule) => draft.categoryMappings[index].category = value);
          });
        Button('↑')
          .backgroundColor('#F1F3F5')
          .fontColor('#344563')
          .onClick(() => this.moveMapping(index, -1));
        Button('↓')
          .backgroundColor('#F1F3F5')
          .fontColor('#344563')
          .onClick(() => this.moveMapping(index, 1));
        Button('删')
          .backgroundColor('#FCE8E6')
          .fontColor('#B42318')
          .onClick(() => this.removeMapping(index));
      }
      .width('100%');
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#F9FAFB')
    .borderRadius(10);
  }

  private copyRule(rule: NotificationRule): NotificationRule {
    const categoryMappings: NotificationCategoryMapping[] = [];
    rule.categoryMappings.forEach((mapping: NotificationCategoryMapping) => {
      const copiedMapping: NotificationCategoryMapping = {
        text: mapping.text,
        matchMode: mapping.matchMode,
        category: mapping.category
      };
      categoryMappings.push(copiedMapping);
    });
    return {
      id: rule.id,
      name: rule.name,
      enabled: rule.enabled,
      isCreditCard: rule.isCreditCard,
      sourceKeywords: rule.sourceKeywords.slice(),
      bodyPattern: rule.bodyPattern,
      semanticCaptures: rule.semanticCaptures,
      amountGroup: rule.amountGroup,
      directionGroup: rule.directionGroup,
      incomeText: rule.incomeText,
      expenseText: rule.expenseText,
      dateGroup: rule.dateGroup,
      dateFormat: rule.dateFormat,
      dateStrategy: rule.dateStrategy,
      merchantGroup: rule.merchantGroup,
      categoryGroup: rule.categoryGroup,
      defaultMerchant: rule.defaultMerchant,
      defaultCategory: rule.defaultCategory,
      categoryMappings: categoryMappings,
      merchantPrefixToStrip: rule.merchantPrefixToStrip,
      noteTemplate: rule.noteTemplate,
      entrySource: rule.entrySource
    };
  }

  private updateRule(update: (draft: NotificationRule) => void): void {
    const next = this.copyRule(this.draft);
    update(next);
    this.draft = next;
    this.validationMessage = '';
  }

  private updateDateGroup(value: string): void {
    this.updateRule((draft: NotificationRule) => draft.dateGroup = this.optionalGroup(value));
  }

  private updateOptionalGroup(value: string, field: 'merchant' | 'category'): void {
    const group = this.optionalGroup(value);
    if (field === 'merchant') {
      this.updateRule((draft: NotificationRule) => draft.merchantGroup = group);
    } else {
      this.updateRule((draft: NotificationRule) => draft.categoryGroup = group);
    }
  }

  private moveMapping(index: number, offset: number): void {
    const target = index + offset;
    if (target < 0 || target >= this.draft.categoryMappings.length) {
      return;
    }
    const mappings = this.draft.categoryMappings.slice();
    const moving = mappings[index];
    mappings[index] = mappings[target];
    mappings[target] = moving;
    this.updateRule((draft: NotificationRule) => draft.categoryMappings = mappings);
  }

  private removeMapping(index: number): void {
    const mappings = this.draft.categoryMappings.filter((_mapping: NotificationCategoryMapping, currentIndex: number) => currentIndex !== index);
    this.updateRule((draft: NotificationRule) => draft.categoryMappings = mappings);
  }

  private groupText(group: number | undefined): string {
    return group === undefined ? '' : String(group);
  }

  private optionalGroup(value: string): number | undefined {
    return value.trim().length === 0 ? undefined : Number(value);
  }

  private async submitRule(): Promise<void> {
    if (this.isSaving || this.isSubmitting) {
      return;
    }
    const issue = validateNotificationRule(this.draft);
    if (issue !== undefined) {
      this.validationMessage = issue.message;
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
