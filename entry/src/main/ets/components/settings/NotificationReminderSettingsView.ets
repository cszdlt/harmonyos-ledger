import type { ReminderSettingsDraft } from '../../model/NotificationReminderModels';

@Component
export struct NotificationReminderSettingsView {
  @Prop draft: ReminderSettingsDraft = {
    enabled: false, bundleName: '', keyword: '', startTime: '17:00', deadlineTime: '20:00'
  };
  @Prop status: string = '尚未检查';
  @Prop busy: boolean = false;
  @Prop sourceLabel: string = '选择来源应用';
  onChange: (field: string, value: string) => void = () => {};
  onToggle: (enabled: boolean) => void = () => {};
  onSave: () => void = () => {};
  onRefresh: () => void = () => {};
  onAuthorize: () => void = () => {};
  onOpenSourcePicker: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('下班打卡提醒')
          .layoutWeight(1)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
        Toggle({ type: ToggleType.Switch, isOn: this.draft.enabled })
          .enabled(!this.busy).onChange((enabled: boolean) => this.onToggle(enabled));
      }.width('100%');
      Text('按中国节假日安排工作日，包含周末调休上班日；未公布年份按周一至周五预排。')
        .fontSize(13).fontColor('#52606D');
      Text('系统日历通过本机专用日历发出提醒；收到匹配通知后跳过当天。')
        .fontSize(13).fontColor('#52606D');
      Text('来源应用').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#344563');
      Button(this.sourceLabel)
        .width('100%').backgroundColor('#F1F3F5').fontColor('#344563').enabled(!this.busy)
        .onClick(() => this.onOpenSourcePicker());
      Row() {
        Text('成功关键词').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#344563');
        Blank();
        Text('标题或正文包含，区分大小写').fontSize(11).fontColor('#7B8794');
      }.width('100%');
      TextInput({ text: this.draft.keyword, placeholder: '例如 下班打卡成功，请按实际通知填写' })
        .enabled(!this.busy).onChange((value: string) => this.onChange('keyword', value));
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text('接收起始时间').fontSize(12).fontColor('#52606D');
          TextInput({ text: this.draft.startTime, placeholder: '17:00' })
            .enabled(!this.busy).onChange((value: string) => this.onChange('startTime', value));
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Column({ space: 6 }) {
          Text('提醒时间').fontSize(12).fontColor('#52606D');
          TextInput({ text: this.draft.deadlineTime, placeholder: '20:00' })
            .enabled(!this.busy).onChange((value: string) => this.onChange('deadlineTime', value));
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%');
      Text('时间使用 HH:mm 格式且不跨天；保存后生效。未收到通知不代表一定未打卡。')
        .fontSize(12).fontColor('#7B8794');
      Button(this.busy ? '正在处理…' : '保存提醒设置')
        .width('100%').backgroundColor('#2857C5').fontColor('#FFFFFF')
        .enabled(!this.busy).onClick(() => this.onSave());
      Row({ space: 8 }) {
        Button('授权日历读写').layoutWeight(1).enabled(!this.busy)
          .backgroundColor('#F1F3F5').fontColor('#344563').onClick(() => this.onAuthorize());
        Button('刷新并重试').layoutWeight(1).enabled(!this.busy)
          .backgroundColor('#F1F3F5').fontColor('#344563').onClick(() => this.onRefresh());
      }.width('100%');
      Text(this.status).fontSize(12).fontColor('#52606D');
      Text('请开启系统日历及专用日历的提醒；漏收通知可能造成误提醒。声音受静音和勿扰设置影响，请勿手动修改日程。')
        .fontSize(12).fontColor('#7B8794');
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(16).backgroundColor('#FFFFFF').borderRadius(14);
  }
}
