import {
  EntrySource,
  LedgerEntry,
  accountingTypeLabel,
  accountingTypeOf,
  formatDateOnly,
  formatDateTime,
  formatMoney
} from '../model/LedgerModels';
import { AppTheme } from '../model/AppTheme';

@Component
export struct LedgerEntryCard {
  @Prop entry: LedgerEntry = {
    id: '',
    happenedAt: 0,
    hasTime: false,
    amountFen: 0,
    direction: 'expense',
    source: 'manual',
    merchant: '',
    category: '其他',
    note: ''
  };
  @Prop sourceLabel: string = '';
  @Prop showFullDate: boolean = false;
  @Prop expenseColor: string = '#172B4D';
  onEdit: (entry: LedgerEntry) => void = (_entry: LedgerEntry) => {};
  onDeleteRequest: (entry: LedgerEntry) => void = (_entry: LedgerEntry) => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.entry.merchant.length > 0 ? this.entry.merchant : '未填写摘要')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
        if (accountingTypeOf(this.entry) !== 'normal') {
          Text(accountingTypeLabel(accountingTypeOf(this.entry)))
            .fontSize(10)
            .fontColor(AppTheme.brandText)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(AppTheme.brandPrimarySoft)
            .borderRadius(4);
        }
      }
      .width('100%');
      Row() {
        Text(this.metadataText())
          .fontSize(11)
          .fontColor(AppTheme.textMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
        Text((this.entry.direction === 'income' ? '+' : '−') + formatMoney(this.entry.amountFen))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(accountingTypeOf(this.entry) === 'credit-repayment' ? AppTheme.textSecondary :
            this.entry.direction === 'income' ? AppTheme.income : this.expenseColor);
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppTheme.surfaceCard)
    .borderRadius(AppTheme.cardRadius)
    .border({ width: { left: 4 }, color: this.sourceAccentColor(this.entry.source) })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ duration: 500 })
          .onAction(() => {
            this.onDeleteRequest(this.entry);
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            this.onEdit(this.entry);
          })
      )
    );
  }

  private sourceAccentColor(source: EntrySource): string {
    if (source === 'wechat') {
      return '#07C160';
    }
    if (source === 'alipay') {
      return '#1677FF';
    }
    if (source === 'icbc' || source === 'citic') {
      return '#C41230';
    }
    if (source === 'manual') {
      return AppTheme.borderSubtle;
    }
    return '#8892A0';
  }

  private metadataText(): string {
    const dateText = this.showFullDate ?
      (this.entry.hasTime ? formatDateTime(this.entry.happenedAt) : formatDateOnly(this.entry.happenedAt)) :
      (this.entry.hasTime ? formatDateTime(this.entry.happenedAt).slice(11) : '');
    const timeSeparator = dateText.length > 0 ? ' · ' : '';
    return dateText + timeSeparator + this.entry.category + ' · ' + this.sourceLabel;
  }
}
