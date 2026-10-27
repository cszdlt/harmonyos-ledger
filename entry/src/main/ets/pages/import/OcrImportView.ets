import { DraftEntry, EntryDirection, EntrySource, ImportSource } from '../../model/LedgerModels';
import { DraftValidationError, OcrSourceOption, UnclassifiedOcrPage } from '../../model/OcrModels';

type DraftTextField = 'merchant' | 'dateText' | 'amountText' | 'category';

@Component
struct DraftCard {
  @Prop draft: DraftEntry = {
    id: '',
    source: 'manual',
    merchant: '',
    dateText: '',
    hasTime: false,
    amountText: '',
    direction: undefined,
    category: '',
    checked: false,
    isRefund: false,
    warnings: []
  };
  @Prop sourceLabel: string = '';
  @Prop validationError: string = '';
  @Prop duplicateMessage: string = '';

  onToggle: () => void = () => {};
  onDirectionChange: (direction: EntryDirection) => void = (_direction: EntryDirection) => {};
  onTextChange: (field: DraftTextField, value: string) => void = (_field: DraftTextField, _value: string) => {};

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.draft.isRefund ? '退款记录' : this.sourceLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.draft.isRefund ? '#B54708' : '#52606D');
        Blank();
        Button(this.draft.checked ? '已选中' : '跳过')
          .backgroundColor(this.draft.checked ? '#E8F0FE' : '#F1F3F5')
          .fontColor(this.draft.checked ? '#2457C5' : '#52606D')
          .onClick(() => this.onToggle());
      }
      .width('100%');

      this.draftInput('商户或摘要', this.draft.merchant, 'merchant');
      this.draftInput('日期时间（YYYY-MM-DD HH:mm）', this.draft.dateText, 'dateText');
      this.draftInput('金额（元）', this.draft.amountText, 'amountText');
      if (this.draft.direction === 'expense' && this.draft.accountingType === 'credit-card') {
        Text('信用卡消费 · 确认后计入支出，不扣减本期现金结余')
          .fontSize(12)
          .fontColor('#2457C5');
      }

      Row({ space: 10 }) {
        Button('支出')
          .layoutWeight(1)
          .backgroundColor(this.draft.direction === 'expense' ? '#2857C5' : '#F1F3F5')
          .fontColor(this.draft.direction === 'expense' ? '#FFFFFF' : '#344563')
          .onClick(() => this.onDirectionChange('expense'));
        Button('收入')
          .layoutWeight(1)
          .backgroundColor(this.draft.direction === 'income' ? '#16845B' : '#F1F3F5')
          .fontColor(this.draft.direction === 'income' ? '#FFFFFF' : '#344563')
          .onClick(() => this.onDirectionChange('income'));
      }
      .width('100%');

      this.draftInput('分类', this.draft.category, 'category');

      if (this.draft.warnings.length > 0) {
        Text(this.draft.warnings.join(' · '))
          .fontSize(12)
          .fontColor('#B54708');
      }
      if (this.duplicateMessage.length > 0) {
        Text(this.duplicateMessage)
          .fontSize(12)
          .fontColor('#8A4B08');
      }
      if (this.validationError.length > 0) {
        Text(this.validationError)
          .fontSize(12)
          .fontColor('#B42318');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .opacity(this.draft.checked ? 1 : 0.55);
  }

  @Builder
  private draftInput(label: string, value: string, field: DraftTextField) {
    Column({ space: 5 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#7B8794');
      TextInput({ text: value, placeholder: label })
        .fontSize(14)
        .backgroundColor('#F6F7F9')
        .borderRadius(8)
        .type(field === 'amountText' ? InputType.NUMBER_DECIMAL : InputType.Normal)
        .onChange((changed: string) => this.onTextChange(field, changed));
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}

@Component
export struct OcrImportView {
  @Prop drafts: DraftEntry[] = [];
  @Prop unclassifiedPages: UnclassifiedOcrPage[] = [];
  @Prop sourceOptions: OcrSourceOption[] = [];
  @Prop rawText: string = '';
  @Prop loading: boolean = false;
  @Prop errorMessage: string = '';
  @Prop reviewMessage: string = '';
  @Prop validationErrors: DraftValidationError[] = [];
  @Prop selectedDraftCount: number = 0;
  @Prop shareImportMode: boolean = false;

  sourceLabel: (source: EntrySource) => string = (_source: EntrySource) => '';
  duplicateMessage: (draft: DraftEntry) => string = (_draft: DraftEntry) => '';
  onBack: () => void = () => {};
  onSelectImages: () => void = () => {};
  onSave: () => void = () => {};
  onRawTextChange: (text: string) => void = (_text: string) => {};
  onToggleDraft: (id: string) => void = (_id: string) => {};
  onDirectionChange: (id: string, direction: EntryDirection) => void = (_id: string, _direction: EntryDirection) => {};
  onTextChange: (id: string, field: string, value: string) => void = (_id: string, _field: string, _value: string) => {};
  onResolvePage: (pageNumber: number, source?: ImportSource) => void = (_pageNumber: number, _source?: ImportSource) => {};

  build() {
    Column() {
      Row() {
        Button(this.shareImportMode ? '取消导入' : '返回')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onBack());
        Blank();
        Text('复核识别结果')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
        Blank();
        Button(this.selectedDraftCount > 0 ? '确认入账（' + this.selectedDraftCount + '）' : '确认入账')
          .enabled(!this.loading && this.unclassifiedPages.length === 0 && this.selectedDraftCount > 0)
          .backgroundColor('#2857C5')
          .fontColor('#FFFFFF')
          .onClick(() => this.onSave());
      }
      .width('100%')
      .padding(16);

      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(22).height(22);
          Text('正在识别账单截图…')
            .fontSize(14)
            .fontColor('#2457C5');
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 8 });
      }
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 8 })
          .fontSize(13)
          .fontColor('#B42318');
      }
      if (this.reviewMessage.length > 0) {
        Text(this.reviewMessage)
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 8 })
          .fontSize(13)
          .fontColor('#B42318');
      }

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.drafts.length > 0 ? '待复核 ' + this.drafts.length + ' 笔' : '识别结果')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('已选 ' + this.selectedDraftCount + ' 笔' +
              (this.unclassifiedPages.length > 0 ? ' · ' + this.unclassifiedPages.length + ' 张截图待选来源' : ''))
              .fontSize(12)
              .fontColor('#52606D');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor('#E9F1FF')
          .borderRadius(12);

          if (this.unclassifiedPages.length > 0) {
            Text('以下截图来源不明确，请选择平台；跳过的截图不会入账。')
              .fontSize(13)
              .fontColor('#8A4B08');
            ForEach(this.unclassifiedPages, (page: UnclassifiedOcrPage) => {
              this.unclassifiedPageCard(page);
            }, (page: UnclassifiedOcrPage) => String(page.pageNumber));
          }

          if (this.drafts.length === 0 && this.unclassifiedPages.length === 0) {
            Text('没有识别到可入账记录。可以展开识别原文，确认截图中是否包含清晰的交易信息。')
              .fontSize(14)
              .fontColor('#7B8794');
          } else if (this.drafts.length > 0) {
            Text('逐笔核对日期、金额和方向；取消勾选的记录不会保存。')
              .fontSize(13)
              .fontColor('#52606D');
            ForEach(this.drafts, (draft: DraftEntry) => {
              DraftCard({
                draft: draft,
                sourceLabel: this.sourceLabel(draft.source),
                validationError: this.validationErrorFor(draft.id),
                duplicateMessage: this.duplicateMessage(draft),
                onToggle: () => this.onToggleDraft(draft.id),
                onDirectionChange: (direction: EntryDirection) => this.onDirectionChange(draft.id, direction),
                onTextChange: (field: DraftTextField, value: string) => this.onTextChange(draft.id, field, value)
              });
            }, (draft: DraftEntry) => draft.id + ':' +
              (draft.direction === undefined ? 'unknown' : draft.direction) + ':' + (draft.checked ? '1' : '0'));
          }

          Button('重新选择截图')
            .width('100%')
            .backgroundColor('#FFFFFF')
            .fontColor('#2457C5')
            .enabled(!this.loading)
            .onClick(() => this.onSelectImages());

          Text('OCR 原文（可编辑；编辑草稿请使用上方字段）')
            .fontSize(13)
            .fontColor('#52606D');
          TextArea({ text: this.rawText, placeholder: '识别后的文字会显示在这里' })
            .width('100%')
            .height(180)
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .onChange((value: string) => this.onRawTextChange(value));
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 20 });
      }
      .layoutWeight(1)
      .width('100%');

      if (this.loading) {
        Text('请等待当前截图识别完成后再保存。')
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 10 })
          .fontSize(12)
          .fontColor('#7B8794');
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7F9');
  }

  @Builder
  private unclassifiedPageCard(page: UnclassifiedOcrPage) {
    Column({ space: 10 }) {
      Text('截图 ' + page.pageNumber + '：请选择来源')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172B4D');
      Column({ space: 8 }) {
        ForEach(this.sourceOptions, (source: OcrSourceOption) => {
          Button(source.name)
            .width('100%')
            .onClick(() => this.onResolvePage(page.pageNumber, source.id));
        }, (source: OcrSourceOption) => source.id);
        Button('跳过')
          .width('100%')
          .onClick(() => this.onResolvePage(page.pageNumber));
      }
      .width('100%');
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFF8E8')
    .borderRadius(12);
  }

  private validationErrorFor(id: string): string {
    const error = this.validationErrors.find((item: DraftValidationError) => item.id === id);
    return error === undefined ? '' : error.message;
  }
}
