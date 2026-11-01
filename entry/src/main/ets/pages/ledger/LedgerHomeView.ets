import { EntrySource, LedgerEntry, formatMoney } from '../../model/LedgerModels';
import { AppTheme } from '../../model/AppTheme';
import { LedgerEntryCard } from '../../components/LedgerEntryCard';
import type { LedgerDayGroup } from '../../services/LedgerHomeData';

@Component
export struct LedgerHomeView {
  @Prop entriesViewRevision: number = 0;
  @Prop monthEntries: LedgerEntry[] = [];
  @Prop dayGroups: LedgerDayGroup[] = [];
  @Prop incomeTotalFen: number = 0;
  @Prop expenseTotalFen: number = 0;
  @Prop fixedExpenseTotalFen: number = 0;
  @Prop nonFixedExpenseTotalFen: number = 0;
  @Prop balanceTotalFen: number = 0;
  @Prop creditCardTotalFen: number = 0;
  @Prop monthLabel: string = '';
  @Prop scrollOffset: number = 0;
  @Prop restoreScrollOnAppear: boolean = false;

  private scroller: Scroller = new Scroller();
  @State private viewportHeight: number = 0;

  onSaveScroll: (offset: number) => void = (_offset: number) => {};
  onRestoreScrollComplete: () => void = () => {};
  onPreviousMonth: () => void = () => {};
  onNextMonth: () => void = () => {};
  onOpenStatistics: () => void = () => {};
  onStartImport: () => void = () => {};
  onOpenSettings: () => void = () => {};
  onAddEntry: () => void = () => {};
  onEditEntry: (entry: LedgerEntry) => void = (_entry: LedgerEntry) => {};
  onDeleteRequest: (entry: LedgerEntry) => void = (_entry: LedgerEntry) => {};
  sourceLabel: (source: EntrySource) => string = (_source: EntrySource) => '';

  build() {
    Column() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Row() {
            Column({ space: 4 }) {
              Text('通知记账')
                .fontSize(27)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.textPrimary);
              Text('只保存在这台设备')
                .fontSize(13)
                .fontColor(AppTheme.textMuted);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            Button('设置')
              .backgroundColor(AppTheme.brandPrimarySoft)
              .fontColor(AppTheme.brandText)
              .borderRadius(AppTheme.buttonRadius)
              .onClick(() => {
                this.onOpenSettings();
              });
          }
          .width('100%');

          this.summaryCard();
          Row({ space: 10 }) {
            Button('识别账单截图')
              .layoutWeight(1)
              .backgroundColor(AppTheme.surfaceCard)
              .fontColor(AppTheme.brandText)
              .border({ width: 1, color: AppTheme.brandPrimarySoft })
              .borderRadius(AppTheme.buttonRadius)
              .onClick(() => this.onStartImport());
            Button('＋ 手动记账')
              .layoutWeight(1)
              .backgroundColor(AppTheme.brandPrimary)
              .fontColor(AppTheme.surfaceCard)
              .borderRadius(AppTheme.buttonRadius)
              .onClick(() => {
                this.onSaveScroll(this.scroller.currentOffset().yOffset);
                this.onAddEntry();
              });
          }
          .width('100%');
          this.monthSelector();
          this.transactionList();
        }
        .width('100%')
        .constraintSize({ minHeight: this.viewportHeight })
        .justifyContent(FlexAlign.Start)
        .padding({ left: 18, right: 18, top: 18, bottom: 24 });
      }
      .layoutWeight(1)
      .onAreaChange((oldArea, newArea) => {
        if (typeof newArea.height === 'number' && newArea.height > 0 &&
          this.viewportHeight !== newArea.height) {
          this.viewportHeight = newArea.height;
        }
      })
      .onAppear(() => {
        if (this.restoreScrollOnAppear) {
          this.scroller.scrollTo({
            xOffset: 0,
            yOffset: this.scrollOffset,
            animation: false
          });
          this.onRestoreScrollComplete();
        }
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.pageBackground);
  }

  @Builder
  private summaryCard() {
    Column({ space: 14 }) {
      Row() {
        Text('本周期收支')
          .fontSize(14)
          .fontColor(AppTheme.summaryHint);
        Blank();
        Text('查看统计 ›')
          .fontSize(12)
          .fontColor(AppTheme.summaryHint);
      }
      .width('100%');
      Row() {
        Column({ space: 6 }) {
          Text('收入')
            .fontSize(13)
            .fontColor(AppTheme.summaryLabel);
          Text(formatMoney(this.incomeTotalFen))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.surfaceCard);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Column({ space: 6 }) {
          Text('非固定支出')
            .fontSize(13)
            .fontColor(AppTheme.summaryLabel);
          Text(formatMoney(this.nonFixedExpenseTotalFen))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.surfaceCard);
          Text('总支出 ' + formatMoney(this.expenseTotalFen))
            .fontSize(11)
            .fontColor(AppTheme.summaryLabel);
          Text('固定开销 ' + formatMoney(this.fixedExpenseTotalFen))
            .fontSize(11)
            .fontColor(AppTheme.summaryLabel);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%');
      Row() {
        Column({ space: 6 }) {
          Text('本期现金结余')
            .fontSize(13)
            .fontColor(AppTheme.summaryLabel);
          Text(formatMoney(this.balanceTotalFen))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.surfaceCard);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Column({ space: 6 }) {
          Text('其中信用卡消费')
            .fontSize(13)
            .fontColor(AppTheme.summaryLabel);
          Text(formatMoney(this.creditCardTotalFen))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.surfaceCard);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(18)
    .backgroundColor(AppTheme.brandPrimary)
    .borderRadius(AppTheme.cardRadiusLarge)
    .onClick(() => {
      this.onSaveScroll(this.scroller.currentOffset().yOffset);
      this.onOpenStatistics();
    });
  }

  @Builder
  private monthSelector() {
    Row() {
      Button('‹')
        .width(42)
        .backgroundColor(AppTheme.surfaceCard)
        .fontColor(AppTheme.textBody)
        .border({ width: 1, color: AppTheme.borderSubtle })
        .borderRadius(AppTheme.buttonRadius)
        .onClick(() => this.onPreviousMonth());
      Blank();
      Text(this.monthLabel)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.textPrimary);
      Blank();
      Button('›')
        .width(42)
        .backgroundColor(AppTheme.surfaceCard)
        .fontColor(AppTheme.textBody)
        .border({ width: 1, color: AppTheme.borderSubtle })
        .borderRadius(AppTheme.buttonRadius)
        .onClick(() => this.onNextMonth());
    }
    .width('100%');
  }

  @Builder
  private transactionList() {
    Column({ space: 10 }) {
      Row() {
        Text('账目明细')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.textPrimary);
        Blank();
        Text(this.monthEntries.length > 0 ?
          '短按编辑 · 长按操作 · ' + this.monthEntries.length + ' 笔' : '0 笔')
          .fontSize(12)
          .fontColor(AppTheme.textMuted);
      }
      .width('100%');

      if (this.monthEntries.length === 0) {
        Column({ space: 12 }) {
          Text('这个月还没有账目')
            .fontSize(15)
            .fontColor(AppTheme.textSecondary);
          Text('可以从截图识别或手动添加第一笔')
            .fontSize(13)
            .fontColor(AppTheme.textMuted);
          Row({ space: 10 }) {
            Button('识别账单截图')
              .layoutWeight(1)
              .backgroundColor(AppTheme.brandPrimarySoft)
              .fontColor(AppTheme.brandText)
              .borderRadius(AppTheme.buttonRadius)
              .onClick(() => this.onStartImport());
            Button('手动记账')
              .layoutWeight(1)
              .backgroundColor(AppTheme.brandPrimary)
              .fontColor(AppTheme.surfaceCard)
              .borderRadius(AppTheme.buttonRadius)
              .onClick(() => {
                this.onSaveScroll(this.scroller.currentOffset().yOffset);
                this.onAddEntry();
              });
          }
          .width('100%');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor(AppTheme.surfaceCard)
        .borderRadius(AppTheme.cardRadius);
      } else {
        ForEach(this.dayGroups, (group: LedgerDayGroup) => {
          this.entryDayGroup(group);
        }, (group: LedgerDayGroup) => group.dateKey + ':' + this.entriesViewRevision);
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private entryDayGroup(group: LedgerDayGroup) {
    Column({ space: 8 }) {
      Row() {
        Text(this.dayGroupLabel(group.dateKey))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.textBody);
        Blank();
        Text(group.entries.length + ' 笔')
          .fontSize(12)
          .fontColor(AppTheme.textMuted);
      }
      .width('100%');
      Row({ space: 12 }) {
        if (group.expenseTotalFen > 0) {
          Text('支出 ' + formatMoney(group.expenseTotalFen))
            .fontSize(12)
            .fontColor(AppTheme.expense);
        }
        if (group.incomeTotalFen > 0) {
          Text('收入 ' + formatMoney(group.incomeTotalFen))
            .fontSize(12)
            .fontColor(AppTheme.income);
        }
      }
      .width('100%');
      ForEach(group.entries, (entry: LedgerEntry) => {
        LedgerEntryCard({
          entry: entry,
          sourceLabel: this.sourceLabel(entry.source),
          expenseColor: AppTheme.expense,
          onEdit: (selectedEntry: LedgerEntry) => {
            this.onSaveScroll(this.scroller.currentOffset().yOffset);
            this.onEditEntry(selectedEntry);
          },
          onDeleteRequest: (selectedEntry: LedgerEntry) => this.onDeleteRequest(selectedEntry)
        });
      }, (entry: LedgerEntry) => entry.id);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  private dayGroupLabel(dateKey: string): string {
    const parts = dateKey.split('-');
    const date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return date.getMonth() + 1 + '月' + date.getDate() + '日 ' + weekdays[date.getDay()];
  }
}
