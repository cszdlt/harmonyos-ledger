import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NotificationRuleEditor } from '../../components/notifications/NotificationRuleEditor';
import { NotificationCategoryMapping, NotificationRule } from '../../services/notificationRules/NotificationRuleModels';
import { loadNotificationRules, saveNotificationRules } from '../../services/NotificationRuleStore';
import { buildNotificationRulePrompt, parseRuleImport } from '../../services/ruleImport/RuleImportEngine';
import type { CompactNotificationRule, RuleImportPreview } from '../../services/ruleImport/RuleImportModels';
import {
  createNotificationRule,
  previewNotificationRule
} from '../../services/ruleImport/NotificationRuleImportAdapter';

const NOTIFICATION_PROMPT_USAGE_EXAMPLE: string = `通知来源：支付宝
标题：交易提醒
正文：你有一笔26.90元的支出，点击领取3个支付宝积分。
预期结果：金额 26.90，方向支出；正文没有商户，使用默认商户“支付宝”；时间使用通知到达时间。`;

const NOTIFICATION_PROMPT_JSON_EXAMPLE: string = String.raw`{
  "schemaVersion": 1,
  "kind": "notification",
  "rule": {
    "name": "支付宝金额提醒",
    "sourceKeywords": ["支付宝"],
    "bodyPattern": "你有一笔(?<amount>[¥￥]?[\\d,.]+)元的(?<direction>支出|收入)",
    "incomeText": "收入",
    "expenseText": "支出",
    "dateFormat": "",
    "dateStrategy": "delivery-time",
    "defaultMerchant": "支付宝",
    "defaultCategory": "其他",
    "entrySource": "支付宝"
  },
  "examples": [
    {
      "input": "你有一笔26.90元的支出，点击领取3个支付宝积分。",
      "expected": { "amount": "26.90", "direction": "expense", "merchant": "支付宝" }
    }
  ]
}`;

@Component
export struct NotificationRuleSettingsView {
  @State private rules: NotificationRule[] = [];
  @State private isLoading: boolean = true;
  @State private errorMessage: string = '';
  @State private isSavingRules: boolean = false;
  @State private editingRule: NotificationRule | undefined = undefined;
  @State private editingIndex: number = -1;
  @State private importJson: string = '';
  @State private importCandidate: NotificationRule | undefined = undefined;
  @State private importPreviews: RuleImportPreview[] = [];
  @State private importMessage: string = '';
  @State private promptText: string = '';
  @State private showPromptExample: boolean = false;
  onBack: () => void = () => {};

  aboutToAppear(): void {
    void this.reloadRules();
  }

  build() {
    if (this.editingRule !== undefined) {
      NotificationRuleEditor({
        rule: this.editingRule,
        isSaving: this.isSavingRules,
        onCancel: () => this.closeEditor(),
        onSave: (rule: NotificationRule) => this.saveEditedRule(rule),
        onDelete: this.editingIndex < 0 ? undefined : () => {
          void this.deleteRule(this.editingIndex);
        }
      });
    } else {
      this.rulesPage();
    }
  }

  @Builder
  private rulesPage() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Button('返回')
            .backgroundColor('#FFFFFF')
            .fontColor('#344563')
            .onClick(() => {
              this.onBack();
            });
          Blank();
          Text('通知识别规则')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          Blank();
          Blank().width(48);
        }
        .width('100%');

        Text('按列表顺序匹配通知。默认规则包含工商银行、中信银行、支付宝和微信支付；删除或清空后不会自动恢复。')
          .fontSize(13)
          .fontColor('#52606D')
          .width('100%');

        if (!this.isLoading && this.errorMessage.length === 0) {
          Column({ space: 9 }) {
            Text('AI 生成规则')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('复制提示词给外部 AI，根据通知来源和原文生成规则。应用只在本机校验和试跑，不上传通知内容。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('使用方法')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#344563');
            Text('1. 复制通知提示词，粘贴到 ChatGPT 等外部 AI。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('2. 补上通知来源、标题、正文和你确认的金额、方向、商户等结果。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('3. 复制 AI 返回的完整 JSON，粘贴到下方，点“校验并预览”；样例通过后确认保存。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('发给外部 AI 的通知原文可能含有个人或金融信息，请先遮盖敏感内容。')
              .fontSize(12)
              .fontColor('#8A4B08');
            Button(this.showPromptExample ? '收起示例' : '查看使用示例')
              .backgroundColor('#F1F3F5')
              .fontColor('#344563')
              .onClick(() => { this.showPromptExample = !this.showPromptExample; });
            if (this.showPromptExample) {
              Text('把这段材料接在提示词后发给 AI')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor('#344563');
              Text(NOTIFICATION_PROMPT_USAGE_EXAMPLE)
                .fontSize(11)
                .fontColor('#52606D')
                .width('100%')
                .padding(10)
                .backgroundColor('#F6F7F9')
                .borderRadius(8)
                .copyOption(CopyOptions.LocalDevice);
              Text('AI 返回的 JSON 格式示例')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor('#344563');
              Text(NOTIFICATION_PROMPT_JSON_EXAMPLE)
                .fontSize(10)
                .fontColor('#52606D')
                .width('100%')
                .padding(10)
                .backgroundColor('#F6F7F9')
                .borderRadius(8)
                .copyOption(CopyOptions.LocalDevice);
            }
            Row({ space: 8 }) {
              Button('复制通知提示词')
                .layoutWeight(1)
                .backgroundColor('#E9F1FF')
                .fontColor('#2457C5')
                .onClick(() => { void this.copyNotificationPrompt(); });
              Button('粘贴剪贴板')
                .layoutWeight(1)
                .backgroundColor('#F1F3F5')
                .fontColor('#344563')
                .onClick(() => { void this.pasteImportJson(); });
            }
            .width('100%');
            TextArea({ text: this.importJson, placeholder: '在这里粘贴 AI 生成的通知规则 JSON' })
              .width('100%')
              .height(150)
              .fontSize(12)
              .backgroundColor('#F6F7F9')
              .onChange((value: string) => {
                this.importJson = value;
                this.importCandidate = undefined;
                this.importPreviews = [];
                this.importMessage = '';
              });
            Button('校验并预览')
              .width('100%')
              .backgroundColor('#2857C5')
              .fontColor('#FFFFFF')
              .enabled(!this.isSavingRules)
              .onClick(() => this.previewImportedRule());
            if (this.importMessage.length > 0) {
              Text(this.importMessage)
                .fontSize(12)
                .fontColor(this.importCandidate === undefined ? '#B42318' : '#52606D');
            }
            if (this.promptText.length > 0) {
              Text('提示词文本，可长按选择并复制')
                .fontSize(12)
                .fontColor('#52606D');
              TextArea({ text: this.promptText })
                .width('100%')
                .height(220)
                .fontSize(11)
                .backgroundColor('#F6F7F9');
            }
            ForEach(this.importPreviews, (preview: RuleImportPreview, index: number) => {
              Column({ space: 4 }) {
                Text((preview.matched ? '样例 ' : '样例未通过 ') + (index + 1))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(preview.matched ? '#16845B' : '#B42318');
                Text('预期：' + JSON.stringify(preview.expected))
                  .fontSize(11)
                  .fontColor('#52606D');
                Text('结果：' + (preview.actual === undefined ? '没有生成结果' : JSON.stringify(preview.actual)))
                  .fontSize(11)
                  .fontColor('#52606D');
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .backgroundColor('#F6F7F9')
              .borderRadius(8);
            }, (_preview: RuleImportPreview, index: number) => 'notification-preview-' + index);
            if (this.importCandidate !== undefined) {
              Button('确认保存导入规则')
                .width('100%')
                .backgroundColor('#16845B')
                .fontColor('#FFFFFF')
                .enabled(!this.isSavingRules)
                .onClick(() => { void this.saveImportedRule(); });
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);
        }

        if (!this.isLoading && this.errorMessage.length === 0) {
          Button('新增规则')
            .width('100%')
            .backgroundColor('#2857C5')
            .fontColor('#FFFFFF')
            .enabled(!this.isSavingRules)
            .onClick(() => {
              this.openNewRule();
            });
        }

        if (this.isLoading) {
          Text('正在读取规则…')
            .fontSize(13)
            .fontColor('#52606D');
        } else if (this.rules.length === 0 && this.errorMessage.length === 0) {
          Text('当前没有识别规则。新增规则后，匹配的通知才会自动入账。')
            .fontSize(13)
            .fontColor('#52606D');
        }
        if (this.errorMessage.length > 0) {
          Column({ space: 8 }) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor('#B42318');
            Button('重新读取')
              .backgroundColor('#F1F3F5')
              .fontColor('#344563')
              .enabled(!this.isSavingRules)
              .onClick(() => {
                void this.reloadRules();
              });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        ForEach(this.rules, (rule: NotificationRule, index: number) => {
          this.ruleCard(index);
        }, (_rule: NotificationRule, index: number) => 'rule-' + index);
      }
      .width('100%')
      .padding(18)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ruleCard(index: number) {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 4 }) {
          Text((index + 1) + '. ' + this.rules[index].name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          Text(this.rules[index].enabled ? '已启用' : '已停用')
            .fontSize(12)
            .fontColor(this.rules[index].enabled ? '#16845B' : '#7B8794');
        }
        .alignItems(HorizontalAlign.Start);
        Blank();
        Button(this.rules[index].enabled ? '停用' : '启用')
          .backgroundColor(this.rules[index].enabled ? '#F1F3F5' : '#E9F1FF')
          .fontColor(this.rules[index].enabled ? '#344563' : '#2457C5')
          .enabled(!this.isSavingRules)
          .onClick(() => {
            void this.setRuleEnabled(index, !this.rules[index].enabled);
          });
      }
      .width('100%');
      Text('来源：' + this.rules[index].sourceKeywords.join('、'))
        .fontSize(12)
        .fontColor('#52606D')
        .width('100%');
      Row({ space: 8 }) {
        Button('编辑')
          .layoutWeight(1)
          .backgroundColor('#E9F1FF')
          .fontColor('#2457C5')
          .enabled(!this.isSavingRules)
          .onClick(() => this.openRule(index));
        Button('上移')
          .layoutWeight(1)
          .backgroundColor('#F1F3F5')
          .fontColor('#344563')
          .enabled(!this.isSavingRules && index > 0)
          .onClick(() => {
            void this.moveRule(index, -1);
          });
        Button('下移')
          .layoutWeight(1)
          .backgroundColor('#F1F3F5')
          .fontColor('#344563')
          .enabled(!this.isSavingRules && index < this.rules.length - 1)
          .onClick(() => {
            void this.moveRule(index, 1);
          });
        Button('删除')
          .layoutWeight(1)
          .backgroundColor('#FCE8E6')
          .fontColor('#B42318')
          .enabled(!this.isSavingRules)
          .onClick(() => {
            void this.deleteRule(index);
          });
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
  }

  private async reloadRules(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      this.rules = await loadNotificationRules(context);
    } catch (error) {
      const failure = error as Error;
      this.errorMessage = '读取通知规则失败：' + failure.message;
    } finally {
      this.isLoading = false;
    }
  }

  private async copyNotificationPrompt(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, buildNotificationRulePrompt());
      await pasteboard.getSystemPasteboard().setData(data);
      this.promptText = '';
      this.importMessage = '通知提示词已复制。';
    } catch (error) {
      const failure = error as Error;
      this.importMessage = '复制失败：' + failure.message + '。请从下方文本手动复制提示词。';
      this.promptText = buildNotificationRulePrompt();
    }
  }

  private async pasteImportJson(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      if (text.length === 0) {
        this.importMessage = '剪贴板没有纯文本，请直接粘贴到输入框。';
        return;
      }
      this.importJson = text;
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.importMessage = '已粘贴规则 JSON，请校验并预览。';
    } catch (error) {
      const failure = error as Error;
      this.importMessage = '读取剪贴板失败：' + failure.message + '。可以直接在输入框中粘贴。';
    }
  }

  private previewImportedRule(): void {
    const parsed = parseRuleImport(this.importJson, 'notification');
    if (parsed.valid === false) {
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.importMessage = parsed.issues
        .map((issue) => issue.field + '：' + issue.message).join('；');
      return;
    }
    const rule = createNotificationRule(parsed.rule as CompactNotificationRule, this.rules);
    this.importCandidate = rule;
    this.importPreviews = previewNotificationRule(rule, parsed.examples);
    if (this.importPreviews.some((preview: RuleImportPreview) => !preview.matched)) {
      this.importMessage = '至少一个样例未通过。请调整规则或样例，再重新预览。';
    } else if (parsed.examples.length === 0) {
      this.importMessage = '规则有效，但没有提供样例；请人工检查后再确认保存。';
    } else {
      this.importMessage = '全部样例通过，可确认保存。';
    }
  }

  private async saveImportedRule(): Promise<void> {
    if (this.importCandidate === undefined || this.importPreviews.some((preview: RuleImportPreview) => !preview.matched)) {
      return;
    }
    const saveError = await this.persistRules(this.rules.concat([this.importCandidate]));
    if (saveError === undefined) {
      this.importJson = '';
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.importMessage = '规则已保存。';
    }
  }

  private openNewRule(): void {
    this.editingIndex = -1;
    this.editingRule = {
      id: 'rule-' + Date.now().toString(36),
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
  }

  private openRule(index: number): void {
    this.editingIndex = index;
    this.editingRule = this.copyRule(this.rules[index]);
  }

  private closeEditor(): void {
    this.editingRule = undefined;
    this.editingIndex = -1;
  }

  private async saveEditedRule(rule: NotificationRule): Promise<string | undefined> {
    const nextRules = this.rules.slice();
    if (this.editingIndex < 0) {
      nextRules.push(rule);
    } else {
      nextRules[this.editingIndex] = rule;
    }
    const saveError = await this.persistRules(nextRules);
    if (saveError !== undefined) {
      return saveError;
    }
    this.closeEditor();
    return undefined;
  }

  private async setRuleEnabled(index: number, enabled: boolean): Promise<void> {
    const nextRules = this.rules.slice();
    const changed = this.copyRule(nextRules[index]);
    changed.enabled = enabled;
    nextRules[index] = changed;
    await this.persistRules(nextRules);
  }

  private async moveRule(index: number, offset: number): Promise<void> {
    const target = index + offset;
    if (target < 0 || target >= this.rules.length) {
      return;
    }
    const nextRules = this.rules.slice();
    const moving = nextRules[index];
    nextRules[index] = nextRules[target];
    nextRules[target] = moving;
    await this.persistRules(nextRules);
  }

  private async deleteRule(index: number): Promise<void> {
    const nextRules = this.rules.filter((_rule: NotificationRule, currentIndex: number) => currentIndex !== index);
    const saveError = await this.persistRules(nextRules);
    if (saveError === undefined && this.editingRule !== undefined) {
      this.closeEditor();
    }
  }

  private async persistRules(rules: NotificationRule[]): Promise<string | undefined> {
    if (this.isSavingRules) {
      return '正在保存规则，请稍候';
    }
    this.isSavingRules = true;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      await saveNotificationRules(context, rules);
      this.rules = rules;
      return undefined;
    } catch (error) {
      const failure = error as Error;
      const message = '保存通知规则失败：' + failure.message;
      this.errorMessage = message;
      return message;
    } finally {
      this.isSavingRules = false;
    }
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
}
