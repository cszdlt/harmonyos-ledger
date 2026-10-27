import { RuleImportGuideView } from '../../components/RuleImportGuideView';
import { emptyRuleSample, changeRuleSample, validateRuleSample, buildSamplePrompt, unwrapRuleResponse,
  explainImportIssues, previewOcrSample } from '../../services/ruleImport/RuleImportGuide';
import type { RuleSampleDraft } from '../../services/ruleImport/RuleImportGuide';
import { OcrImporter } from '../../services/OcrImporter';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { OcrRuleEditor } from '../../components/ocr/OcrRuleEditor';
import type { CreditHistoryRule } from '../../services/CreditHistory';
import { createDefaultOcrRules } from '../../services/ocrRules/OcrRuleEngine';
import type { OcrCategoryMapping, OcrPattern, OcrRule, OcrSourceMatcher } from '../../services/ocrRules/OcrRuleModels';
import { loadOcrRules, saveOcrRules } from '../../services/OcrRuleStore';
import { parseRuleImport } from '../../services/ruleImport/RuleImportEngine';
import type { CompactOcrRule, RuleImportPreview } from '../../services/ruleImport/RuleImportModels';
import { createOcrRule } from '../../services/ruleImport/OcrRuleImportAdapter';

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
  @State private sample: RuleSampleDraft = emptyRuleSample();
  @State private showAdvanced: boolean = false;
  @State private isRecognizing: boolean = false;
  onBack: () => void = () => {};
  onOpenCreditHistory: (rule: CreditHistoryRule) => void = (_rule: CreditHistoryRule) => {};

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
          RuleImportGuideView({
            kind: 'ocr', sample: this.sample, response: this.importJson, message: this.importMessage,
            promptText: this.promptText, previews: this.importPreviews,
            busy: this.isSavingRules || this.isRecognizing, advanced: this.showAdvanced,
            candidateSummary: this.importCandidate === undefined ? '' :
              '规则：' + this.importCandidate.name + '；来源：' + this.importCandidate.sourceName +
              '。新规则放在列表顶部，优先用于同来源截图，生成待复核草稿。',
            onFieldChange: (field: string, value: string) => this.changeSample(field, value),
            onChooseSample: () => { void this.chooseScreenshot(); },
            onCopy: () => { void this.copyOcrPrompt(); },
            onResponseChange: (value: string) => this.updateImportResponse(value),
            onPreview: () => this.previewImportedRule(),
            onSave: () => { void this.saveImportedRule(); },
            onToggleAdvanced: () => { this.showAdvanced = !this.showAdvanced; }
          });
        }

        if (this.showAdvanced && !this.isLoading && this.errorMessage.length === 0) {
          Button('手动新增规则')
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
      if (this.rules[index].isCreditCard === true) {
        Text('信用卡消费规则')
          .fontSize(12)
          .fontColor('#2457C5');
        Button('标记历史账目')
          .width('100%')
          .enabled(!this.isSavingRules)
          .backgroundColor('#E9F1FF')
          .fontColor('#2457C5')
          .onClick(() => {
            const rule = this.rules[index];
            this.onOpenCreditHistory({ name: rule.name, source: rule.source });
          });
      }
      if (this.showAdvanced) {
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

  private async chooseScreenshot(): Promise<void> {
    if (this.isRecognizing || this.isSavingRules) { return; }
    this.isRecognizing = true;
    this.importCandidate = undefined;
    this.importPreviews = [];
    this.importMessage = '正在本机识别截图…';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await OcrImporter.chooseAndRecognize(context, 1);
      if (result.pages.length === 0) { this.importMessage = '已取消选择。'; return; }
      const page = result.pages[0];
      if (page.lines.length === 0) { this.importMessage = '截图没有识别到文字，请换一张清晰截图。'; return; }
      this.sample = emptyRuleSample();
      this.sample.input = page.rawText;
      this.sample.ocrPage = page;
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.importJson = '';
      this.promptText = '';
      this.importMessage = '文字已提取，请确认来源和其中一笔交易；预览将使用真实截图坐标。';
    } catch (error) {
      this.importMessage = '截图识别失败：' + (error as Error).message;
    } finally {
      this.isRecognizing = false;
    }
  }

  private changeSample(field: string, value: string): void {
    this.sample = changeRuleSample(this.sample, field, value);
    this.importCandidate = undefined;
    this.importPreviews = [];
    this.importMessage = '';
    this.promptText = '';
  }

  private updateImportResponse(value: string): void {
    this.importJson = value;
    this.importCandidate = undefined;
    this.importPreviews = [];
    this.importMessage = '';
    if (value.trim().length > 0) { this.previewImportedRule(); }
  }

  private async copyOcrPrompt(): Promise<void> {
    const issue = validateRuleSample(this.sample, 'ocr');
    if (issue.length > 0) { this.importMessage = issue; return; }
    const prompt = buildSamplePrompt(this.sample, 'ocr');
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, prompt);
      await pasteboard.getSystemPasteboard().setData(data);
      this.promptText = '';
      this.importMessage = '完整材料已复制，请交给你使用的 AI，再把返回内容粘贴到下方。';
    } catch (_error) {
      this.promptText = prompt;
      this.importMessage = '复制失败，可以长按下方完整材料手动复制。';
    }
  }

  private previewImportedRule(): void {
    this.importCandidate = undefined;
    this.importPreviews = [];
    const issue = validateRuleSample(this.sample, 'ocr');
    if (issue.length > 0) { this.importMessage = issue; return; }
    const parsed = parseRuleImport(unwrapRuleResponse(this.importJson), 'ocr');
    if (parsed.valid === false) {
      this.importMessage = explainImportIssues(parsed.issues);
      return;
    }
    const rule = createOcrRule(parsed.rule as CompactOcrRule, this.rules);
    this.importPreviews = [previewOcrSample(rule, this.sample, this.rules)];
    this.importCandidate = rule;
    this.importMessage = this.importPreviews[0].matched ?
      '已用你的样例核对通过；请检查下方结果后再保存。' : '识别结果需要调整，请查看标红字段。';
  }

  private async saveImportedRule(): Promise<void> {
    if (this.isSavingRules || this.importCandidate === undefined || this.importPreviews.length === 0 || this.importPreviews.some((preview: RuleImportPreview) => !preview.matched)) {
      return;
    }
    const saveError = await this.persistRules([this.importCandidate].concat(this.rules));
    if (saveError === undefined) {
      this.importJson = '';
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.sample = emptyRuleSample();
      this.promptText = '';
      this.importMessage = '规则已保存并启用。';
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
}
