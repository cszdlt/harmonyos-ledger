import { AccountingType, EntryDirection } from '../../model/LedgerModels';

@Component
export struct LedgerEditorView {
  @Prop editingId: string = '';
  @Prop merchant: string = '';
  @Prop dateText: string = '';
  @Prop amountText: string = '';
  @Prop entryDirection: EntryDirection = 'expense';
  @Prop accountingType: AccountingType = 'normal';
  @Prop category: string = '其他';
  @Prop note: string = '';
  @Prop dateError: string = '';
  @Prop amountError: string = '';

  private scroller: Scroller = new Scroller();

  onBack: () => void = () => {};
  onSave: () => void = () => {};
  onChooseDate: () => void = () => {};
  onFieldChange: (field: string, value: string) => void = (_field: string, _value: string) => {};
  onDirectionChange: (direction: EntryDirection) => void = (_direction: EntryDirection) => {};
  onAccountingTypeChange: (type: AccountingType) => void = (_type: AccountingType) => {};

  build() {
    Column() {
      Row() {
        Button('返回')
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onBack());
        Blank();
        Text(this.editingId.length > 0 ? '编辑账目' : '手动记账')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
        Blank();
        Button('保存')
          .backgroundColor('#2857C5')
          .fontColor('#FFFFFF')
          .onClick(() => this.onSave());
      }
      .width('100%')
      .padding(18);
      Scroll(this.scroller) {
        Column({ space: 14 }) {
          this.inputField('商户或摘要', this.merchant, 'merchant');
          this.inputField('日期时间（YYYY-MM-DD HH:mm）', this.dateText, 'date', this.dateError);
          Button('选择日期')
            .width('100%')
            .backgroundColor('#E9F1FF')
            .fontColor('#2457C5')
            .onClick(() => this.onChooseDate());
          this.inputField('金额（元）', this.amountText, 'amount', this.amountError);
          Text('方向')
            .fontSize(14)
            .fontColor('#52606D');
          Row({ space: 10 }) {
            Button('支出')
              .layoutWeight(1)
              .backgroundColor(this.entryDirection === 'expense' ? '#2857C5' : '#FFFFFF')
              .fontColor(this.entryDirection === 'expense' ? '#FFFFFF' : '#344563')
              .onClick(() => this.onDirectionChange('expense'));
            Button('收入')
              .layoutWeight(1)
              .backgroundColor(this.entryDirection === 'income' ? '#16845B' : '#FFFFFF')
              .fontColor(this.entryDirection === 'income' ? '#FFFFFF' : '#344563')
              .onClick(() => this.onDirectionChange('income'));
          }
          .width('100%');
          this.inputField('分类', this.category, 'category');
          if (this.entryDirection === 'expense') {
            Text('记账类型')
              .fontSize(14)
              .fontColor('#52606D');
            Row({ space: 6 }) {
              this.accountingTypeButton('普通支出', 'normal');
              this.accountingTypeButton('信用卡消费', 'credit-card');
              this.accountingTypeButton('信用卡还款', 'credit-repayment');
            }
            .width('100%');
          }
          this.inputField('备注（可选）', this.note, 'note');
          Text('截图识别的内容仍需你核对。')
            .fontSize(12)
            .fontColor('#7B8794');
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .padding({ left: 18, right: 18, top: 4, bottom: 24 });
      }
      .layoutWeight(1)
      .onAppear(() => {
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7F9');
  }

  @Builder
  private accountingTypeButton(label: string, type: AccountingType) {
    Button(label)
      .layoutWeight(1)
      .fontSize(12)
      .backgroundColor(this.accountingType === type ? '#2857C5' : '#FFFFFF')
      .fontColor(this.accountingType === type ? '#FFFFFF' : '#344563')
      .onClick(() => this.onAccountingTypeChange(type));
  }

  @Builder
  private inputField(label: string, value: string, field: string, error: string = '') {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(14)
        .fontColor('#52606D');
      TextInput({ text: value, placeholder: label })
        .fontSize(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .type(field === 'amount' ? InputType.NUMBER_DECIMAL : InputType.Normal)
        .onChange((changed: string) => {
          this.onFieldChange(field, changed);
        });
      if (error.length > 0) {
        Text(error)
          .fontSize(12)
          .fontColor('#B42318');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
