import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { OcrRuleEditor } from '../../components/ocr/OcrRuleEditor';
import { createDefaultOcrRules } from '../../services/ocrRules/OcrRuleEngine';
import type { OcrCategoryMapping, OcrPattern, OcrRule, OcrSourceMatcher } from '../../services/ocrRules/OcrRuleModels';
import { loadOcrRules, saveOcrRules } from '../../services/OcrRuleStore';
import {
  buildOcrRulePrompt,
  parseRuleImport
} from '../../services/ruleImport/RuleImportEngine';
import type { CompactOcrRule, RuleImportPreview } from '../../services/ruleImport/RuleImportModels';
import { createOcrRule, previewOcrRule } from '../../services/ruleImport/OcrRuleImportAdapter';

const OCR_PROMPT_USAGE_EXAMPLE: string = `来源名称：示例钱包
OCR 原文：
示例钱包
日期：2026-10-03
商户：午餐店
支出 金额：1,031.10
分类：餐饮
预期结果：金额 1,031.10，日期 2026-10-03，方向支出，商户午餐店，分类餐饮。`;

const OCR_PROMPT_JSON_EXAMPLE: string = String.raw`{
  "schemaVersion": 1,
  "kind": "ocr",
  "rule": {
    "name": "示例钱包",
    "source": { "id": "example-wallet", "name": "示例钱包", "patterns": ["示例钱包"] },
    "record": { "mode": "row" },
    "fields": {
      "amount": "金额[:：]\\s*([+-]?\\s*[¥￥]?\\s*[\\d,.]+)",
      "date": "日期[:：]\\s*((?:20\\d{2}[-/.年])?\\d{1,2}[-/.月]\\d{1,2}日?)",
      "direction": "(收入|支出)",
      "merchant": "商户[:：]\\s*(.+)",
      "category": "分类[:：]\\s*(.+)"
    },
    "incomeKeywords": ["收入", "收款"],
    "expenseKeywords": ["支出", "付款", "消费"],
    "defaultCategory": "其他"
  },
  "examples": [
    {
      "input": "示例钱包\n日期：2026-10-03\n商户：午餐店\n支出 金额：1,031.10\n分类：餐饮",
      "expected": {
        "amount": "1,031.10",
        "date": "2026-10-03",
        "direction": "expense",
        "merchant": "午餐店",
        "category": "餐饮"
      }
    }
  ]
}`;

@Component
export struct OcrRuleSettingsView {
  @State private rules: OcrRule[] = [];
  @State private isLoading: boolean = true;
  @State private errorMessage: string = '';
  @State private isSavingRules: boolean = false;
  @State private editingRule: OcrRule | undefined = undefined;
  @State private editingIndex: number = -1;
  @State private importJson: string = '';
  @State private importCandidate: OcrRule | undefined = undefined;
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
      OcrRuleEditor({
        rule: this.editingRule,
        isSaving: this.isSavingRules,
        onCancel: () => this.closeEditor(),
        onSave: (rule: OcrRule) => this.saveEditedRule(rule),
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
            .onClick(() => this.onBack());
          Blank();
          Text('OCR 识别规则')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          Blank();
          Blank().width(48);
        }
        .width('100%');

        Text('规则只用于生成待复核草稿。自动识别按来源表达式命中数判断；同一来源的多个规则按列表顺序尝试。')
          .fontSize(13)
          .fontColor('#52606D')
          .width('100%');

        if (!this.isLoading && this.errorMessage.length === 0) {
          Column({ space: 9 }) {
            Text('AI 生成规则')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('复制提示词到你使用的 AI，根据 OCR 原文生成 JSON，再粘贴到这里。本机只校验和试跑规则，不会上传样例。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('使用方法')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#344563');
            Text('1. 复制 OCR 提示词，粘贴到 ChatGPT 等外部 AI。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('2. 补上来源名称、OCR 原文和你确认的金额、日期、方向、商户等结果。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('3. 复制 AI 返回的完整 JSON，粘贴到下方，点“校验并预览”；样例通过后确认保存。')
              .fontSize(12)
              .fontColor('#52606D');
            Text('发给外部 AI 的样例可能含有账务信息，请先遮盖卡号、姓名等隐私。文字预览不验证截图列范围。')
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
              Text(OCR_PROMPT_USAGE_EXAMPLE)
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
              Text(OCR_PROMPT_JSON_EXAMPLE)
                .fontSize(10)
                .fontColor('#52606D')
                .width('100%')
                .padding(10)
                .backgroundColor('#F6F7F9')
                .borderRadius(8)
                .copyOption(CopyOptions.LocalDevice);
            }
            Row({ space: 8 }) {
              Button('复制 OCR 提示词')
                .layoutWeight(1)
                .backgroundColor('#E9F1FF')
                .fontColor('#2457C5')
                .onClick(() => { void this.copyOcrPrompt(); });
              Column() {
                PasteButton()
                  .width('100%')
                  .height(40)
                  .onClick((_event, result) => {
                    if (result !== PasteButtonOnClickResult.SUCCESS) {
                      this.importMessage = '未能授权读取剪贴板，请直接粘贴到输入框。';
                      return;
                    }
                    void this.pasteImportJson();
                  });
              }
              .layoutWeight(1);
            }
            .width('100%');
            TextArea({ text: this.importJson, placeholder: '在这里粘贴 AI 生成的 OCR 规则 JSON' })
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
                Text('结果：' + (preview.actual === undefined ? '没有生成草稿' : JSON.stringify(preview.actual)))
                  .fontSize(11)
                  .fontColor('#52606D');
                if (preview.message !== undefined) {
                  Text(preview.message).fontSize(11).fontColor('#8A4B08');
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .backgroundColor('#F6F7F9')
              .borderRadius(8);
            }, (_preview: RuleImportPreview, index: number) => 'ocr-preview-' + index);
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
            .onClick(() => this.openNewRule());
        }

        if (this.isLoading) {
          Text('正在读取规则…')
            .fontSize(13)
            .fontColor('#52606D');
        } else if (this.rules.length === 0 && this.errorMessage.length === 0) {
          Text('当前没有 OCR 规则。自动识别将把截图留在来源确认流程中。')
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
        ForEach(this.rules, (_rule: OcrRule, index: number) => {
          this.ruleCard(index);
        }, (_rule: OcrRule, index: number) => 'ocr-rule-' + index);
      }
      .width('100%')
      .padding(18)
      .alignItems(HorizontalAlign.Start);
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
      Text('来源：' + (this.rules[index].sourceName ?? this.sourceName(this.rules[index].source)) + ' · ' +
        (this.rules[index].layoutStrategy === 'generic' ?
          this.rules[index].record?.mode === 'anchor' ? '通用锚点' : '通用视觉行' :
          this.rules[index].layoutStrategy === 'receipt-list' ? '旧版收据' : '工行兼容'))
        .fontSize(12)
        .fontColor('#52606D')
        .width('100%');
      Text('来源表达式 ' + this.rules[index].sourceMatchers.length + ' 条')
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

  private sourceName(source: string): string {
    if (source === 'wechat') {
      return '微信';
    }
    if (source === 'alipay') {
      return '支付宝';
    }
    return source;
  }

  private async copyOcrPrompt(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, buildOcrRulePrompt());
      await pasteboard.getSystemPasteboard().setData(data);
      this.promptText = '';
      this.importMessage = 'OCR 提示词已复制。';
    } catch (error) {
      const failure = error as Error;
      this.importMessage = '复制失败：' + failure.message + '。可以手动复制下方提示词内容。';
      this.promptText = buildOcrRulePrompt();
    }
  }

  private async pasteImportJson(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      if (typeof text !== 'string' || text.trim().length === 0) {
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
    const parsed = parseRuleImport(this.importJson, 'ocr');
    if (parsed.valid === false) {
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.importMessage = parsed.issues.slice(0, 4)
        .map((issue) => issue.field + '：' + issue.message).join('；');
      return;
    }
    const rule = createOcrRule(parsed.rule as CompactOcrRule, this.rules);
    this.importCandidate = rule;
    this.importPreviews = previewOcrRule(rule, parsed.examples);
    if (this.importPreviews.some((preview: RuleImportPreview) => !preview.matched)) {
      this.importMessage = '至少一个样例未通过。请调整规则或样例，再重新预览。';
    } else if (parsed.examples.length === 0) {
      this.importMessage = '规则有效，但没有提供样例；请人工检查后再确认保存。';
    } else {
      this.importMessage = '全部样例通过，可确认保存。列范围需用真实截图再核对。';
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

  private async reloadRules(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      this.rules = await loadOcrRules(context);
    } catch (error) {
      const failure = error as Error;
      this.errorMessage = '读取 OCR 识别规则失败：' + failure.message;
    } finally {
      this.isLoading = false;
    }
  }

  private openNewRule(): void {
    const rule = this.copyRule(createDefaultOcrRules()[0]);
    rule.id = 'ocr-rule-' + Date.now().toString(36);
    rule.name = '新 OCR 规则';
    rule.source = 'new-source';
    rule.sourceName = '新来源';
    rule.sourceMatchers = [];
    this.editingIndex = -1;
    this.editingRule = rule;
  }

  private openRule(index: number): void {
    this.editingIndex = index;
    this.editingRule = this.copyRule(this.rules[index]);
  }

  private closeEditor(): void {
    this.editingRule = undefined;
    this.editingIndex = -1;
  }

  private async saveEditedRule(rule: OcrRule): Promise<string | undefined> {
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
    const nextRules = this.rules.filter((_rule: OcrRule, currentIndex: number) => currentIndex !== index);
    const saveError = await this.persistRules(nextRules);
    if (saveError === undefined && this.editingRule !== undefined) {
      this.closeEditor();
    }
  }

  private async persistRules(rules: OcrRule[]): Promise<string | undefined> {
    if (this.isSavingRules) {
      return '正在保存规则，请稍候';
    }
    this.isSavingRules = true;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      await saveOcrRules(context, rules);
      this.rules = rules;
      return undefined;
    } catch (error) {
      const failure = error as Error;
      const message = '保存 OCR 识别规则失败：' + failure.message;
      this.errorMessage = message;
      return message;
    } finally {
      this.isSavingRules = false;
    }
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
}
