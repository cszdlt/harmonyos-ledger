import { filterNotificationSources } from '../../model/NotificationArchiveModels';
import type { NotificationArchiveEntry, NotificationSource } from '../../model/NotificationArchiveModels';
import { NotificationArchiveRow } from './NotificationArchiveRow';

@Component
export struct NotificationRuleSamplePicker {
  @Prop sources: NotificationSource[] = [];
  @Prop entries: NotificationArchiveEntry[] = [];
  @Prop bundleName: string = '';
  @Prop selectedIds: number[] = [];
  @Prop loading: boolean = false;
  @Prop hasMore: boolean = false;
  @Prop message: string = '';
  @State private sourcePickerOpen: boolean = false;
  @State private sourceSearch: string = '';
  onSelectSource: (bundleName: string) => void = (_bundleName: string) => {};
  onToggle: (entry: NotificationArchiveEntry) => void = (_entry: NotificationArchiveEntry) => {};
  onLoadMore: () => void = () => {};
  onDone: () => void = () => {};

  aboutToAppear(): void {
    this.sourcePickerOpen = this.bundleName.length === 0;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 12 }) {
        Row() {
          Text('选择通知样例').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#172B4D');
          Blank();
          Button('完成选择（' + this.selectedIds.length + '）').onClick(() => this.onDone());
        }.width('100%');
        Button(this.bundleName.length > 0 ? '来源：' + this.bundleName : '选择应用包名')
          .width('100%').backgroundColor('#E9F1FF').fontColor('#2457C5')
          .onClick(() => { this.sourceSearch = ''; this.sourcePickerOpen = true; });
        Text('勾选同一应用的多条交易通知。切换包名会清空已选样例，返回后需逐条确认交易字段。')
          .fontSize(12).fontColor('#52606D');
        if (this.message.length > 0) {
          Text(this.message).fontSize(13).fontColor('#B42318');
        }
        List({ space: 10 }) {
          ForEach(this.entries, (entry: NotificationArchiveEntry) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(this.selectedIds.includes(entry.id) ? '✓ 已选择' : '点击选择此通知')
                  .fontColor(this.selectedIds.includes(entry.id) ? '#16845B' : '#52606D').fontSize(13);
                NotificationArchiveRow({ entry: entry, onSelect: () => this.onToggle(entry) });
              }
              .width('100%').padding(8)
              .border({ width: 1, color: this.selectedIds.includes(entry.id) ? '#16845B' : '#DFE3E8' })
              .borderRadius(12);
            }
          }, (entry: NotificationArchiveEntry) => entry.id.toString());
          if (this.loading) {
            ListItem() { Text('正在读取通知…').fontSize(13).fontColor('#52606D'); }
          } else if (this.bundleName.length > 0 && this.entries.length === 0) {
            ListItem() { Text('该应用暂无通知，请返回手动填写或选择其他来源。').fontSize(13); }
          }
          if (!this.loading && this.hasMore) {
            ListItem() {
              Button('加载更多通知').width('100%').onClick(() => this.onLoadMore());
            }
          }
        }.layoutWeight(1).width('100%');
      }
      .width('100%').height('100%').padding(18).alignItems(HorizontalAlign.Start);
      if (this.sourcePickerOpen) { this.sourcePicker(); }
    }.width('100%').height('100%');
  }

  @Builder
  private sourcePicker() {
    Column() {
      Column({ space: 14 }) {
        Row() {
          Text('选择通知来源').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#172B4D');
          Blank();
          Button('关闭').onClick(() => { this.sourcePickerOpen = false; });
        }.width('100%');
        TextInput({ text: this.sourceSearch, placeholder: '搜索应用名称或包名' })
          .height(48).backgroundColor('#F4F6F8').borderRadius(12)
          .onChange((value: string) => { this.sourceSearch = value; });
        List({ space: 8 }) {
          ForEach(filterNotificationSources(this.sources, this.sourceSearch), (source: NotificationSource) => {
            ListItem() {
              Button() {
                Column({ space: 4 }) {
                  Text(source.appName || source.bundleName).fontSize(15).fontColor('#172B4D');
                  Text(source.bundleName).fontSize(12).fontColor('#52606D');
                }.width('100%').alignItems(HorizontalAlign.Start);
              }
              .width('100%').padding(14).borderRadius(12)
              .backgroundColor(source.bundleName === this.bundleName ? '#EEF4FF' : '#F7F8FA')
              .onClick(() => {
                this.sourcePickerOpen = false;
                this.onSelectSource(source.bundleName);
              });
            }
          }, (source: NotificationSource) => source.bundleName);
          if (filterNotificationSources(this.sources, this.sourceSearch).length === 0) {
            ListItem() {
              Text(this.sources.length === 0 ? '还没有通知来源，可返回手动填写样例。' : '没有找到匹配的应用')
                .fontSize(13).fontColor('#52606D');
            }
          }
        }.layoutWeight(1);
      }
      .width('100%').height('78%').padding(18).backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 24, topRight: 24 });
    }
    .width('100%').height('100%').justifyContent(FlexAlign.End).backgroundColor('#66000000');
  }
}
