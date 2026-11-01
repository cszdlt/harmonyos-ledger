import { AppTheme } from '../model/AppTheme';

@Component
export struct MainTabBarItem {
  @Prop title: string = '';
  @Prop selected: boolean = false;

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(13)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected ? AppTheme.brandText : AppTheme.textMuted);
      Row()
        .width(22)
        .height(3)
        .borderRadius(99)
        .backgroundColor(this.selected ? AppTheme.brandText : '#00000000');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }
}
