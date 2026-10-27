import { LedgerEntry, accountingTypeOf, formatDateOnly, formatMoney } from '../../model/LedgerModels';
import { LedgerEntryCard } from '../../components/LedgerEntryCard';
import {
  LedgerStatistics,
  StatisticsPeriod,
  StatisticsTrendItem,
  buildLedgerStatistics,
  previousStatisticsRange,
  statisticsRange
} from '../../services/LedgerStatistics';
import { StatisticsDirection, StatisticsRankType } from '../../components/statistics/StatisticsRanking';
import { StatisticsOverview } from '../../components/statistics/StatisticsOverview';
import { StatisticsTrend } from '../../components/statistics/StatisticsTrend';
import { StatisticsRanking } from '../../components/statistics/StatisticsRanking';

type StatisticsDetailSort = 'time' | 'amount';

@Component
export struct StatisticsView {
  @Watch('onEntriesChanged')
  @Prop entries: LedgerEntry[] = [];
  @Prop cycleStartDay: number = 15;
  @Link selectedRankValue: string;
  onBack: () => void = () => {};
  onEditEntry: (entry: LedgerEntry) => void = (_entry: LedgerEntry) => {};
  onDeleteRequest: (entry: LedgerEntry) => void = (_entry: LedgerEntry) => {};

  @State private period: StatisticsPeriod = 'month';
  @State private cursor: number = Date.now();
  @State private customStart: number = new Date(new Date().getFullYear(), new Date().getMonth(), 1).getTime();
  @State private customEnd: number = new Date().getTime();
  @State private selectedRankType: StatisticsRankType = 'category';
  @State private selectedRangeStart: number = 0;
  @State private selectedRangeEndExclusive: number = 0;
  @State private detailSort: StatisticsDetailSort = 'time';
  @State private detailSortDescending: boolean = true;
  @State private detailRefreshKey: number = 0;
  @State private rankDirection: StatisticsDirection = 'expense';
  @State private overviewScrollOffset: number = 0;
  @State private restoreOverviewScrollOnAppear: boolean = false;
  @State private resetOverviewScrollOnAppear: boolean = false;
  @State private scrollViewportHeight: number = 0;
  @State private statistics: LedgerStatistics = {
    incomeFen: 0,
    expenseFen: 0,
    netFen: 0,
    creditCardFen: 0,
    creditRepaymentFen: 0,
    entryCount: 0,
    trend: [],
    categories: [],
    merchants: [],
    sources: [],
    incomeCategories: [],
    incomeMerchants: [],
    incomeSources: []
  };
  @State private previousStatistics: LedgerStatistics = {
    incomeFen: 0,
    expenseFen: 0,
    netFen: 0,
    creditCardFen: 0,
    creditRepaymentFen: 0,
    entryCount: 0,
    trend: [],
    categories: [],
    merchants: [],
    sources: [],
    incomeCategories: [],
    incomeMerchants: [],
    incomeSources: []
  };
  @State private statisticsRefreshKey: number = 0;
  @State private selectedTrendKey: string = '';

  private overviewScroller: Scroller = new Scroller();
  private detailScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.resetOverviewScrollOnAppear = true;
    this.refreshStatistics();
  }

  private onEntriesChanged(): void {
    this.refreshStatistics();
    if (this.selectedRankValue.length > 0) {
      this.detailRefreshKey++;
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => {
            if (this.selectedRankValue.length > 0) {
              this.selectedRankValue = '';
            } else {
              this.onBack();
            }
          });
        Blank();
        Text(this.selectedRankValue.length > 0 ?
          (this.rankDirection === 'income' ? '收入 · ' : '支出 · ') + this.selectedRankName() + '账目' : '收支统计')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
        Blank();
        Blank().width(48);
      }
      .width('100%')
      .padding(18);

      if (this.selectedRankValue.length > 0) {
        Scroll(this.detailScroller) {
          Column({ space: 12 }) {
            this.rankEntriesContent();
          }
          .width('100%')
          .constraintSize({ minHeight: this.scrollViewportHeight })
          .justifyContent(FlexAlign.Start)
          .padding({ left: 18, right: 18, bottom: 24 });
        }
        .layoutWeight(1)
        .onAreaChange((oldArea, newArea) => {
          if (typeof newArea.height === 'number' && newArea.height > 0 &&
            this.scrollViewportHeight !== newArea.height) {
            this.scrollViewportHeight = newArea.height;
          }
        })
        .onAppear(() => {
          this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
        });
      } else {
        Scroll(this.overviewScroller) {
          Column() {
            ForEach([this.statisticsRefreshKey], (refreshKey: number) => {
              Column({ space: 12 }) {
                this.statisticsContent();
              }
              .width('100%');
            }, (refreshKey: number) => refreshKey.toString());
          }
          .width('100%')
          .constraintSize({ minHeight: this.scrollViewportHeight })
          .justifyContent(FlexAlign.Start)
          .padding({ left: 18, right: 18, bottom: 24 });
        }
        .layoutWeight(1)
        .onAreaChange((oldArea, newArea) => {
          if (typeof newArea.height === 'number' && newArea.height > 0 &&
            this.scrollViewportHeight !== newArea.height) {
            this.scrollViewportHeight = newArea.height;
          }
        })
        .onAppear(() => {
          if (this.resetOverviewScrollOnAppear) {
            this.overviewScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
            this.resetOverviewScrollOnAppear = false;
            this.restoreOverviewScrollOnAppear = false;
          } else if (this.restoreOverviewScrollOnAppear) {
            this.overviewScroller.scrollTo({
              xOffset: 0,
              yOffset: this.overviewScrollOffset,
              animation: false
            });
            this.restoreOverviewScrollOnAppear = false;
          }
        });
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private statisticsContent() {
    this.periodSelector();
    this.rangeSelector();
    if (this.statistics.entryCount === 0) {
      Text('所选期间没有账目，统计将在添加账目后显示。')
        .width('100%')
        .padding(12)
        .fontSize(13)
        .fontColor('#7B8794')
        .backgroundColor('#FFFFFF')
        .borderRadius(12);
    }
    StatisticsOverview({
      currentStatistics: this.statistics,
      previousStatistics: this.previousStatistics
    });
    StatisticsTrend({
      statistics: this.statistics,
      maximumAmountFen: this.maximumTrendAmount(),
      selectedSummary: this.selectedTrendSummary(),
      onSelectTrend: (key: string) => {
        this.selectedTrendKey = key;
      }
    });
    StatisticsRanking({
      statistics: this.statistics,
      rankDirection: this.rankDirection,
      sourceName: (source: string) => this.sourceName(source),
      onDirectionChange: (direction: StatisticsDirection) => {
        this.rankDirection = direction;
        this.statisticsRefreshKey++;
      },
      onSelectRank: (rankType: StatisticsRankType, value: string) => this.openRank(rankType, value)
    });
  }

  @Builder
  private periodSelector() {
    Row({ space: 8 }) {
      this.periodButton('月', 'month');
      this.periodButton('年', 'year');
      this.periodButton('自定义', 'custom');
    }
    .width('100%');
  }

  @Builder
  private periodButton(label: string, period: StatisticsPeriod) {
    Button(label)
      .layoutWeight(1)
      .backgroundColor(this.period === period ? '#2857C5' : '#FFFFFF')
      .fontColor(this.period === period ? '#FFFFFF' : '#344563')
      .onClick(() => {
        this.period = period;
        this.refreshStatistics();
      });
  }

  @Builder
  private rangeSelector() {
    if (this.period === 'custom') {
      Row({ space: 8 }) {
        Button('开始：' + formatDateOnly(this.customStart))
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.chooseCustomDate(true));
        Text('至')
          .fontSize(13)
          .fontColor('#7B8794');
        Button('结束：' + formatDateOnly(this.customEnd))
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.chooseCustomDate(false));
      }
      .width('100%');
    } else {
      Row() {
        Button('‹')
          .width(42)
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.movePeriod(-1));
        Blank();
        Text(this.period === 'month' ? this.monthLabel() : new Date(this.cursor).getFullYear() + '年')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172B4D');
        Blank();
        Button('›')
          .width(42)
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.movePeriod(1));
      }
      .width('100%');
    }
  }

  @Builder
  private rankEntriesContent() {
    Text(this.rankRangeLabel())
      .fontSize(12)
      .fontColor('#7B8794');
    if (this.rankEntries().length > 0) {
      Text('短按编辑 · 长按删除')
        .fontSize(11)
        .fontColor('#7B8794');
    }
    Row({ space: 8 }) {
      Text(this.rankEntries().length + ' 笔')
        .fontSize(13)
        .fontColor('#52606D');
      Blank();
      this.detailSortButton('time');
      this.detailSortButton('amount');
    }
    .width('100%');
    if (this.rankEntries().length === 0) {
      Text('所选期间没有对应账目')
        .width('100%')
        .padding(16)
        .fontSize(13)
        .fontColor('#7B8794')
        .backgroundColor('#FFFFFF')
        .borderRadius(12);
    } else {
      ForEach([this.detailRefreshKey], (refreshKey: number) => {
        ForEach(this.rankEntries(), (entry: LedgerEntry) => {
          LedgerEntryCard({
            entry: entry,
            sourceLabel: this.sourceName(entry.source),
            showFullDate: true,
            onEdit: (selectedEntry: LedgerEntry) => this.onEditEntry(selectedEntry),
            onDeleteRequest: (selectedEntry: LedgerEntry) => this.onDeleteRequest(selectedEntry)
          });
        }, (entry: LedgerEntry) => entry.id);
      }, (refreshKey: number) => refreshKey.toString());
    }
  }

  @Builder
  private detailSortButton(sort: StatisticsDetailSort) {
    Button(this.detailSortLabel(sort))
      .backgroundColor(this.detailSort === sort ? '#2857C5' : '#FFFFFF')
      .fontColor(this.detailSort === sort ? '#FFFFFF' : '#344563')
      .onClick(() => this.setDetailSort(sort));
  }

  private monthLabel(): string {
    if (this.cycleStartDay === 1) {
      const date = new Date(this.cursor);
      return date.getFullYear() + '年' + (date.getMonth() + 1) + '月';
    }
    const range = statisticsRange('month', this.cursor, this.customStart, this.customEnd, this.cycleStartDay);
    const start = new Date(range.start);
    const end = new Date(range.endExclusive - 24 * 60 * 60 * 1000);
    const endYear = start.getFullYear() === end.getFullYear() ? '' : end.getFullYear() + '年';
    return start.getFullYear() + '年' + (start.getMonth() + 1) + '月' + start.getDate() +
      '日—' + endYear + (end.getMonth() + 1) + '月' + end.getDate() + '日';
  }

  private selectedRankName(): string {
    return this.selectedRankType === 'source' ? this.sourceName(this.selectedRankValue) : this.selectedRankValue;
  }

  private openRank(rankType: StatisticsRankType, value: string): void {
    this.overviewScrollOffset = Math.max(0, this.overviewScroller.currentOffset().yOffset);
    this.restoreOverviewScrollOnAppear = true;
    const range = statisticsRange(this.period, this.cursor, this.customStart, this.customEnd, this.cycleStartDay);
    this.selectedRangeStart = range.start;
    this.selectedRangeEndExclusive = range.endExclusive;
    this.selectedRankType = rankType;
    this.selectedRankValue = value;
    this.detailSort = 'time';
    this.detailSortDescending = true;
    this.detailRefreshKey++;
  }

  private rankEntries(): LedgerEntry[] {
    const filtered = this.entries.filter((entry: LedgerEntry) => {
      if (accountingTypeOf(entry) === 'credit-repayment') {
        return false;
      }
      if (entry.direction !== this.rankDirection || entry.happenedAt < this.selectedRangeStart ||
        entry.happenedAt >= this.selectedRangeEndExclusive) {
        return false;
      }
      if (this.selectedRankType === 'category') {
        return (entry.category.trim().length > 0 ? entry.category.trim() : '其他') === this.selectedRankValue;
      }
      if (this.selectedRankType === 'merchant') {
        return (entry.merchant.trim().length > 0 ? entry.merchant.trim() : '未填写商户') === this.selectedRankValue;
      }
      return entry.source === this.selectedRankValue;
    });
    return filtered.sort((left: LedgerEntry, right: LedgerEntry) => {
      const primary = this.detailSort === 'time' ?
        left.happenedAt - right.happenedAt : left.amountFen - right.amountFen;
      if (primary !== 0) {
        return this.detailSortDescending ? -primary : primary;
      }
      return right.happenedAt - left.happenedAt;
    });
  }

  private rankRangeLabel(): string {
    const endDate = new Date(this.selectedRangeEndExclusive);
    const end = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate() - 1).getTime();
    return formatDateOnly(this.selectedRangeStart) + ' 至 ' + formatDateOnly(end);
  }

  private detailSortLabel(sort: StatisticsDetailSort): string {
    const label = sort === 'time' ? '时间' : '金额';
    if (this.detailSort !== sort) {
      return label;
    }
    return label + (this.detailSortDescending ? ' ↓' : ' ↑');
  }

  private setDetailSort(sort: StatisticsDetailSort): void {
    if (this.detailSort === sort) {
      this.detailSortDescending = !this.detailSortDescending;
    } else {
      this.detailSort = sort;
      this.detailSortDescending = true;
    }
    this.detailRefreshKey++;
  }

  private refreshStatistics(): void {
    const range = statisticsRange(this.period, this.cursor, this.customStart, this.customEnd, this.cycleStartDay);
    const previousRange = previousStatisticsRange(range, this.period, this.cycleStartDay);
    this.statistics = buildLedgerStatistics(this.entries, range, this.period);
    this.previousStatistics = buildLedgerStatistics(this.entries, previousRange, this.period);
    this.selectedTrendKey = '';
    this.statisticsRefreshKey++;
  }

  private movePeriod(amount: number): void {
    const date = new Date(this.cursor);
    this.cursor = this.period === 'year' ?
      new Date(date.getFullYear() + amount, 0, 1).getTime() :
      new Date(date.getFullYear(), date.getMonth() + amount, 1).getTime();
    this.refreshStatistics();
  }

  private chooseCustomDate(startDate: boolean): void {
    const selectedDate = startDate ? this.customStart : this.customEnd;
    const uiContext = this.getUIContext();
    uiContext.showDatePickerDialog({
      start: startDate ? new Date(1900, 0, 31) : new Date(this.customStart),
      end: startDate ? new Date(this.customEnd) : new Date(2100, 11, 31),
      selected: new Date(selectedDate),
      lunar: false,
      onDateAccept: (date: Date) => {
        const value = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        uiContext.runScopedTask(() => {
          if (startDate) {
            this.customStart = value;
          } else {
            this.customEnd = value;
          }
          this.refreshStatistics();
        });
      }
    });
  }

  private maximumTrendAmount(): number {
    let maximum = 0;
    this.statistics.trend.forEach((item: StatisticsTrendItem) => {
      maximum = Math.max(maximum, item.incomeFen, item.expenseFen);
    });
    return maximum;
  }

  private selectedTrendSummary(): string {
    for (const item of this.statistics.trend) {
      if (item.key === this.selectedTrendKey) {
        return item.label + ' · 收入 ' + formatMoney(item.incomeFen) + ' · 支出 ' + formatMoney(item.expenseFen);
      }
    }
    return '';
  }

  private sourceName(source: string): string {
    if (source === 'wechat') {
      return '微信支付';
    }
    if (source === 'alipay') {
      return '支付宝';
    }
    if (source === 'icbc') {
      return '工商银行';
    }
    if (source === 'citic') {
      return '中信银行';
    }
    return source === 'manual' ? '手动记账' : source;
  }
}
