import { AppTheme } from '../model/AppTheme';

@Component
export struct PageHeader {
  @Prop title: string = '';
  onBack: () => void = () => {};
  @BuilderParam trailing: () => void = this.defaultTrailing;

  @Builder
  defaultTrailing() {
    Blank().width(48);
  }

  build() {
    Row() {
      Button('返回')
        .backgroundColor(AppTheme.surfaceCard)
        .fontColor(AppTheme.textBody)
        .border({ width: 1, color: AppTheme.borderSubtle })
        .borderRadius(AppTheme.buttonRadius)
        .onClick(() => this.onBack());
      Blank();
      Text(this.title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.textPrimary);
      Blank();
      this.trailing();
    }
    .width('100%')
    .padding(18);
  }
}
