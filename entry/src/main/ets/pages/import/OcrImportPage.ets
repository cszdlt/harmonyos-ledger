import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DraftEntry, EntryDirection, EntrySource, ImportSource, LedgerEntry, hasClockTime } from '../../model/LedgerModels';
import { DraftValidationError, OcrImportResult, OcrSourceOption, UnclassifiedOcrPage } from '../../model/OcrModels';
import { OcrImporter } from '../../services/OcrImporter';
import { OcrDraftConfirmationPlan, OcrImportCoordinator } from '../../services/OcrImportCoordinator';
import { loadOcrRules } from '../../services/OcrRuleStore';
import type { OcrRule } from '../../services/ocrRules/OcrRuleModels';
import { OcrImportView } from './OcrImportView';

export interface OcrImportSaveResult {
  success: boolean;
  message: string;
}

const DEFAULT_OCR_IMPORT_SAVE_RESULT: OcrImportSaveResult = {
  success: false,
  message: '保存回调未连接'
};

@Component
export struct OcrImportPage {
  @Prop entries: LedgerEntry[] = [];
  @Prop shareImportMode: boolean = false;
  @Prop sharedImportUris: string[] = [];
  @Prop sharedImportError: string = '';
  @Watch('onSessionRevisionChanged')
  @Prop sessionRevision: number = 0;
  @Watch('onBackRequestChanged')
  @Prop backRequestRevision: number = 0;
  sourceLabel: (source: EntrySource) => string = (_source: EntrySource) => '';

  onBack: () => void = () => {};
  onToast: (message: string) => void = (_message: string) => {};
  onConfirmDrafts: (plan: OcrDraftConfirmationPlan) => Promise<OcrImportSaveResult> =
    (_plan: OcrDraftConfirmationPlan) => Promise.resolve(DEFAULT_OCR_IMPORT_SAVE_RESULT);

  @State private drafts: DraftEntry[] = [];
  @State private unclassifiedPages: UnclassifiedOcrPage[] = [];
  @State private ocrRawText: string = '';
  @State private ocrLoading: boolean = false;
  @State private ocrErrorMessage: string = '';
  @State private reviewMessage: string = '';
  @State private draftValidationErrors: DraftValidationError[] = [];
  @State private shareImportCompleted: boolean = false;
  @State private shareImportCancelled: boolean = false;
  @State private shareImportOutcomeMessage: string = '';
  @State private pendingImportDiscardConfirmation: boolean = false;
  @State private localSharedImportError: string = '';
  @State private sharedImportErrorDismissed: boolean = false;
  private ocrRulesSnapshot: OcrRule[] = [];
  private ocrRequestId: number = 0;
  private handledSessionRevision: number = -1;

  aboutToAppear(): void {
    this.startSessionForRevision();
  }

  private onSessionRevisionChanged(): void {
    this.startSessionForRevision();
  }

  private onBackRequestChanged(): void {
    if (this.pendingImportDiscardConfirmation) {
      this.pendingImportDiscardConfirmation = false;
      return;
    }
    if (this.shareImportMode) {
      void this.closeShareImport();
      return;
    }
    this.requestLeaveImport();
  }

  private startSessionForRevision(): void {
    if (this.handledSessionRevision === this.sessionRevision) {
      return;
    }
    this.handledSessionRevision = this.sessionRevision;
    this.resetImportReview();
    this.pendingImportDiscardConfirmation = false;
    this.shareImportCompleted = false;
    this.shareImportCancelled = false;
    this.shareImportOutcomeMessage = '';
    this.sharedImportErrorDismissed = false;
    this.localSharedImportError = '';
    if (this.shareImportMode) {
      if (this.sharedImportError.length === 0) {
        void this.startSharedImport();
      }
      return;
    }
    void this.startImport();
  }

  private effectiveSharedImportError(): string {
    if (this.localSharedImportError.length > 0) {
      return this.localSharedImportError;
    }
    return this.sharedImportErrorDismissed ? '' : this.sharedImportError;
  }

  build() {
    if (this.shareImportMode && this.shareImportCompleted) {
      this.shareImportOutcomeView(true);
    } else if (this.shareImportMode && this.shareImportCancelled) {
      this.shareImportOutcomeView(false);
    } else if (this.shareImportMode && !this.ocrLoading && this.effectiveSharedImportError().length > 0) {
      this.shareImportErrorView();
    } else {
      Stack() {
        OcrImportView({
          drafts: this.drafts,
          unclassifiedPages: this.unclassifiedPages,
          sourceOptions: this.enabledOcrSourceOptions(),
          rawText: this.ocrRawText,
          loading: this.ocrLoading,
          errorMessage: this.ocrErrorMessage,
          reviewMessage: this.reviewMessage,
          validationErrors: this.draftValidationErrors,
          selectedDraftCount: OcrImportCoordinator.selectedCount(this.drafts),
          shareImportMode: this.shareImportMode,
          sourceLabel: (source: EntrySource) => this.sourceLabel(source),
          duplicateMessage: (draft: DraftEntry) => OcrImportCoordinator.duplicateMessage(draft, this.entries),
          onBack: () => this.requestLeaveImport(),
          onSelectImages: () => {
            void this.startImport();
          },
          onSave: () => {
            void this.confirmDrafts();
          },
          onRawTextChange: (value: string) => {
            this.ocrRawText = value;
          },
          onToggleDraft: (id: string) => this.toggleDraft(id),
          onDirectionChange: (id: string, direction: EntryDirection) => this.setDraftDirection(id, direction),
          onTextChange: (id: string, field: string, value: string) => this.setDraftText(id, field, value),
          onResolvePage: (pageNumber: number, source?: ImportSource) => this.resolveUnclassifiedPage(pageNumber, source)
        });
        if (this.pendingImportDiscardConfirmation) {
          this.discardConfirmationView();
        }
      }
      .width('100%')
      .height('100%');
    }
  }

  private async confirmDrafts(): Promise<void> {
    const plan = OcrImportCoordinator.prepareConfirmation(this.drafts, this.entries);
    if (plan.validationErrors.length > 0) {
      this.draftValidationErrors = plan.validationErrors;
      this.reviewMessage = '请修正标记为错误的记录，或取消勾选不入账。';
      return;
    }
    this.draftValidationErrors = [];
    if (plan.selectedCount === 0) {
      this.reviewMessage = '请至少勾选一条有效记录。';
      return;
    }
    await this.persistDrafts(plan);
  }
  private async persistDrafts(plan: OcrDraftConfirmationPlan): Promise<void> {
    const result = await this.onConfirmDrafts(plan);
    if (!result.success) {
      this.reviewMessage = result.message;
      return;
    }
    this.shareImportOutcomeMessage = result.message;
    this.resetImportReview();
    this.shareImportCompleted = this.shareImportMode;
    this.shareImportCancelled = false;
    if (!this.shareImportMode) {
      this.onToast(result.message);
      this.onBack();
    }
  }

  private confirmDiscardImport(): void {
    this.pendingImportDiscardConfirmation = false;
    this.cancelImport();
  }
  private resetImportReview(): void {
    this.drafts = [];
    this.unclassifiedPages = [];
    this.ocrRawText = '';
    this.ocrErrorMessage = '';
    this.reviewMessage = '';
    this.draftValidationErrors = [];
    this.ocrRulesSnapshot = [];
  }

  private async startImport(): Promise<void> {
    if (this.ocrLoading) {
      return;
    }
    const requestId = ++this.ocrRequestId;
    this.ocrLoading = true;
    this.ocrErrorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const rules = await loadOcrRules(context);
      if (requestId !== this.ocrRequestId) {
        return;
      }
      this.ocrRulesSnapshot = rules;
      const recognition = await OcrImporter.chooseAndRecognize(context);
      if (requestId !== this.ocrRequestId) {
        return;
      }
      if (recognition.pages.length === 0) {
        if (this.drafts.length === 0 && this.unclassifiedPages.length === 0) {
          this.onBack();
        }
        this.onToast('未选择截图');
        return;
      }
      this.applyImportResult(OcrImportCoordinator.parsePages(recognition.pages, this.entries, rules));
    } catch (error) {
      if (requestId === this.ocrRequestId) {
        const businessError = error as BusinessError;
        this.ocrErrorMessage = '截图识别失败：' + businessError.message;
      }
    } finally {
      if (requestId === this.ocrRequestId) {
        this.ocrLoading = false;
      }
    }
  }

  private applyImportResult(result: OcrImportResult): void {
    this.drafts = result.drafts;
    this.unclassifiedPages = result.unclassifiedPages;
    this.ocrRawText = result.rawText;
    this.reviewMessage = result.drafts.length === 0 && result.unclassifiedPages.length === 0 ?
      '没有识别到可入账的账目。日期不明确的记录不会自动补日期。' : '';
    this.draftValidationErrors = [];
  }

  private async startSharedImport(): Promise<void> {
    if (this.sharedImportUris.length === 0) {
      this.sharedImportErrorDismissed = true;
      this.localSharedImportError = '没有收到可导入的图片。';
      return;
    }
    this.sharedImportErrorDismissed = true;
    this.localSharedImportError = '';
    this.ocrLoading = true;
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const rules = await loadOcrRules(context);
      this.ocrRulesSnapshot = rules;
      const recognition = await OcrImporter.recognizeUris(this.sharedImportUris);
      this.applyImportResult(OcrImportCoordinator.parsePages(recognition.pages, this.entries, rules));
    } catch (error) {
      const businessError = error as BusinessError;
      this.localSharedImportError = '截图识别失败：' + businessError.message;
    } finally {
      this.ocrLoading = false;
    }
  }

  private async closeShareImport(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIExtensionContext;
      await context.terminateSelf();
    } catch (error) {
      const businessError = error as BusinessError;
      this.onToast('关闭失败：' + businessError.message);
    }
  }

  private requestLeaveImport(): void {
    if (this.shareImportMode) {
      this.cancelImport();
      return;
    }
    if (this.drafts.length > 0 || this.unclassifiedPages.length > 0) {
      this.pendingImportDiscardConfirmation = true;
      return;
    }
    this.cancelImport();
  }

  private cancelImport(): void {
    this.ocrRequestId++;
    this.pendingImportDiscardConfirmation = false;
    this.ocrLoading = false;
    this.resetImportReview();
    this.shareImportCancelled = this.shareImportMode;
    if (!this.shareImportMode) {
      this.onBack();
    }
  }

  private resolveUnclassifiedPage(pageNumber: number, source?: ImportSource): void {
    const page = this.unclassifiedPages.find((item: UnclassifiedOcrPage) => item.pageNumber === pageNumber);
    if (page === undefined) {
      return;
    }
    if (source !== undefined) {
      const parsed = OcrImportCoordinator.parsePage(
        page.lines, source, this.entries, this.ocrRulesSnapshot, this.drafts, page.captureTime, page.imageWidth);
      this.drafts = this.drafts.concat(parsed);
      this.reviewMessage = parsed.length === 0 ?
        '所选来源下没有找到带明确日期的交易记录；请检查原文或跳过该截图。' : '';
    }
    this.unclassifiedPages = this.unclassifiedPages.filter((item: UnclassifiedOcrPage) =>
      item.pageNumber !== pageNumber);
  }

  private setDraftText(id: string, field: string, value: string): void {
    this.drafts = this.drafts.map((draft: DraftEntry) => {
      if (draft.id !== id) {
        return draft;
      }
      const updated: DraftEntry = {
        id: draft.id,
        source: draft.source,
        merchant: field === 'merchant' ? value : draft.merchant,
        dateText: field === 'dateText' ? value : draft.dateText,
        hasTime: field === 'dateText' ? hasClockTime(value) : draft.hasTime,
        amountText: field === 'amountText' ? value : draft.amountText,
        direction: draft.direction,
        category: field === 'category' ? value : draft.category,
        checked: draft.checked,
        isRefund: draft.isRefund,
        warnings: draft.warnings.slice()
      };
      if (field === 'dateText' && value.trim().length > 0) {
        updated.warnings = updated.warnings.filter((warning: string) =>
          warning !== '未识别到日期标题，请填写交易日期');
      }
      if (field === 'merchant' && value.trim().length > 0) {
        updated.warnings = updated.warnings.filter((warning: string) => warning !== '未识别到商户或摘要');
      }
      return updated;
    });
    this.clearDraftValidationError(id);
  }

  private setDraftDirection(id: string, direction: EntryDirection): void {
    this.drafts = this.drafts.map((draft: DraftEntry) => {
      if (draft.id !== id) {
        return draft;
      }
      return {
        id: draft.id,
        source: draft.source,
        merchant: draft.merchant,
        dateText: draft.dateText,
        hasTime: draft.hasTime,
        amountText: draft.amountText,
        direction: direction,
        category: draft.category,
        checked: draft.checked,
        isRefund: draft.isRefund,
        warnings: draft.warnings.filter((warning: string) =>
          warning !== '金额方向不明确，请选择收入或支出' &&
          warning !== '识别到退款，请确认收入或支出方向')
      };
    });
    this.clearDraftValidationError(id);
  }

  private toggleDraft(id: string): void {
    this.drafts = this.drafts.map((draft: DraftEntry) => {
      if (draft.id !== id) {
        return draft;
      }
      return {
        id: draft.id,
        source: draft.source,
        merchant: draft.merchant,
        dateText: draft.dateText,
        hasTime: draft.hasTime,
        amountText: draft.amountText,
        direction: draft.direction,
        category: draft.category,
        checked: !draft.checked,
        isRefund: draft.isRefund,
        warnings: draft.warnings.slice()
      };
    });
    this.clearDraftValidationError(id);
  }

  private clearDraftValidationError(id: string): void {
    const remaining = this.draftValidationErrors.filter((error: DraftValidationError) => error.id !== id);
    if (remaining.length !== this.draftValidationErrors.length) {
      this.draftValidationErrors = remaining;
      if (remaining.length === 0 && this.reviewMessage === '请修正标记为错误的记录，或取消勾选不入账。') {
        this.reviewMessage = '';
      }
    }
  }



  private enabledOcrSourceOptions(): OcrSourceOption[] {
    const options: OcrSourceOption[] = [];
    this.ocrRulesSnapshot.filter((rule: OcrRule) => rule.enabled).forEach((rule: OcrRule) => {
      if (!options.some((option: OcrSourceOption) => option.id === rule.source)) {
        options.push({ id: rule.source, name: rule.sourceName ?? rule.name });
      }
    });
    return options;
  }

  @Builder
  private shareImportErrorView() {
    Column({ space: 14 }) {
      Text('无法导入截图')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172B4D');
      Text(this.effectiveSharedImportError())
        .fontSize(14)
        .fontColor('#52606D')
        .textAlign(TextAlign.Center);
      if (this.sharedImportUris.length > 0) {
        Button('重试识别')
          .width('100%')
          .backgroundColor('#2857C5')
          .fontColor('#FFFFFF')
          .onClick(() => {
            void this.startSharedImport();
          });
      }
      Button('关闭')
        .width('100%')
        .backgroundColor('#F1F3F5')
        .fontColor('#344563')
        .onClick(() => {
          void this.closeShareImport();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24);
  }

  @Builder
  private shareImportOutcomeView(saved: boolean) {
    Column({ space: 14 }) {
      Text(saved ? '已记入账本' : '已取消导入')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(saved ? '#16845B' : '#172B4D');
      Text(saved ? '本次导入：' + (this.shareImportOutcomeMessage.length > 0 ?
        this.shareImportOutcomeMessage : '账目已保存在本机。') : '截图没有写入账本。')
        .fontSize(14)
        .fontColor('#52606D');
      Button('完成')
        .width('100%')
        .backgroundColor('#2857C5')
        .fontColor('#FFFFFF')
        .onClick(() => {
          void this.closeShareImport();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24);
  }

  @Builder
  private discardConfirmationView() {
    Column() {
      Column({ space: 10 }) {
        Text('有内容尚未保存，确定放弃并离开吗？')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#344563');
        Row({ space: 10 }) {
          Button('继续编辑')
            .layoutWeight(1)
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => {
              this.pendingImportDiscardConfirmation = false;
            });
          Button('放弃并离开')
            .layoutWeight(1)
            .backgroundColor('#B42318')
            .fontColor('#FFFFFF')
            .onClick(() => this.confirmDiscardImport());
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
    .backgroundColor('#66000000')
    .zIndex(1);
  }
}