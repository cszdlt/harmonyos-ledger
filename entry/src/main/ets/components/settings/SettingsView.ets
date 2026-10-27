import { CycleStartDaySelector } from './CycleStartDaySelector';

@Component
export struct SettingsView {
  @Prop cycleStartDay: number = 15;
  @Prop busy: boolean = false;
  @Prop creditHistoryUndoCount: number = 0;
  @Prop operationMessage: string = '';
  onExportBackup: () => void = () => {};
  onRestoreBackup: () => void = () => {};
  onUndoCreditHistory: () => void = () => {};

  onBack: () => void = () => {};
  onCycleStartDayChange: (day: number) => void = (_day: number) => {};
  onOpenOcrRules: () => void = () => {};
  onOpenHelp: () => void = () => {};
  onExportCsv: () => void = () => {};
  onImportCsv: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button('返回')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onBack());
        Blank();
        Text('设置')
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
          Column({ space: 8 }) {
            Text('使用帮助')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('查看记账、截图导入、通知识别和备份恢复的操作步骤。')
              .fontSize(13)
              .fontColor('#52606D');
            Button('查看使用指南')
              .width('100%')
              .backgroundColor('#E9F1FF')
              .fontColor('#2457C5')
              .onClick(() => this.onOpenHelp());
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);

          Column({ space: 8 }) {
            Text('数据与隐私')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('账目和 OCR 截图只在本机处理，不会上传。卸载应用可能会删除本机数据。')
              .fontSize(13)
              .fontColor('#52606D');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);

          Column({ space: 8 }) {
            Text('记账周期')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('周期从每月所选日期开始，至下月前一天结束。')
              .fontSize(13)
              .fontColor('#52606D');
            CycleStartDaySelector({
              startDay: this.cycleStartDay,
              onChange: (day: number) => this.onCycleStartDayChange(day)
            });
            Text('年统计仍按自然年。')
              .fontSize(12)
              .fontColor('#7B8794');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);

          Column({ space: 8 }) {
            Text('截图 OCR')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('管理微信、支付宝和工商银行截图的来源、字段与过滤规则。识别结果仍需复核后保存。')
              .fontSize(13)
              .fontColor('#52606D');
            Button('管理 OCR 识别规则')
              .width('100%')
              .backgroundColor('#E9F1FF')
              .fontColor('#2457C5')
              .onClick(() => this.onOpenOcrRules());
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);

          Column({ space: 8 }) {
            Text('数据备份')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('完整备份包含全部账目、识别信息、通知/OCR 规则和记账周期，不包含通知归档。文件为本地明文 JSON，请妥善保管。')
              .fontSize(13)
              .fontColor('#52606D');
            Button('导出完整备份（JSON）')
              .width('100%')
              .backgroundColor('#2857C5')
              .fontColor('#FFFFFF')
              .onClick(() => this.onExportBackup());
            Button('从完整备份恢复')
              .width('100%')
              .backgroundColor('#E9F1FF')
              .fontColor('#2457C5')
              .onClick(() => this.onRestoreBackup());
            if (this.operationMessage.length > 0) {
              Text(this.operationMessage)
                .fontSize(13)
                .fontColor('#52606D');
            }
            if (this.creditHistoryUndoCount > 0) {
              Button('撤销最近一次批量标记（' + this.creditHistoryUndoCount + ' 笔）')
                .width('100%')
                .backgroundColor('#E9F1FF')
                .fontColor('#2457C5')
                .onClick(() => this.onUndoCreditHistory());
            }
            Text('导出全部账目，或从本应用导出的 CSV 恢复账目。导入前会检查无效记录和重复记录。')
              .fontSize(13)
              .fontColor('#52606D');
            Button('导入本应用 CSV')
              .width('100%')
              .backgroundColor('#E9F1FF')
              .fontColor('#2457C5')
              .onClick(() => this.onImportCsv());
            Button('导出全部账目为 CSV')
              .width('100%')
              .backgroundColor('#2857C5')
              .fontColor('#FFFFFF')
              .onClick(() => this.onExportCsv());
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(14);
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
    .enabled(!this.busy)
    .justifyContent(FlexAlign.Start)
    .backgroundColor('#F6F7F9');
  }
}
