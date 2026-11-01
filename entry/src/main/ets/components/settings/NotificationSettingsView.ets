import { NotificationProbeSnapshot } from '../../services/NotificationProbeStore';
import { formatDateTime } from '../../model/LedgerModels';
import type { ReminderSettingsDraft } from '../../model/NotificationReminderModels';
import { NotificationReminderSettingsView } from './NotificationReminderSettingsView';

export interface PairedNotificationDevice {
  address: string;
  label: string;
}

@Component
export struct NotificationSettingsView {
  @Prop permissionStatus: string = '尚未检查';
  @Prop subscriptionStatus: string = '尚未检查';
  @Prop probe: NotificationProbeSnapshot = {
    receivedCount: 0,
    bundleName: '',
    appName: '',
    deliveryTime: 0,
    title: '',
    body: '',
    titleLength: 0,
    bodyLength: 0
  };
  @Prop pairedDevices: PairedNotificationDevice[] = [];
  @Prop advancedHelp: boolean = false;
  @State private lowFrequencyExpanded: boolean = false;
  @Prop reminderDraft: ReminderSettingsDraft = {
    enabled: false, bundleName: '', keyword: '', startTime: '17:00', deadlineTime: '20:00'
  };
  @Prop reminderStatus: string = '尚未检查';
  @Prop reminderBusy: boolean = false;
  @Prop reminderSourceLabel: string = '选择来源应用';

  onReminderChange: (field: string, value: string) => void = () => {};
  onReminderToggle: (enabled: boolean) => void = () => {};
  onReminderSave: () => void = () => {};
  onReminderRefresh: () => void = () => {};
  onReminderAuthorize: () => void = () => {};
  onReminderOpenSourcePicker: () => void = () => {};

  onBack: () => void = () => {};
  onOpenPermission: () => void = () => {};
  onOpenRules: () => void = () => {};
  onRefresh: () => void = () => {};
  onFindDevices: () => void = () => {};
  onSubscribeDevice: (device: PairedNotificationDevice) => void = (_device: PairedNotificationDevice) => {};
  onShowRecentNotification: () => void = () => {};
  onClearDiagnostics: () => void = () => {};
  onToggleAdvancedHelp: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button('返回')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onBack());
        Blank();
        Text('通知接收设置')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
        Blank();
        Blank().width(48);
      }
      .width('100%')
      .padding(18);

      Scroll() {
        Column({ space: 14 }) {
          NotificationReminderSettingsView({
            draft: this.reminderDraft,
            status: this.reminderStatus,
            busy: this.reminderBusy,
            sourceLabel: this.reminderSourceLabel,
            onChange: this.onReminderChange,
            onToggle: this.onReminderToggle,
            onSave: this.onReminderSave,
            onRefresh: this.onReminderRefresh,
            onAuthorize: this.onReminderAuthorize,
            onOpenSourcePicker: this.onReminderOpenSourcePicker
          });
          Text('通知自动记账')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D')
            .width('100%');
          Column({ space: 12 }) {
            Text('授权后，本机处理工商银行、中信银行、支付宝和微信支付通知；只记录金额与收支方向明确的交易，并忽略支付宝、微信的失败、撤销和退款通知。')
              .fontSize(13)
              .fontColor('#52606D');

            Column({ space: 8 }) {
              Text('通知访问授权')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172B4D');
              Text('在系统页允许读取通知，并选择要接收的来源应用。')
                .fontSize(13)
                .fontColor('#52606D');
              Text(this.permissionStatus)
                .fontSize(12)
                .fontColor('#7B8794');
              Row({ space: 8 }) {
                Button('打开通知访问授权')
                  .layoutWeight(3)
                  .backgroundColor('#2857C5')
                  .fontColor('#FFFFFF')
                  .onClick(() => this.onOpenPermission());
                Button('刷新授权状态')
                  .layoutWeight(2)
                  .backgroundColor('#F1F3F5')
                  .fontColor('#344563')
                  .onClick(() => this.onRefresh());
              }
              .width('100%');
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            Column({ space: 8 }) {
              Text('自动入账识别规则')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172B4D');
              Text('管理通知来源、正文匹配和交易字段提取。')
                .fontSize(13)
                .fontColor('#52606D');
              Button('配置识别规则')
                .width('100%')
                .backgroundColor('#E9F1FF')
                .fontColor('#2457C5')
                .onClick(() => this.onOpenRules());
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);

          Button(this.lowFrequencyExpanded ? '收起设备与诊断' : '设备与诊断（穿戴设备、通知排查）')
            .width('100%')
            .backgroundColor('#FFFFFF')
            .fontColor('#344563')
            .onClick(() => {
              this.lowFrequencyExpanded = !this.lowFrequencyExpanded;
            });

          if (this.lowFrequencyExpanded) {
            Column({ space: 8 }) {
              Text('穿戴设备通知转发')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172B4D');
              Text('如需通过已配对设备转发通知，可单独申请蓝牙访问并订阅。')
                .fontSize(13)
                .fontColor('#52606D');
              Button('查找已配对设备')
                .width('100%')
                .backgroundColor('#E9F1FF')
                .fontColor('#2457C5')
                .onClick(() => this.onFindDevices());
              ForEach(this.pairedDevices, (device: PairedNotificationDevice) => {
                Button('订阅 ' + device.label)
                  .width('100%')
                  .backgroundColor('#E9F1FF')
                  .fontColor('#2457C5')
                  .onClick(() => this.onSubscribeDevice(device));
              }, (device: PairedNotificationDevice) => device.address);
              Text(this.subscriptionStatus)
                .fontSize(12)
                .fontColor('#7B8794');
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(14);

            Column({ space: 8 }) {
              Text('通知接收诊断')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#172B4D');
              if (this.probe.receivedCount > 0) {
                Text('已收到通知：' + this.probe.receivedCount + ' 条')
                  .fontSize(13)
                  .fontColor('#16845B');
                Text('最近来源：' + (this.probe.appName.length > 0 ? this.probe.appName : this.probe.bundleName))
                  .fontSize(12)
                  .fontColor('#52606D');
                Text('通知时间：' + formatDateTime(this.probe.deliveryTime))
                  .fontSize(12)
                  .fontColor('#52606D');
                Text('标题有内容：' + (this.probe.titleLength > 0 ? '是' : '否') +
                  '；正文有内容：' + (this.probe.bodyLength > 0 ? '是' : '否'))
                  .fontSize(12)
                  .fontColor('#52606D');
                Button('显示最近通知详情')
                  .width('100%')
                  .backgroundColor('#E9F1FF')
                  .fontColor('#2457C5')
                  .onClick(() => this.onShowRecentNotification());
              } else {
                Text('尚未收到通知回调。确认授权和来源选择后，可通过支持银行的通知验证。')
                  .fontSize(13)
                  .fontColor('#52606D');
              }
              Row({ space: 8 }) {
                Button('刷新状态')
                  .layoutWeight(1)
                  .backgroundColor('#F1F3F5')
                  .fontColor('#344563')
                  .onClick(() => this.onRefresh());
                Button('清除诊断记录')
                  .layoutWeight(1)
                  .backgroundColor('#F1F3F5')
                  .fontColor('#344563')
                  .onClick(() => this.onClearDiagnostics());
              }
              .width('100%');
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(14);

            Column({ space: 8 }) {
              Button(this.advancedHelp ? '收起排查说明' : '查看排查说明')
                .backgroundColor('#FFFFFF')
                .fontColor('#344563')
                .onClick(() => this.onToggleAdvancedHelp());
              if (this.advancedHelp) {
                Text('若授权页中找不到本应用，请确认安装包具备通知订阅能力并重新签名安装。穿戴设备还需完成配对和订阅。')
                  .fontSize(12)
                  .fontColor('#7B8794');
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 18, right: 18, bottom: 24 });
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor('#F6F7F9');
  }
}
