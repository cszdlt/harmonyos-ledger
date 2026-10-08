import {
  EntryDirection,
  EntrySource,
  LedgerEntry,
  formatDateOnly,
  formatDateTime,
  hasClockTime,
  makeId,
  parseAmountFen,
  parseDateTime
} from '../../model/LedgerModels';
import { LedgerEditorView } from './LedgerEditorView';

@Component
export struct LedgerEditorPage {
  @Prop editingEntry: LedgerEntry | undefined = undefined;
  @Watch('onSessionRevisionChanged')
  @Prop sessionRevision: number = 0;
  @Watch('onBackRequestChanged')
  @Prop backRequestRevision: number = 0;

  onBack: () => void = () => {};
  onSave: (entry: LedgerEntry, isEditing: boolean) => Promise<boolean> =
    (_entry: LedgerEntry, _isEditing: boolean) => Promise.resolve(false);

  @State private editingId: string = '';
  @State private editingSource: EntrySource = 'manual';
  @State private editorDirty: boolean = false;
  @State private editorDateError: string = '';
  @State private editorAmountError: string = '';
  @State private pendingDiscardConfirmation: boolean = false;
  @State private formMerchant: string = '';
  @State private formDateText: string = '';
  @State private formAmountText: string = '';
  @State private formDirection: EntryDirection = 'expense';
  @State private formCategory: string = '其他';
  @State private formNote: string = '';
  private handledSessionRevision: number = -1;

  aboutToAppear(): void {
    this.startSessionForRevision();
  }

  private onSessionRevisionChanged(): void {
    this.startSessionForRevision();
  }

  private onBackRequestChanged(): void {
    if (this.pendingDiscardConfirmation) {
      this.pendingDiscardConfirmation = false;
      return;
    }
    this.requestLeaveEditor();
  }

  private startSessionForRevision(): void {
    if (this.handledSessionRevision === this.sessionRevision) {
      return;
    }
    this.handledSessionRevision = this.sessionRevision;
    this.editorDirty = false;
    this.editorDateError = '';
    this.editorAmountError = '';
    this.pendingDiscardConfirmation = false;
    if (this.editingEntry === undefined) {
      this.editingId = '';
      this.editingSource = 'manual';
      this.formMerchant = '';
      this.formDateText = formatDateTime(Date.now());
      this.formAmountText = '';
      this.formDirection = 'expense';
      this.formCategory = '其他';
      this.formNote = '';
      return;
    }
    this.editingId = this.editingEntry.id;
    this.editingSource = this.editingEntry.source;
    this.formMerchant = this.editingEntry.merchant;
    this.formDateText = this.editingEntry.hasTime ?
      formatDateTime(this.editingEntry.happenedAt) : formatDateOnly(this.editingEntry.happenedAt);
    this.formAmountText = (this.editingEntry.amountFen / 100).toFixed(2);
    this.formDirection = this.editingEntry.direction;
    this.formCategory = this.editingEntry.category;
    this.formNote = this.editingEntry.note;
  }

  build() {
    Stack() {
      this.editorView();
      if (this.pendingDiscardConfirmation) {
        this.discardConfirmationView();
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private editorView() {
    LedgerEditorView({
      editingId: this.editingId,
      merchant: this.formMerchant,
      dateText: this.formDateText,
      amountText: this.formAmountText,
      entryDirection: this.formDirection,
      category: this.formCategory,
      note: this.formNote,
      dateError: this.editorDateError,
      amountError: this.editorAmountError,
      onBack: () => this.requestLeaveEditor(),
      onSave: () => {
        void this.saveEditor();
      },
      onChooseDate: () => this.chooseEditorDate(),
      onFieldChange: (field: string, value: string) => this.setFormValue(field, value),
      onDirectionChange: (direction: EntryDirection) => {
        this.editorDirty = this.editorDirty || this.formDirection !== direction;
        this.formDirection = direction;
      }
    });
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
              this.pendingDiscardConfirmation = false;
            });
          Button('放弃并离开')
            .layoutWeight(1)
            .backgroundColor('#B42318')
            .fontColor('#FFFFFF')
            .onClick(() => this.discardEditor());
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

  private setFormValue(field: string, value: string): void {
    if (field === 'merchant') {
      this.editorDirty = this.editorDirty || this.formMerchant !== value;
      this.formMerchant = value;
    } else if (field === 'date') {
      this.editorDirty = this.editorDirty || this.formDateText !== value;
      this.formDateText = value;
      this.editorDateError = '';
    } else if (field === 'amount') {
      this.editorDirty = this.editorDirty || this.formAmountText !== value;
      this.formAmountText = value;
      this.editorAmountError = '';
    } else if (field === 'category') {
      this.editorDirty = this.editorDirty || this.formCategory !== value;
      this.formCategory = value;
    } else {
      this.editorDirty = this.editorDirty || this.formNote !== value;
      this.formNote = value;
    }
  }

  private chooseEditorDate(): void {
    const current = parseDateTime(this.formDateText) ?? Date.now();
    const uiContext = this.getUIContext();
    uiContext.showDatePickerDialog({
      selected: new Date(current),
      onDateAccept: (date: Date) => {
        const selected = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        const time = this.formDateText.trim().match(/(?:^|\s)(\d{1,2}):(\d{2})$/);
        const dateText = formatDateOnly(selected);
        const value = time === null ? dateText : dateText + ' ' +
          String(Number(time[1])).padStart(2, '0') + ':' + time[2];
        uiContext.runScopedTask(() => {
          this.setFormValue('date', value);
        });
      }
    });
  }

  private async saveEditor(): Promise<void> {
    const date = parseDateTime(this.formDateText);
    const amountFen = parseAmountFen(this.formAmountText);
    this.editorDateError = date === undefined ? '请填写有效日期，例如 2026-10-04 18:30。' : '';
    this.editorAmountError = amountFen === undefined || amountFen <= 0 ? '金额需为大于 0 的有效数字。' : '';
    if (this.editorDateError.length > 0 || this.editorAmountError.length > 0 ||
      date === undefined || amountFen === undefined || amountFen <= 0) {
      return;
    }
    const entry: LedgerEntry = {
      id: this.editingId.length > 0 ? this.editingId : makeId('entry'),
      happenedAt: date,
      hasTime: hasClockTime(this.formDateText),
      amountFen: amountFen,
      direction: this.formDirection,
      source: this.editingSource,
      merchant: this.formMerchant.trim(),
      category: this.formCategory.trim().length > 0 ? this.formCategory.trim() : '其他',
      note: this.formNote.trim()
    };
    const saved = await this.onSave(entry, this.editingId.length > 0);
    if (saved) {
      this.editorDirty = false;
      this.onBack();
    }
  }

  private requestLeaveEditor(): void {
    if (this.editorDirty) {
      this.pendingDiscardConfirmation = true;
      return;
    }
    this.discardEditor();
  }

  private discardEditor(): void {
    this.pendingDiscardConfirmation = false;
    this.editorDirty = false;
    this.editorDateError = '';
    this.editorAmountError = '';
    this.onBack();
  }
}
