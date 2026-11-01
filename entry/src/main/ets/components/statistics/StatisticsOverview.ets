import { LedgerStatistics } from '../../services/LedgerStatistics';
import { formatMoney } from '../../model/LedgerModels';

@Component
export struct StatisticsOverview {
  @Prop currentStatistics: LedgerStatistics;
  @Prop previousStatistics: LedgerStatistics;

  build() {
    Column({ space: 10 }) {
      Text('收支概览')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172B4D');
      Row({ space: 8 }) {
        this.metricCard('收入', formatMoney(this.currentStatistics.incomeFen),
          this.moneyChange(this.currentStatistics.incomeFen, this.previousStatistics.incomeFen), '#16845B');
        this.metricCard('总支出', formatMoney(this.currentStatistics.expenseFen),
          this.moneyChange(this.currentStatistics.expenseFen, this.previousStatistics.expenseFen), '#B54747');
      }
      .width('100%');
      Row({ space: 8 }) {
        this.metricCard('固定开销', formatMoney(this.currentStatistics.fixedExpenseFen),
          this.moneyChange(this.currentStatistics.fixedExpenseFen, this.previousStatistics.fixedExpenseFen), '#B54747',
          '占支出 ' + this.expenseShare(this.currentStatistics.fixedExpenseFen, this.currentStatistics.expenseFen));
        this.metricCard('非固定支出', formatMoney(this.currentStatistics.nonFixedExpenseFen),
          this.moneyChange(this.currentStatistics.nonFixedExpenseFen, this.previousStatistics.nonFixedExpenseFen),
          '#B54747', '占支出 ' + this.expenseShare(this.currentStatistics.nonFixedExpenseFen,
            this.currentStatistics.expenseFen));
      }
      .width('100%');
      Row({ space: 8 }) {
        this.metricCard('本期现金结余', this.signedMoney(this.currentStatistics.netFen),
          this.moneyChange(this.currentStatistics.netFen, this.previousStatistics.netFen), '#2457C5');
        this.metricCard('笔数', this.currentStatistics.entryCount + ' 笔',
          this.countChange(this.currentStatistics.entryCount, this.previousStatistics.entryCount), '#52606D');
      }
      .width('100%');
      Row({ space: 8 }) {
        this.metricCard('其中信用卡消费', formatMoney(this.currentStatistics.creditCardFen),
          this.moneyChange(this.currentStatistics.creditCardFen, this.previousStatistics.creditCardFen), '#2457C5');
        this.metricCard('信用卡还款', formatMoney(this.currentStatistics.creditRepaymentFen),
          this.moneyChange(this.currentStatistics.creditRepaymentFen, this.previousStatistics.creditRepaymentFen), '#52606D');
      }
      .width('100%');
      Text('现金结余＝收入－支出＋信用卡消费－信用卡还款；与上一周期对比')
        .fontSize(11)
        .fontColor('#7B8794');
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
  }

  @Builder
  private metricCard(label: string, value: string, change: string, color: string, detail: string = '') {
    Column({ space: 5 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#7B8794');
      Text(value)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(color);
      if (detail.length > 0) {
        Text(detail)
          .fontSize(10)
          .fontColor('#7B8794');
      }
      Text(change)
        .fontSize(10)
        .fontColor('#7B8794');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(10)
    .backgroundColor('#F6F7F9')
    .borderRadius(10);
  }

  private expenseShare(amount: number, total: number): string {
    return (total > 0 ? (amount * 100 / total).toFixed(1) : '0.0') + '%';
  }

  private signedMoney(amountFen: number): string {
    const sign = amountFen > 0 ? '+' : amountFen < 0 ? '−' : '';
    return sign + formatMoney(Math.abs(amountFen));
  }

  private moneyChange(current: number, previous: number): string {
    const change = current - previous;
    const sign = change > 0 ? '+' : change < 0 ? '−' : '';
    const amount = sign + formatMoney(Math.abs(change));
    if (previous === 0) {
      return '较上期 ' + amount + '（上期为0）';
    }
    const percentSign = change > 0 ? '+' : change < 0 ? '−' : '';
    const percent = (Math.abs(change) * 100 / Math.abs(previous)).toFixed(1);
    return '较上期 ' + amount + '（' + percentSign + percent + '%）';
  }

  private countChange(current: number, previous: number): string {
    const change = current - previous;
    const sign = change > 0 ? '+' : change < 0 ? '−' : '';
    if (previous === 0) {
      return '较上期 ' + sign + change + ' 笔（上期为0）';
    }
    const percentSign = change > 0 ? '+' : change < 0 ? '−' : '';
    const percent = (Math.abs(change) * 100 / previous).toFixed(1);
    return '较上期 ' + sign + Math.abs(change) + ' 笔（' + percentSign + percent + '%）';
  }
}
