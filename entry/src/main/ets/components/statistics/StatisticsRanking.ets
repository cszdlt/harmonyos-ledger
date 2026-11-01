import {
  LedgerStatistics,
  StatisticsExpenseScope,
  StatisticsRankItem
} from '../../services/LedgerStatistics';
import { formatMoney } from '../../model/LedgerModels';

export type StatisticsRankType = 'category' | 'merchant' | 'source';
export type StatisticsDirection = 'income' | 'expense';

@Component
export struct StatisticsRanking {
  @Prop statistics: LedgerStatistics;
  @Prop rankDirection: StatisticsDirection = 'expense';
  @Prop expenseScope: StatisticsExpenseScope = 'all';
  @State private expandedRankType: StatisticsRankType | '' = '';
  sourceName: (source: string) => string = (source: string) => source;
  onDirectionChange: (direction: StatisticsDirection) => void = (_direction: StatisticsDirection) => {};
  onExpenseScopeChange: (scope: StatisticsExpenseScope) => void = (_scope: StatisticsExpenseScope) => {};
  onSelectRank: (type: StatisticsRankType, value: string, scope: StatisticsExpenseScope) => void =
    (_type: StatisticsRankType, _value: string, _scope: StatisticsExpenseScope) => {};

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button('支出分析')
          .layoutWeight(1)
          .backgroundColor(this.rankDirection === 'expense' ? '#2857C5' : '#FFFFFF')
          .fontColor(this.rankDirection === 'expense' ? '#FFFFFF' : '#344563')
          .onClick(() => this.onDirectionChange('expense'));
        Button('收入分析')
          .layoutWeight(1)
          .backgroundColor(this.rankDirection === 'income' ? '#2857C5' : '#FFFFFF')
          .fontColor(this.rankDirection === 'income' ? '#FFFFFF' : '#344563')
          .onClick(() => this.onDirectionChange('income'));
      }
      .width('100%');
      if (this.rankDirection === 'expense') {
        Row({ space: 6 }) {
          this.scopeButton('全部支出', 'all');
          this.scopeButton('固定开销', 'fixed');
          this.scopeButton('非固定支出', 'nonFixed');
        }
        .width('100%');
      }
      this.rankingCard(this.rankDirection === 'income' ? '收入分类' : this.expenseTitle('分类'),
        this.selectedItems('category'), this.totalAmountFen(), 'category');
      this.rankingCard(this.rankDirection === 'income' ? '收入商户' : this.expenseTitle('商户'),
        this.selectedItems('merchant'), this.totalAmountFen(), 'merchant');
      this.rankingCard(this.rankDirection === 'income' ? '收入来源' : this.expenseTitle('来源'),
        this.selectedItems('source'), this.totalAmountFen(), 'source');
    }
    .width('100%');
  }

  @Builder
  private scopeButton(label: string, scope: StatisticsExpenseScope) {
    Button(label)
      .layoutWeight(1)
      .height(32)
      .fontSize(11)
      .backgroundColor(this.expenseScope === scope ? '#E8EEFF' : '#FFFFFF')
      .fontColor(this.expenseScope === scope ? '#2857C5' : '#344563')
      .onClick(() => this.onExpenseScopeChange(scope));
  }

  @Builder
  private rankingCard(title: string, items: StatisticsRankItem[], total: number, rankType: StatisticsRankType) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172B4D');
      if (items.length === 0) {
        Text(this.emptyLabel())
          .fontSize(13)
          .fontColor('#7B8794');
      } else {
        ForEach(this.visibleRankItems(items, rankType), (item: StatisticsRankItem) => {
          this.rankingItem(item, total, rankType);
        }, (item: StatisticsRankItem) => this.rankDirection + ':' + this.expenseScope + ':' + item.key);
        if (items.length > 5) {
          Button(this.expandedRankType === rankType ? '收起' : '展开全部 ' + items.length + ' 项')
            .width('100%')
            .height(32)
            .backgroundColor('#F6F7F9')
            .fontColor('#2857C5')
            .onClick(() => {
              this.expandedRankType = this.expandedRankType === rankType ? '' : rankType;
            });
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
  }

  @Builder
  private rankingItem(item: StatisticsRankItem, total: number, rankType: StatisticsRankType) {
    Column({ space: 5 }) {
      Row() {
        Column({ space: 2 }) {
          Text(rankType === 'source' ? this.sourceName(item.key) : item.label)
            .fontSize(13)
            .fontColor('#344563');
          Text('查看账目 ›')
            .fontSize(10)
            .fontColor('#2457C5');
          Text(item.count + ' 笔')
            .fontSize(10)
            .fontColor('#7B8794');
        }
        .alignItems(HorizontalAlign.Start);
        Blank();
        Text(formatMoney(item.amountFen))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172B4D');
      }
      .width('100%');
      Row() {
        Row()
          .width(this.barWidth(item.amountFen, total))
          .height(6)
          .backgroundColor('#5979D0')
          .borderRadius(3);
      }
      .width('100%')
      .height(6)
      .backgroundColor('#EEF1F4')
      .borderRadius(3);
      Text(total > 0 ? (item.amountFen * 100 / total).toFixed(1) + '%' : '0.0%')
        .fontSize(10)
        .fontColor('#7B8794');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 3, bottom: 5 })
    .onClick(() => this.onSelectRank(rankType, item.key,
      this.rankDirection === 'expense' ? this.expenseScope : 'all'));
  }

  private selectedItems(rankType: StatisticsRankType): StatisticsRankItem[] {
    if (this.rankDirection === 'income') {
      if (rankType === 'category') {
        return this.statistics.incomeCategories;
      }
      return rankType === 'merchant' ? this.statistics.incomeMerchants : this.statistics.incomeSources;
    }
    if (this.expenseScope === 'fixed') {
      if (rankType === 'category') {
        return this.statistics.fixedCategories;
      }
      return rankType === 'merchant' ? this.statistics.fixedMerchants : this.statistics.fixedSources;
    }
    if (this.expenseScope === 'nonFixed') {
      if (rankType === 'category') {
        return this.statistics.nonFixedCategories;
      }
      return rankType === 'merchant' ? this.statistics.nonFixedMerchants : this.statistics.nonFixedSources;
    }
    if (rankType === 'category') {
      return this.statistics.categories;
    }
    return rankType === 'merchant' ? this.statistics.merchants : this.statistics.sources;
  }

  private visibleRankItems(items: StatisticsRankItem[], rankType: StatisticsRankType): StatisticsRankItem[] {
    if (this.expandedRankType === rankType || items.length <= 5) {
      return items;
    }
    if (rankType !== 'category') {
      return items.slice(0, 5);
    }
    const otherIndex = items.findIndex((item: StatisticsRankItem) => item.key === '其他');
    if (otherIndex < 0 || otherIndex < 5) {
      return items.slice(0, 5);
    }
    const visible = items.slice(0, 4);
    visible.push(items[otherIndex]);
    return visible.sort((left: StatisticsRankItem, right: StatisticsRankItem) =>
      right.amountFen - left.amountFen);
  }

  private totalAmountFen(): number {
    if (this.rankDirection === 'income') {
      return this.statistics.incomeFen;
    }
    if (this.expenseScope === 'fixed') {
      return this.statistics.fixedExpenseFen;
    }
    if (this.expenseScope === 'nonFixed') {
      return this.statistics.nonFixedExpenseFen;
    }
    return this.statistics.expenseFen;
  }

  private expenseTitle(kind: string): string {
    if (this.expenseScope === 'fixed') {
      return '固定开销' + kind;
    }
    if (this.expenseScope === 'nonFixed') {
      return '非固定支出' + kind;
    }
    return '支出' + kind;
  }

  private emptyLabel(): string {
    if (this.rankDirection === 'income') {
      return '暂无收入数据';
    }
    if (this.expenseScope === 'fixed') {
      return '暂无固定开销数据';
    }
    if (this.expenseScope === 'nonFixed') {
      return '暂无非固定支出数据';
    }
    return '暂无支出数据';
  }

  private barWidth(value: number, maximum: number): string {
    if (value <= 0 || maximum <= 0) {
      return '0%';
    }
    return Math.max(2, value * 100 / maximum).toFixed(1) + '%';
  }
}
