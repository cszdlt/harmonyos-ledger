import { EntrySource, LedgerEntry, formatDateOnly, formatDateTime, formatMoney } from '../../model/LedgerModels';
import { LedgerEntryCard } from '../../components/LedgerEntryCard';
import { CycleStartDaySelector } from '../../components/settings/CycleStartDaySelector';
import type { LedgerDayGroup } from '../../services/LedgerHomeData';

@Component
export struct LedgerHomeView {
  @Prop entriesViewRevision: number = 0;
  @Prop monthEntries: LedgerEntry[] = [];
  @Prop dayGroups: LedgerDayGroup[] = [];
  @Prop incomeTotalFen: number = 0;
  @Prop expenseTotalFen: number = 0;
  @Prop monthLabel: string = '';
  @Prop cycleStartDay: number = 15;
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
  onCycleStartDayChange: (day: number) => void = (_day: number) => {};
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
                .fontColor('#172B4D');
              Text('只保存在这台设备')
                .fontSize(13)
                .fontColor('#7B8794');
            }
            Blank();
            CycleStartDaySelector({
              startDay: this.cycleStartDay,
              onChange: (day: number) => this.onCycleStartDayChange(day)
            });
            Button('设置')
              .backgroundColor('#E9F1FF')
              .fontColor('#2457C5')
              .onClick(() => {
                this.onOpenSettings();
              });
          }
          .width('100%');

          this.summaryCard();
          Row({ space: 10 }) {
            Button('识别账单截图')
              .layoutWeight(1)
              .backgroundColor('#FFFFFF')
              .fontColor('#2457C5')
              .onClick(() => this.onStartImport());
            Button('＋ 手动记账')
              .layoutWeight(1)
              .backgroundColor('#2457C5')
              .fontColor('#FFFFFF')
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
    .height('100%');
  }

  @Builder
  private summaryCard() {
    Column({ space: 14 }) {
      Text('本周期收支')
        .fontSize(14)
        .fontColor('#EAF0FF');
      Row() {
        Column({ space: 6 }) {
          Text('收入')
            .fontSize(13)
            .fontColor('#D7E2FF');
          Text(formatMoney(this.incomeTotalFen))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Column({ space: 6 }) {
          Text('支出')
            .fontSize(13)
            .fontColor('#D7E2FF');
          Text(formatMoney(this.expenseTotalFen))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%');
      Text('账目保存在本机，无需登录或联网')
        .fontSize(12)
        .fontColor('#D7E2FF');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(18)
    .backgroundColor('#2857C5')
    .borderRadius(18)
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
        .backgroundColor('#FFFFFF')
        .fontColor('#344563')
        .onClick(() => this.onPreviousMonth());
      Blank();
      Text(this.monthLabel)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#172B4D');
      Blank();
      Button('›')
        .width(42)
        .backgroundColor('#FFFFFF')
        .fontColor('#344563')
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
          .fontColor('#172B4D');
        Blank();
        Text(this.monthEntries.length > 0 ?
          '短按编辑 · 长按删除 · ' + this.monthEntries.length + ' 笔' : '0 笔')
          .fontSize(12)
          .fontColor('#7B8794');
      }
      .width('100%');

      if (this.monthEntries.length === 0) {
        Column({ space: 8 }) {
          Text('这个月还没有账目')
            .fontSize(15)
            .fontColor('#52606D');
          Text('可以手动记一笔')
            .fontSize(13)
            .fontColor('#7B8794');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);
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
          .fontColor('#344563');
        Blank();
        Text(group.entries.length + ' 笔')
          .fontSize(12)
          .fontColor('#7B8794');
      }
      .width('100%');
      Row({ space: 12 }) {
        if (group.expenseTotalFen > 0) {
          Text('支出 ' + formatMoney(group.expenseTotalFen))
            .fontSize(12)
            .fontColor('#B54747');
        }
        if (group.incomeTotalFen > 0) {
          Text('收入 ' + formatMoney(group.incomeTotalFen))
            .fontSize(12)
            .fontColor('#16845B');
        }
      }
      .width('100%');
      ForEach(group.entries, (entry: LedgerEntry) => {
        LedgerEntryCard({
          entry: entry,
          sourceLabel: this.sourceLabel(entry.source),
          expenseColor: '#B54747',
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
