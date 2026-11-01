import type { NotificationSource } from '../../model/NotificationArchiveModels';

@Component
export struct NotificationSourcePicker {
  @Prop sources: NotificationSource[] = [];
  @Prop sourceCount: number = 0;
  @Prop query: string = '';
  @Prop selectedBundle: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  onSearch: (query: string) => void = () => {};
  onSelect: (bundleName: string) => void = () => {};
  onClose: () => void = () => {};
  onRefresh: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {}
        .width('100%').height('100%').backgroundColor('#66000000')
        .onClick(() => this.onClose());
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('选择通知来源').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#172B4D');
            Text('共 ' + this.sourceCount + ' 个应用').fontSize(12).fontColor('#7B8794');
          }.alignItems(HorizontalAlign.Start);
          Blank();
          Button('关闭').fontColor('#344563').backgroundColor('#F1F3F5')
            .onClick(() => this.onClose());
        }.width('100%');
        TextInput({ text: this.query, placeholder: '搜索应用名称或包名' })
          .height(48).backgroundColor('#F4F6F8').borderRadius(12)
          .onChange((query: string) => this.onSearch(query));
        if (this.loading) {
          Text('正在读取通知来源…').fontColor('#7B8794');
        } else if (this.error.length > 0) {
          Text(this.error).fontColor('#B54708').fontSize(13);
        } else {
          List({ space: 8 }) {
            if (this.sourceCount === 0) {
              ListItem() {
                Text('尚无通知来源，请先在通知访问授权中选择签到应用，并接收一条该应用通知。')
                  .fontSize(13).fontColor('#7B8794').padding(16);
              }
            } else if (this.sources.length === 0) {
              ListItem() {
                Text('没有找到匹配的应用').fontSize(13).fontColor('#7B8794').padding(16);
              }
            } else {
              ForEach(this.sources, (source: NotificationSource) => {
                ListItem() {
                  Button() {
                    Row({ space: 12 }) {
                      Column({ space: 4 }) {
                        Text(source.appName.length > 0 ? source.appName : source.bundleName)
                          .fontSize(15).fontColor('#172B4D');
                        Text(source.bundleName).fontSize(11).fontColor('#7B8794');
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                      if (source.bundleName === this.selectedBundle) {
                        Text('已选择').fontSize(12).fontColor('#2457C5');
                      }
                    }.width('100%');
                  }
                  .width('100%').padding(14).borderRadius(12)
                  .backgroundColor(source.bundleName === this.selectedBundle ? '#E9F1FF' : '#F4F6F8')
                  .onClick(() => this.onSelect(source.bundleName));
                }
              }, (source: NotificationSource) => source.bundleName);
            }
          }.layoutWeight(1).width('100%');
        }
        if (this.loading || this.error.length > 0) { Blank(); }
        Button('刷新来源列表').width('100%').enabled(!this.loading)
          .backgroundColor('#F1F3F5').fontColor('#344563').onClick(() => this.onRefresh());
      }
      .width('100%').height('78%').padding({ left: 18, right: 18, top: 20, bottom: 24 })
      .alignItems(HorizontalAlign.Start).backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 24, topRight: 24 });
    }.width('100%').height('100%').zIndex(2);
  }
}
