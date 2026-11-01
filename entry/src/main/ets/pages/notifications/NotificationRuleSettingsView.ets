import { RuleImportGuideView } from '../../components/RuleImportGuideView';
import { emptyRuleSample, changeRuleSample, unwrapRuleResponse,
  explainImportIssues, sampleFromNotification } from '../../services/ruleImport/RuleImportGuide';
import type { RuleSampleDraft } from '../../services/ruleImport/RuleImportGuide';
import type { NotificationArchiveEntry } from '../../model/NotificationArchiveModels';
import type { NotificationArchiveCursor, NotificationSource } from '../../model/NotificationArchiveModels';
import { NotificationArchiveRepository } from '../../data/NotificationArchiveRepository';
import { NotificationRuleSamplePicker } from '../../components/notifications/NotificationRuleSamplePicker';
import { buildNotificationSamplesPrompt, validateNotificationSamples, previewNotificationSamples,
  notificationSampleStatus } from '../../services/ruleImport/NotificationRuleSamples';
import type { NotificationRuleSample } from '../../services/ruleImport/NotificationRuleSamples';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NotificationRuleEditor } from '../../components/notifications/NotificationRuleEditor';
import type { CreditHistoryRule } from '../../services/CreditHistory';
import { NotificationCategoryMapping, NotificationRule } from '../../services/notificationRules/NotificationRuleModels';
import { loadNotificationRules, saveNotificationRules } from '../../services/NotificationRuleStore';
import { parseRuleImport } from '../../services/ruleImport/RuleImportEngine';
import type { CompactNotificationRule, RuleImportPreview } from '../../services/ruleImport/RuleImportModels';
import {
  createNotificationRule
} from '../../services/ruleImport/NotificationRuleImportAdapter';
import { NotificationRebookingPage } from './NotificationRebookingPage';

@Component
export struct NotificationRuleSettingsView {
  @State private rules: NotificationRule[] = [];
  @State private isLoading: boolean = true;
  @State private errorMessage: string = '';
  @State private isSavingRules: boolean = false;
  @State private editingRule: NotificationRule | undefined = undefined;
  @State private rebookingRule: NotificationRule | undefined = undefined;
  @State private editingIndex: number = -1;
  @State private importJson: string = '';
  @State private importCandidate: NotificationRule | undefined = undefined;
  @State private importPreviews: RuleImportPreview[] = [];
  @State private importMessage: string = '';
  @State private promptText: string = '';
  @State private sample: RuleSampleDraft = emptyRuleSample();
  @State private showAdvanced: boolean = false;
  @State private activeRuleSection: string = 'setup';
  @State private selectedSamples: NotificationRuleSample[] = [];
  @State private activeSampleIndex: number = 0;
  @State private pickerOpen: boolean = false;
  @State private pickerSources: NotificationSource[] = [];
  @State private pickerEntries: NotificationArchiveEntry[] = [];
  @State private pickerBundle: string = '';
  @State private pickerLoading: boolean = false;
  @State private pickerMessage: string = '';
  private sampleRepository: NotificationArchiveRepository = new NotificationArchiveRepository();
  private pickerCursor: NotificationArchiveCursor | undefined = undefined;
  private pickerQueryRevision: number = 0;
  @Prop initialSample: NotificationArchiveEntry | undefined = undefined;
  onChooseNotification: () => void = () => {};
  onBack: () => void = () => {};
  onOpenCreditHistory: (rule: CreditHistoryRule) => void = (_rule: CreditHistoryRule) => {};

  aboutToAppear(): void {
    if (this.initialSample !== undefined) {
      this.sample = sampleFromNotification(this.initialSample);
      this.selectedSamples = [{ id: this.initialSample.id, draft: this.sample }];
    }
    void this.reloadRules();
  }

  build() {
    if (this.pickerOpen) {
      NotificationRuleSamplePicker({
        sources: this.pickerSources, entries: this.pickerEntries, bundleName: this.pickerBundle,
        selectedIds: this.selectedSamples.map((item: NotificationRuleSample) => item.id),
        loading: this.pickerLoading, hasMore: this.pickerCursor !== undefined, message: this.pickerMessage,
        onSelectSource: (bundleName: string) => this.selectSampleSource(bundleName),
        onToggle: (entry: NotificationArchiveEntry) => this.toggleSample(entry),
        onLoadMore: () => { void this.loadPickerEntries(true); },
        onDone: () => {
          this.pickerOpen = false;
          this.pickerQueryRevision++;
          this.pickerLoading = false;
        }
      });
    } else if (this.editingRule !== undefined) {
      NotificationRuleEditor({
        rule: this.editingRule,
        isSaving: this.isSavingRules,
        onCancel: () => this.closeEditor(),
        onSave: (rule: NotificationRule) => this.saveEditedRule(rule),
        onDelete: this.editingIndex < 0 ? undefined : () => {
          void this.deleteRule(this.editingIndex);
        }
      });
    } else if (this.rebookingRule !== undefined) {
      NotificationRebookingPage({
        rule: this.rebookingRule,
        onBack: () => { this.rebookingRule = undefined; }
      });
    } else {
      this.rulesPage();
    }
  }

  @Builder
  private rulesPage() {
    Stack({ alignContent: Alignment.Bottom }) {
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

          Row({ space: 8 }) {
            Button('新增规则')
              .layoutWeight(1)
              .backgroundColor(this.activeRuleSection === 'setup' ? '#2857C5' : '#F1F3F5')
              .fontColor(this.activeRuleSection === 'setup' ? '#FFFFFF' : '#344563')
              .onClick(() => this.selectRuleSection('setup'));
            Button('已有规则（' + this.rules.length + '）')
              .layoutWeight(1)
              .backgroundColor(this.activeRuleSection === 'rules' ? '#2857C5' : '#F1F3F5')
              .fontColor(this.activeRuleSection === 'rules' ? '#FFFFFF' : '#344563')
              .onClick(() => this.selectRuleSection('rules'));
          }
          .width('100%');

          if (this.activeRuleSection === 'setup') {
            this.ruleSetupSection();
          } else {
            this.savedRulesSection();
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 18,
          bottom: this.activeRuleSection === 'setup' && this.selectedSamples.length > 0 ? 160 : 24 })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .width('100%')
      .height('100%');
      if (this.activeRuleSection === 'setup' && this.selectedSamples.length > 0 &&
        !this.isLoading && this.errorMessage.length === 0) {
        this.sampleSelectionBar();
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ruleSetupSection() {
    if (!this.isLoading && this.errorMessage.length === 0) {
      ForEach([this.selectedSamples.length > 0 ? 'archive-' + this.selectedSamples[this.activeSampleIndex].id : 'manual'], (_key: string) => {
        RuleImportGuideView({
          kind: 'notification', sample: this.sample, response: this.importJson, message: this.importMessage,
          promptText: this.promptText, previews: this.importPreviews,
          busy: this.isSavingRules, sourceLocked: this.selectedSamples.length > 0,
          batchSampleCount: this.selectedSamples.length,
          candidateSummary: this.importCandidate === undefined ? '' :
            '规则：' + this.importCandidate.name + '；来源：' + this.importCandidate.sourceKeywords.join('、') +
            '。新规则放在列表顶部，优先处理匹配的新通知并自动入账。',
          onFieldChange: (field: string, value: string) => this.changeSample(field, value),
          onChooseSample: () => { void this.openSamplePicker(); },
          onCopy: () => { void this.copyNotificationPrompt(); },
          onResponseChange: (value: string) => this.updateImportResponse(value),
          onPreview: () => this.previewImportedRule(),
          onSave: () => { void this.saveImportedRule(); },
          onSetExcluded: (excluded: boolean) => this.setCurrentSampleExcluded(excluded),
          onRemoveSample: () => this.removeSample(this.selectedSamples[this.activeSampleIndex].id)
        });
      }, (key: string) => key);
    } else if (this.isLoading) {
      Text('正在读取规则…').fontSize(13).fontColor('#52606D');
    } else {
      this.rulesErrorMessage();
    }
  }

  @Builder
  private savedRulesSection() {
    if (this.errorMessage.length > 0) {
      this.rulesErrorMessage();
    } else if (this.isLoading) {
      Text('正在读取规则…').fontSize(13).fontColor('#52606D');
    } else {
      Button(this.showAdvanced ? '收起高级操作' : '显示高级操作')
        .width('100%')
        .backgroundColor('#F1F3F5')
        .fontColor('#344563')
        .onClick(() => { this.showAdvanced = !this.showAdvanced; });
      if (this.showAdvanced) {
        Button('手动新增规则')
          .width('100%')
          .backgroundColor('#2857C5')
          .fontColor('#FFFFFF')
          .enabled(!this.isSavingRules)
          .onClick(() => this.openNewRule());
      }
      if (this.rules.length === 0) {
        Text('当前没有识别规则。新增规则后，匹配的通知才会自动入账。')
          .fontSize(13)
          .fontColor('#52606D');
      }
      ForEach(this.rules, (rule: NotificationRule, index: number) => {
        this.ruleCard(index);
      }, (_rule: NotificationRule, index: number) => 'rule-' + index);
    }
  }

  @Builder
  private rulesErrorMessage() {
    Column({ space: 8 }) {
      Text(this.errorMessage).fontSize(13).fontColor('#B42318');
      Button('重新读取')
        .backgroundColor('#F1F3F5')
        .fontColor('#344563')
        .enabled(!this.isSavingRules)
        .onClick(() => { void this.reloadRules(); });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private sampleSelectionBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        List({ space: 8 }) {
          ForEach(this.selectedSamples, (item: NotificationRuleSample, index: number) => {
            ListItem() {
              Button() {
                Column({ space: 2 }) {
                  Text('样例 ' + (index + 1)).fontSize(11);
                  Text(notificationSampleStatus(item.draft)).fontSize(10);
                }.alignItems(HorizontalAlign.Center);
              }
              .width(82)
              .height(52)
              .padding(4)
              .backgroundColor(index === this.activeSampleIndex ? '#2857C5' : '#F1F3F5')
              .fontColor(index === this.activeSampleIndex ? '#FFFFFF' :
                (item.draft.excluded === true ? '#B42318' : '#344563'))
              .enabled(!this.isSavingRules)
              .onClick(() => this.activateSample(index));
            }
          }, (item: NotificationRuleSample) => 'sample-' + item.id);
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .height(56);
        Text((this.activeSampleIndex + 1) + '/' + this.selectedSamples.length)
          .fontSize(12)
          .fontColor('#52606D');
      }.width('100%');
      Text('待配置 ' + this.sampleStatusCount('待配置') + ' · 已填写 ' +
        this.sampleStatusCount('已填写') + ' · 排除 ' + this.sampleStatusCount('排除'))
        .fontSize(11)
        .fontColor('#52606D')
        .width('100%');
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 1 }, color: '#E5E8EB' });
  }

  private selectRuleSection(section: string): void {
    if (section !== 'setup' && section !== 'rules') { return; }
    this.activeRuleSection = section;
  }

  private sampleStatusCount(status: string): number {
    return this.selectedSamples.filter((item: NotificationRuleSample) => notificationSampleStatus(item.draft) === status).length;
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
      if (this.rules[index].enabled) {
        Button('补记历史通知')
          .width('100%')
          .enabled(!this.isSavingRules)
          .backgroundColor('#E9F1FF')
          .fontColor('#2457C5')
          .onClick(() => {
            this.openRebooking(index);
          });
      }
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
            const rule = this.copyRule(this.rules[index]);
            this.onOpenCreditHistory({ name: rule.name,
              source: rule.entrySource === undefined || rule.entrySource.length === 0 ? rule.name : rule.entrySource,
              notificationRule: rule });
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

  private changeSample(field: string, value: string): void {
    if (this.selectedSamples.length > 0 && ['source', 'title', 'input'].includes(field)) { return; }
    this.sample = changeRuleSample(this.sample, field, value);
    if (this.selectedSamples.length > 0) {
      this.selectedSamples = this.selectedSamples.map((item: NotificationRuleSample, index: number): NotificationRuleSample => {
        return { id: item.id, draft: field === 'matchTitle' ? changeRuleSample(item.draft, field, value) :
          index === this.activeSampleIndex ? this.sample : item.draft };
      });
    }
    this.resetImportPreview();
  }

  private resetImportPreview(): void {
    this.importCandidate = undefined;
    this.importPreviews = [];
    this.importMessage = '';
    this.promptText = '';
  }

  private currentSamples(): RuleSampleDraft[] {
    return this.selectedSamples.length > 0 ? this.selectedSamples.map((item: NotificationRuleSample) => item.draft) : [this.sample];
  }

  private activateSample(index: number): void {
    if (index < 0 || index >= this.selectedSamples.length) { return; }
    this.activeSampleIndex = index;
    this.sample = this.selectedSamples[index].draft;
  }

  private setCurrentSampleExcluded(excluded: boolean): void {
    if (this.selectedSamples.length === 0) { return; }
    const current = this.selectedSamples[this.activeSampleIndex];
    if (current === undefined || current.draft.excluded === excluded) { return; }
    const draft = changeRuleSample(current.draft, 'excluded', String(excluded));
    this.sample = draft;
    this.selectedSamples = this.selectedSamples.map((item: NotificationRuleSample, index: number): NotificationRuleSample =>
      index === this.activeSampleIndex ? { id: item.id, draft: draft } : item);
    this.resetImportPreview();
  }

  private toggleSample(entry: NotificationArchiveEntry): void {
    if (entry.bundleName !== this.pickerBundle) { return; }
    if (this.selectedSamples.some((item: NotificationRuleSample) => item.id === entry.id)) {
      this.removeSample(entry.id);
      return;
    }
    const draft = sampleFromNotification(entry);
    draft.matchTitle = this.selectedSamples.length > 0 && this.selectedSamples[0].draft.matchTitle;
    this.selectedSamples = this.selectedSamples.concat([{ id: entry.id, draft: draft }]);
    this.activateSample(this.selectedSamples.length - 1);
    this.resetImportPreview();
  }

  private removeSample(id: number): void {
    this.selectedSamples = this.selectedSamples.filter((item: NotificationRuleSample) => item.id !== id);
    this.activeSampleIndex = Math.min(this.activeSampleIndex, Math.max(0, this.selectedSamples.length - 1));
    if (this.selectedSamples.length > 0) {
      this.activateSample(this.activeSampleIndex);
    } else {
      this.sample = emptyRuleSample();
      this.sample.source = this.pickerBundle;
    }
    this.resetImportPreview();
  }

  private async openSamplePicker(): Promise<void> {
    this.pickerBundle = this.sample.source;
    this.pickerOpen = true;
    this.pickerLoading = true;
    this.pickerMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      await this.sampleRepository.open(context);
      this.pickerSources = await this.sampleRepository.listSources();
      if (!this.pickerOpen) { return; }
      this.pickerLoading = false;
      await this.loadPickerEntries();
    } catch (error) {
      this.pickerLoading = false;
      this.pickerMessage = '读取通知来源失败：' + (error as Error).message;
    }
  }

  private selectSampleSource(bundleName: string): void {
    if (bundleName !== this.sample.source) {
      this.selectedSamples = [];
      this.activeSampleIndex = 0;
      this.sample = emptyRuleSample();
      this.sample.source = bundleName;
      this.resetImportPreview();
    }
    this.pickerBundle = bundleName;
    void this.loadPickerEntries();
  }

  private async loadPickerEntries(more: boolean = false): Promise<void> {
    if (more && (this.pickerLoading || this.pickerCursor === undefined)) { return; }
    const revision = ++this.pickerQueryRevision;
    const cursor = more ? this.pickerCursor : undefined;
    if (!more) { this.pickerEntries = []; this.pickerCursor = undefined; }
    if (this.pickerBundle.length === 0) { this.pickerLoading = false; return; }
    this.pickerLoading = true;
    this.pickerMessage = '';
    try {
      const page = await this.sampleRepository.listPage({ bundleName: this.pickerBundle, keyword: '' }, cursor);
      if (revision !== this.pickerQueryRevision) { return; }
      this.pickerEntries = more ? this.pickerEntries.concat(page.entries) : page.entries;
      this.pickerCursor = page.nextCursor;
    } catch (error) {
      if (revision === this.pickerQueryRevision) {
        this.pickerMessage = '读取通知失败：' + (error as Error).message;
      }
    } finally {
      if (revision === this.pickerQueryRevision) { this.pickerLoading = false; }
    }
  }

  private updateImportResponse(value: string): void {
    this.importJson = value;
    this.importCandidate = undefined;
    this.importPreviews = [];
    this.importMessage = '';
    if (value.trim().length > 0) { this.previewImportedRule(); }
  }

  private async copyNotificationPrompt(): Promise<void> {
    const samples = this.currentSamples();
    const issue = validateNotificationSamples(samples);
    if (issue.length > 0) { this.importMessage = issue; return; }
    const prompt = buildNotificationSamplesPrompt(samples);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, prompt);
      await pasteboard.getSystemPasteboard().setData(data);
      this.promptText = '';
      this.importMessage = '已将全部 ' + samples.length + ' 条样例及各自确认值复制到同一份提示词。请一次提交给 AI 生成一条覆盖全部样例的规则，再粘贴返回内容。';
    } catch (_error) {
      this.promptText = prompt;
      this.importMessage = '复制失败，可以长按下方完整材料手动复制。';
    }
  }

  private previewImportedRule(): void {
    this.importCandidate = undefined;
    this.importPreviews = [];
    const samples = this.currentSamples();
    const issue = validateNotificationSamples(samples);
    if (issue.length > 0) { this.importMessage = issue; return; }
    const parsed = parseRuleImport(unwrapRuleResponse(this.importJson), 'notification');
    if (parsed.valid === false) {
      this.importMessage = explainImportIssues(parsed.issues);
      return;
    }
    const rule = createNotificationRule(parsed.rule as CompactNotificationRule, this.rules);
    rule.requiredTitle = samples[0].matchTitle && samples[0].title.length > 0 ? samples[0].title : undefined;
    this.importPreviews = previewNotificationSamples(rule, samples, this.rules);
    this.importCandidate = rule;
    const passed = this.importPreviews.filter((preview: RuleImportPreview) => preview.matched).length;
    this.importMessage = passed === samples.length ?
      '全部 ' + samples.length + ' 条通知及金额泛化检查通过，请核对后保存。' :
      '通过 ' + passed + ' / ' + samples.length + ' 条；请让 AI 调整未匹配通知或金额正则。';
  }

  private async saveImportedRule(): Promise<void> {
    if (this.isSavingRules || this.importCandidate === undefined || this.importPreviews.length === 0 ||
      this.importPreviews.length !== this.currentSamples().length || this.importPreviews.some((preview: RuleImportPreview) => !preview.matched)) {
      return;
    }
    const saveError = await this.persistRules([this.importCandidate].concat(this.rules));
    if (saveError === undefined) {
      this.importJson = '';
      this.importCandidate = undefined;
      this.importPreviews = [];
      this.sample = emptyRuleSample();
      this.selectedSamples = [];
      this.activeSampleIndex = 0;
      this.promptText = '';
      this.importMessage = '规则已保存并启用。';
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

  private openRebooking(index: number): void {
    if (!this.rules[index].enabled) { return; }
    this.rebookingRule = this.copyRule(this.rules[index]);
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
      requiredTitle: rule.requiredTitle,
      excludeBodyPatterns: rule.excludeBodyPatterns?.slice(),
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
