import type { RuleImportKind, RuleImportPreview } from '../services/ruleImport/RuleImportModels';
import { emptyRuleSample, previewFieldRows } from '../services/ruleImport/RuleImportGuide';
import type { RuleSampleDraft, RulePreviewFieldRow } from '../services/ruleImport/RuleImportGuide';

@Component
export struct RuleImportGuideView {
  @Prop kind: RuleImportKind = 'ocr';
  @Prop sample: RuleSampleDraft = emptyRuleSample();
  @Prop response: string = '';
  @Prop message: string = '';
  @Prop promptText: string = '';
  @Prop previews: RuleImportPreview[] = [];
  @Prop candidateSummary: string = '';
  @Prop busy: boolean = false;
  @Prop advanced: boolean = false;
  onFieldChange: (field: string, value: string) => void = (_field: string, _value: string) => {};
  onChooseSample: () => void = () => {};
  onCopy: () => void = () => {};
  onResponseChange: (value: string) => void = (_value: string) => {};
  onPreview: () => void = () => {};
  onSave: () => void = () => {};
  onToggleAdvanced: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('从样例添加识别方式').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#172B4D');
      Text('1. 提供样例，确认这笔交易').fontSize(15).fontWeight(FontWeight.Bold);
      Button(this.kind === 'ocr' ? '选择截图并提取文字' : '从通知历史选择样例')
        .enabled(!this.busy).onClick(() => this.onChooseSample());
      if (this.kind === 'notification') {
        Text('在通知历史打开详情，点“用此通知创建规则”；也可以在下方手动填写。')
          .fontSize(12).fontColor('#52606D');
      }
      this.field('来源名称或应用包名', 'source', this.sample.source, '例如：示例钱包');
      if (this.kind === 'notification') {
        this.field('通知标题', 'title', this.sample.title, '保留实际通知标题');
        Row({ space: 8 }) {
          Text('仅匹配此固定标题（将保存标题文字）').fontSize(12).layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.sample.matchTitle })
            .enabled(!this.busy)
            .onChange((value: boolean) => this.onFieldChange('matchTitle', value ? 'true' : 'false'));
        }.width('100%');
        Text('标题含金额、姓名或商户且每次变化时，请保持关闭；支付与聊天共用应用时，建议设置固定支付标题。')
          .fontSize(12).fontColor('#52606D');
      }
      Text(this.kind === 'ocr' ? '截图识别文字（可修改，修改后使用文字预览）' : '通知正文（请保留完整内容）')
        .fontSize(13);
      TextArea({ text: this.sample.input, placeholder: '选择样例后自动填入，也可手动粘贴' })
        .height(130).fontSize(13).enabled(!this.busy)
        .onChange((value: string) => this.onFieldChange('input', value));
      this.field('交易金额（元）', 'amount', this.sample.amount, '填写交易金额，不是余额');
      Row({ space: 8 }) {
        Text('收支');
        Button('支出').backgroundColor(this.sample.direction === 'expense' ? '#2857C5' : '#52606D')
          .enabled(!this.busy).onClick(() => this.onFieldChange('direction', 'expense'));
        Button('收入').backgroundColor(this.sample.direction === 'income' ? '#16845B' : '#52606D')
          .enabled(!this.busy).onClick(() => this.onFieldChange('direction', 'income'));
      }
      this.field(this.kind === 'ocr' ? '交易日期（有时分时可补充）' : '交易时间',
        'date', this.sample.date, this.kind === 'ocr' ? '2026-10-28' : '2026-10-28 10:15');
      if (this.kind === 'notification' && this.sample.receivedAt !== undefined) {
        Text('时间已带入通知发布时间；若正文另有交易时间，请按正文修正。').fontSize(12).fontColor('#52606D');
      }
      this.field('商户（选填，保留原文）', 'merchant', this.sample.merchant, '例如：午餐店');
      this.field('分类（选填）', 'category', this.sample.category, '例如：餐饮');
      Text('2. 复制完整材料，交给你使用的 AI').fontSize(15).fontWeight(FontWeight.Bold);
      Text('材料包含样例原文，请先遮盖姓名、卡号等隐私。应用不会联网发送；样例仅在本次页面中使用。')
        .fontSize(12).fontColor('#8A4B08');
      Button('复制完整 AI 材料').enabled(!this.busy).onClick(() => this.onCopy());
      if (this.promptText.length > 0) {
        Text(this.promptText).fontSize(12).copyOption(CopyOptions.LocalDevice);
      }
      Text('3. 粘贴 AI 返回内容，核对识别结果').fontSize(15).fontWeight(FontWeight.Bold);
      TextArea({ text: this.response, placeholder: '长按粘贴 AI 返回的完整内容，无需编辑代码' })
        .height(110).fontSize(12).enabled(!this.busy)
        .onChange((value: string) => this.onResponseChange(value));
      Button('重新检查结果').enabled(!this.busy && this.response.trim().length > 0)
        .onClick(() => this.onPreview());
      if (this.message.length > 0) {
        Text(this.message).fontSize(13).fontColor('#8A4B08').copyOption(CopyOptions.LocalDevice);
      }
      ForEach(this.previews, (preview: RuleImportPreview, index: number) => {
        Column({ space: 8 }) {
          Text((index === 0 ? '你的样例' : '附加样例 ' + index) + (preview.matched ? '：通过' : '：需要调整'))
            .fontWeight(FontWeight.Bold).fontColor(preview.matched ? '#16845B' : '#B42318');
          Text(preview.input).fontSize(12).fontColor('#52606D').copyOption(CopyOptions.LocalDevice);
          ForEach(previewFieldRows(preview), (row: RulePreviewFieldRow) => {
            Text(row.label + '：' + row.actual + (row.expected === '未指定' ? '' : '（确认值：' + row.expected + '）'))
              .fontSize(13).fontColor(row.matched ? '#344563' : '#B42318');
          }, (row: RulePreviewFieldRow) => row.label);
          if (preview.message !== undefined) {
            Text(preview.message).fontSize(12).fontColor('#52606D');
          }
        }
        .width('100%').padding(12).alignItems(HorizontalAlign.Start).backgroundColor('#F6F7F9').borderRadius(10);
      }, (_preview: RuleImportPreview, index: number) => 'preview-' + index);
      if (this.candidateSummary.length > 0) {
        Text(this.candidateSummary).fontSize(13).fontColor('#344563');
        Button('确认保存并优先启用').enabled(!this.busy && this.previews.length > 0 &&
          this.previews.every((preview: RuleImportPreview) => preview.matched))
          .backgroundColor('#16845B').onClick(() => this.onSave());
      }
      Button(this.advanced ? '收起高级设置' : '高级设置：手动编辑规则')
        .enabled(!this.busy).backgroundColor('#F1F3F5').fontColor('#344563')
        .onClick(() => this.onToggleAdvanced());
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor('#FFFFFF').borderRadius(14);
  }

  @Builder
  private field(label: string, field: string, value: string, placeholder: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(13).fontColor('#344563');
      TextInput({ text: value, placeholder: placeholder }).fontSize(13).enabled(!this.busy)
        .onChange((text: string) => this.onFieldChange(field, text));
    }
    .width('100%').alignItems(HorizontalAlign.Start);
  }
}
