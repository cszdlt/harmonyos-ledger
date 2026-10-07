import { NotificationSource } from '../../model/NotificationArchiveModels';
import { formatDateOnly } from '../../model/LedgerModels';

export type NotificationHistoryRange = 'all' | 'today' | '7days' | '30days' | 'custom';

@Component
export struct NotificationFilterBar {
  @Prop expanded: boolean = false;
  @Prop keywordInput: string = '';
  @Prop appliedKeyword: string = '';
  @Prop selectedSourceLabel: string = '全部来源';
  @Prop rangeLabel: string = '全部时间';
  @Prop range: NotificationHistoryRange = 'all';
  @Prop customStart: number = Date.now();
  @Prop customEnd: number = Date.now();
  @Prop filterSummary: string = '';
  @Prop activeFilterCount: number = 0;

  onKeywordChange: (value: string) => void = (_value: string) => {};
  onApplyKeyword: () => void = () => {};
  onToggleExpanded: () => void = () => {};
  onRefresh: () => void = () => {};
  onChooseSource: () => void = () => {};
  onChooseRange: () => void = () => {};
  onChooseStartDate: () => void = () => {};
  onChooseEndDate: () => void = () => {};
  onReset: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button(this.expanded ? '收起筛选' :
          '筛选与管理' + (this.activeFilterCount > 0 ? ' · ' + this.activeFilterCount : ''))
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onToggleExpanded());
        Button('刷新')
          .backgroundColor('#E9F1FF')
          .fontColor('#2457C5')
          .onClick(() => this.onRefresh());
      }
      .width('100%');

      if (this.activeFilterCount > 0) {
        Row({ space: 8 }) {
          Text(this.filterSummary)
            .layoutWeight(1)
            .fontSize(12)
            .fontColor('#52606D')
            .maxLines(2);
          Button('重置')
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => this.onReset());
        }
        .width('100%');
      }

      if (this.expanded) {
        Row({ space: 8 }) {
          TextInput({ text: this.keywordInput, placeholder: '搜索标题或正文' })
            .layoutWeight(1)
            .backgroundColor('#FFFFFF')
            .onChange((value: string) => this.onKeywordChange(value))
            .onSubmit(() => this.onApplyKeyword());
          Button('搜索')
            .backgroundColor('#2457C5')
            .fontColor('#FFFFFF')
            .onClick(() => this.onApplyKeyword());
        }
        .width('100%');

        if (this.keywordInput.trim() !== this.appliedKeyword) {
          Text('搜索词尚未应用，点击“搜索”后生效。')
            .fontSize(11)
            .fontColor('#8A4B08');
        }

        Button(this.selectedSourceLabel)
          .width('100%')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onChooseSource());
        Button('时间范围：' + this.rangeLabel)
          .width('100%')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onChooseRange());
        if (this.range === 'custom') {
          Row({ space: 8 }) {
            Button('开始：' + formatDateOnly(this.customStart))
              .layoutWeight(1)
              .backgroundColor('#FFFFFF')
              .fontColor('#344563')
              .onClick(() => this.onChooseStartDate());
            Button('结束：' + formatDateOnly(this.customEnd))
              .layoutWeight(1)
              .backgroundColor('#FFFFFF')
              .fontColor('#344563')
              .onClick(() => this.onChooseEndDate());
          }
          .width('100%');
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
