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
    Column({ space: 10 }) {
      Text('下班打卡提醒')
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#172B4D');
      Text('按中国节假日安排工作日；周末调休上班日也会提醒。未公布安排的年份按周一至周五预排。')
        .fontSize(13).fontColor('#52606D');
      Text('授权日历读写后，在本机创建独立的“下班打卡提醒”日历；提醒由系统日历发出，收到匹配通知后跳过当天。')
        .fontSize(13).fontColor('#52606D');
      Row() {
        Text('启用提醒').layoutWeight(1).fontColor('#172B4D');
        Toggle({ type: ToggleType.Switch, isOn: this.draft.enabled })
          .enabled(!this.busy).onChange((enabled: boolean) => this.onToggle(enabled));
      }.width('100%');
      Text('来源应用').fontSize(12).fontColor('#52606D');
      Button(this.sourceLabel)
        .width('100%').backgroundColor('#F1F3F5').fontColor('#344563').enabled(!this.busy)
        .onClick(() => this.onOpenSourcePicker());
      Text('成功关键词（标题或正文包含，按原文区分大小写）').fontSize(12).fontColor('#52606D');
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
      Text('时间格式为 HH:mm，不支持跨天。配置保存后生效；未收到通知不代表一定未打卡。')
        .fontSize(12).fontColor('#7B8794');
      Button(this.busy ? '正在处理…' : '保存提醒设置')
        .width('100%').backgroundColor('#E9F1FF').fontColor('#2457C5')
        .enabled(!this.busy).onClick(() => this.onSave());
      Row({ space: 8 }) {
        Button('授权日历读写').layoutWeight(1).enabled(!this.busy)
          .backgroundColor('#F1F3F5').fontColor('#344563').onClick(() => this.onAuthorize());
        Button('刷新并重试').layoutWeight(1).enabled(!this.busy)
          .backgroundColor('#F1F3F5').fontColor('#344563').onClick(() => this.onRefresh());
      }.width('100%');
      Text(this.status).fontSize(12).fontColor('#52606D');
      Text('请开启系统日历及“下班打卡提醒”日历的提醒。声音受日历通知、静音和勿扰设置影响；请勿手动修改此日程。')
        .fontSize(12).fontColor('#7B8794');
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(16).backgroundColor('#FFFFFF').borderRadius(14);
  }
}
