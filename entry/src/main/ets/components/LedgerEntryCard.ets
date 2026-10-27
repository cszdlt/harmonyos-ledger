import { LedgerEntry, accountingTypeLabel, accountingTypeOf, formatDateOnly, formatDateTime, formatMoney } from '../model/LedgerModels';

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
      Row() {
        Text(this.entry.merchant.length > 0 ? this.entry.merchant : '未填写摘要')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172B4D')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
      }
      .width('100%');
      Row() {
        Text(this.metadataText())
          .fontSize(11)
          .fontColor('#7B8794')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
        Text((this.entry.direction === 'income' ? '+' : '−') + formatMoney(this.entry.amountFen))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(accountingTypeOf(this.entry) === 'credit-repayment' ? '#52606D' :
            this.entry.direction === 'income' ? '#16845B' : this.expenseColor);
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
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

  private metadataText(): string {
    const dateText = this.showFullDate ?
      (this.entry.hasTime ? formatDateTime(this.entry.happenedAt) : formatDateOnly(this.entry.happenedAt)) :
      (this.entry.hasTime ? formatDateTime(this.entry.happenedAt).slice(11) : '');
    const timeSeparator = dateText.length > 0 ? ' · ' : '';
    const type = accountingTypeOf(this.entry);
    const typeText = type === 'normal' ? '' : accountingTypeLabel(type) + ' · ';
    return dateText + timeSeparator + typeText + this.entry.category + ' · ' + this.sourceLabel;
  }
}
