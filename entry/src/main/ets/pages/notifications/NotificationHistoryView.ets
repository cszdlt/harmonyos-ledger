import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NotificationArchiveRepository } from '../../data/NotificationArchiveRepository';
import {
  NotificationArchiveCursor,
  NotificationArchiveEntry,
  NotificationArchiveFilter,
  NotificationSource,
  filterNotificationSources
} from '../../model/NotificationArchiveModels';
import { formatDateOnly, formatDateTime } from '../../model/LedgerModels';
import { NotificationArchiveRow } from '../../components/notifications/NotificationArchiveRow';
import { NotificationFilterBar, NotificationHistoryRange } from '../../components/notifications/NotificationFilterBar';



@Component
export struct NotificationHistoryView {
  onOpenSettings: () => void = () => {};
  @Link overlayOpen: boolean;
  @Link
  @Watch('onBackRequestChanged')
  backRequestRevision: number;

  @State private entries: NotificationArchiveEntry[] = [];
  @State private sources: NotificationSource[] = [];
  @State private selectedBundle: string = '';
  @State private keywordInput: string = '';
  @State private appliedKeyword: string = '';
  @State private range: NotificationHistoryRange = 'all';
  @State private customStart: number = Date.now();
  @State private customEnd: number = Date.now();
  @State private loading: boolean = false;
  @State private loadingMore: boolean = false;
  @State private errorMessage: string = '';
  @State private pagingError: boolean = false;
  @State private selectedEntry: NotificationArchiveEntry | undefined = undefined;
  @State private filtersExpanded: boolean = false;
  @State private showTechnicalDetails: boolean = false;
  @State private sourcePickerOpen: boolean = false;
  @State private sourceSearchInput: string = '';

  private repository: NotificationArchiveRepository = new NotificationArchiveRepository();
  private repositoryReady: boolean = false;
  private historyVisible: boolean = false;
  private archiveChangeSubscribed: boolean = false;
  private archiveChangeObserver: () => void = (): void => this.onArchiveChanged();
  private nextCursor: NotificationArchiveCursor | undefined = undefined;
  private queryRevision: number = 0;

  aboutToAppear(): void {
    this.historyVisible = true;
    void this.refresh();
  }

  aboutToDisappear(): void {
    this.historyVisible = false;
    if (this.archiveChangeSubscribed) {
      this.repository.stopListeningForArchiveChanges(this.archiveChangeObserver);
      this.archiveChangeSubscribed = false;
    }
  }

  private onBackRequestChanged(): void {
    this.closeOverlay();
  }

  build() {
    Stack() {
      Column({ space: 12 }) {
        Row() {
          Text('通知历史')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172B4D');
          Blank();
          Button('设置')
            .backgroundColor('#E9F1FF')
            .fontColor('#2457C5')
            .onClick(() => this.onOpenSettings());
        }
        .width('100%');

        Text('仅显示系统实际投递给本应用的通知。')
          .fontSize(12)
          .fontColor('#52606D');

        NotificationFilterBar({
          expanded: this.filtersExpanded,
          keywordInput: this.keywordInput,
          appliedKeyword: this.appliedKeyword,
          selectedSourceLabel: this.selectedSourceLabel(),
          rangeLabel: this.rangeLabel(),
          range: this.range,
          customStart: this.customStart,
          customEnd: this.customEnd,
          filterSummary: this.activeFilterSummary(),
          activeFilterCount: this.activeFilterCount(),
          onKeywordChange: (value: string) => {
            this.keywordInput = value;
          },
          onApplyKeyword: () => this.applyKeyword(),
          onToggleExpanded: () => {
            this.filtersExpanded = !this.filtersExpanded;
          },
          onRefresh: () => {
            void this.refresh();
          },
          onChooseSource: () => this.openSourcePicker(),
          onChooseRange: () => this.chooseRange(),
          onChooseStartDate: () => this.chooseCustomDate(true),
          onChooseEndDate: () => this.chooseCustomDate(false),
          onReset: () => this.resetFilters()
        });

        if (this.loading) {
          LoadingProgress();
        } else if (this.errorMessage.length > 0 && this.entries.length === 0) {
          Column({ space: 8 }) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor('#B42318');
            if (this.errorMessage !== '开始日期不能晚于结束日期') {
              Button('重试')
                .onClick(() => void this.refresh());
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        } else if (this.entries.length === 0) {
          Column({ space: 10 }) {
            Text(this.hasActiveFilter() ? '没有符合筛选条件的通知' : '尚无通知记录')
              .fontSize(15)
              .fontColor('#52606D');
            if (!this.hasActiveFilter()) {
              Text('请先在设置中完成设备订阅和通知来源授权。')
                .fontSize(12)
                .fontColor('#7B8794');
              Button('前往通知设置')
                .backgroundColor('#E9F1FF')
                .fontColor('#2457C5')
                .onClick(() => this.onOpenSettings());
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        } else {
          List({ space: 10 }) {
            ForEach(this.entries, (entry: NotificationArchiveEntry) => {
              ListItem() {
                NotificationArchiveRow({ entry: entry, onSelect: () => this.openEntry(entry) });
              }
            }, (entry: NotificationArchiveEntry) => entry.id.toString());
            ListItem() {
              Row() {
                Blank().height(8);
              }
            }
            if (this.loadingMore || this.errorMessage.length > 0) {
              ListItem() {
                Row({ space: 8 }) {
                  Text(this.loadingMore ? '正在加载…' : this.errorMessage)
                    .fontSize(12)
                    .fontColor(this.loadingMore ? '#7B8794' : '#B42318');
                  if (!this.loadingMore && this.errorMessage.length > 0) {
                    Button('重试')
                      .onClick(() => {
                        if (this.pagingError) {
                          void this.loadMore(true);
                        } else {
                          void this.refresh();
                        }
                      });
                  }
                }
                .width('100%');
              }
            }
          }
          .layoutWeight(1)
          .onReachEnd(() => void this.loadMore());
        }

      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(18);

      if (this.selectedEntry !== undefined) {
        this.detailOverlay(this.selectedEntry);
      }
      if (this.sourcePickerOpen) {
        this.sourcePickerOverlay();
      }
    }
    .width('100%')
    .height('100%');
  }


  @Builder
  private detailOverlay(entry: NotificationArchiveEntry) {
    Column() {
      Column({ space: 12 }) {
        Text('通知详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
        Scroll() {
          Column({ space: 10 }) {
            this.detailField('来源', entry.appName.length > 0 ? entry.appName : entry.bundleName);
            this.detailField('标题', entry.title);
            this.detailField('正文', entry.body);
            this.detailField('通知时间', formatDateTime(entry.eventTime));
            this.detailField('接收时间', formatDateTime(entry.receivedAt));
            Button(this.showTechnicalDetails ? '收起系统字段' : '显示系统字段')
              .backgroundColor('#F1F3F5')
              .fontColor('#344563')
              .onClick(() => {
                this.showTechnicalDetails = !this.showTechnicalDetails;
              });
            if (this.showTechnicalDetails) {
              this.detailField('归档序号', entry.id.toString());
              this.detailField('应用包名', entry.bundleName);
              this.detailField('发布时间', entry.deliveryTime > 0 ? formatDateTime(entry.deliveryTime) : '未提供');
              this.detailField('通知标识', entry.hashCode);
              this.detailField('通知类别', entry.slotType.toString());
              this.detailField('分组', entry.groupName);
              this.detailField('应用分身序号', entry.appIndex.toString());
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .height('70%');
        Button('关闭')
          .width('100%')
          .backgroundColor('#2457C5')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.closeOverlay();
          });
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.scale({ x: 0.96, y: 0.96 }).combine(TransitionEffect.OPACITY)
          .animation({ duration: 190, curve: Curve.EaseOut }),
        TransitionEffect.scale({ x: 0.98, y: 0.98 }).combine(TransitionEffect.OPACITY)
          .animation({ duration: 140, curve: Curve.EaseIn })
      ));
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20 })
    .backgroundColor('#66000000')
    .zIndex(1)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }));
  }

  @Builder
  private detailField(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#7B8794');
      Text(value.length > 0 ? value : '（空）')
        .fontSize(14)
        .fontColor('#344563')
        .copyOption(CopyOptions.LocalDevice);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private sourcePickerOverlay() {
    Column() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('选择通知来源')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172B4D');
            Text('共 ' + this.sources.length + ' 个应用')
              .fontSize(12)
              .fontColor('#7B8794');
          }
          .alignItems(HorizontalAlign.Start);
          Blank();
          Button('×')
            .width(36)
            .height(36)
            .fontSize(20)
            .fontColor('#344563')
            .backgroundColor('#F1F3F5')
            .borderRadius(18)
            .onClick(() => {
              this.sourcePickerOpen = false;
            });
        }
        .width('100%');

        TextInput({ text: this.sourceSearchInput, placeholder: '搜索应用名称或包名' })
          .height(48)
          .padding({ left: 14, right: 14 })
          .backgroundColor('#F4F6F8')
          .borderRadius(12)
          .onChange((value: string) => {
            this.sourceSearchInput = value;
          });

        List({ space: 8 }) {
          ListItem() {
            this.sourcePickerOption('全部来源', '');
          }
          if (this.sources.length === 0) {
            ListItem() {
              this.sourcePickerEmptyState('还没有可筛选的通知来源');
            }
          } else if (this.filteredSources().length === 0) {
            ListItem() {
              this.sourcePickerEmptyState('没有找到匹配的应用');
            }
          } else {
            ForEach(this.filteredSources(), (source: NotificationSource) => {
              ListItem() {
                this.sourcePickerOption(
                  source.appName.length > 0 ? source.appName : source.bundleName,
                  source.bundleName
                );
              }
            }, (source: NotificationSource) => source.bundleName);
          }
        }
        .layoutWeight(1);
      }
      .width('100%')
      .height('78%')
      .padding({ left: 18, right: 18, top: 20, bottom: 24 })
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 24, topRight: 24 });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#66000000')
    .zIndex(2);
  }

  @Builder
  private sourcePickerOption(appName: string, bundleName: string) {
    Button() {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(appName)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#172B4D')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(bundleName.length > 0 ? bundleName : '不过滤应用来源')
            .fontSize(11)
            .fontColor('#7B8794')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        if (this.selectedBundle === bundleName) {
          Text('✓')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2457C5')
            .width(24)
            .textAlign(TextAlign.Center);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.selectedBundle === bundleName ? '#EEF4FF' : '#F7F8FA')
    .borderRadius(14)
    .onClick(() => this.selectSource(bundleName));
  }

  @Builder
  private sourcePickerEmptyState(message: string) {
    Column() {
      Text(message)
        .fontSize(14)
        .fontColor('#7B8794')
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center);
  }

  private async refresh(): Promise<void> {
    const revision = ++this.queryRevision;
    this.loading = true;
    this.pagingError = false;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      await this.repository.open(context);
      if (this.historyVisible && !this.archiveChangeSubscribed) {
        this.repository.listenForArchiveChanges(this.archiveChangeObserver);
        this.archiveChangeSubscribed = true;
      }
      const sources = await this.repository.listSources();
      if (revision !== this.queryRevision) {
        return;
      }
      this.sources = sources;
      this.repositoryReady = true;
      await this.reload();
    } catch (error) {
      if (revision === this.queryRevision) {
        const businessError = error as BusinessError;
        this.errorMessage = '读取通知历史失败：' + businessError.message;
        this.loading = false;
      }
    }
  }

  private onArchiveChanged(): void {
    if (this.historyVisible) {
      void this.refresh();
    }
  }

  private async reload(): Promise<void> {
    if (!this.repositoryReady) {
      return;
    }
    const revision = ++this.queryRevision;
    this.nextCursor = undefined;
    this.entries = [];
    this.errorMessage = '';
    this.pagingError = false;
    this.loadingMore = false;
    const filter = this.currentFilter();
    if (filter === undefined) {
      this.loading = false;
      return;
    }
    this.loading = true;
    try {
      const page = await this.repository.listPage(filter);
      if (revision !== this.queryRevision) {
        return;
      }
      this.entries = page.entries;
      this.nextCursor = page.nextCursor;
    } catch (error) {
      if (revision === this.queryRevision) {
        const businessError = error as BusinessError;
        this.errorMessage = '读取通知历史失败：' + businessError.message;
      }
    } finally {
      if (revision === this.queryRevision) {
        this.loading = false;
      }
    }
  }

  private async loadMore(retry: boolean = false): Promise<void> {
    if (this.loading || this.loadingMore || this.nextCursor === undefined ||
      (this.errorMessage.length > 0 && !retry)) {
      return;
    }
    const filter = this.currentFilter();
    if (filter === undefined) {
      return;
    }
    const revision = this.queryRevision;
    const cursor = this.nextCursor;
    this.loadingMore = true;
    this.errorMessage = '';
    this.pagingError = false;
    try {
      const page = await this.repository.listPage(filter, cursor);
      if (revision !== this.queryRevision) {
        return;
      }
      this.entries = this.entries.concat(page.entries);
      this.nextCursor = page.nextCursor;
    } catch (error) {
      if (revision === this.queryRevision) {
        const businessError = error as BusinessError;
        this.errorMessage = '继续加载失败：' + businessError.message;
        this.pagingError = true;
      }
    } finally {
      if (revision === this.queryRevision) {
        this.loadingMore = false;
      }
    }
  }

  private currentFilter(): NotificationArchiveFilter | undefined {
    const filter: NotificationArchiveFilter = {
      bundleName: this.selectedBundle,
      keyword: this.appliedKeyword
    };
    if (this.range === 'all') {
      return filter;
    }
    const now = new Date();
    if (this.range === 'custom') {
      const start = new Date(this.customStart);
      const startTime = new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime();
      const end = new Date(this.customEnd);
      const endTime = new Date(end.getFullYear(), end.getMonth(), end.getDate()).getTime();
      if (startTime > endTime) {
        this.errorMessage = '开始日期不能晚于结束日期';
        return undefined;
      }
      filter.startTime = startTime;
      filter.endTimeExclusive = new Date(end.getFullYear(), end.getMonth(), end.getDate() + 1).getTime();
      return filter;
    }
    const days = this.range === 'today' ? 1 : this.range === '7days' ? 7 : 30;
    filter.startTime = new Date(now.getFullYear(), now.getMonth(), now.getDate() - days + 1).getTime();
    filter.endTimeExclusive = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime();
    return filter;
  }

  private openSourcePicker(): void {
    this.sourceSearchInput = '';
    this.sourcePickerOpen = true;
  }

  private selectSource(bundleName: string): void {
    this.selectedBundle = bundleName;
    this.sourcePickerOpen = false;
    void this.reload();
  }

  private filteredSources(): NotificationSource[] {
    return filterNotificationSources(this.sources, this.sourceSearchInput);
  }

  private chooseRange(): void {
    const labels: string[] = ['全部时间', '今天', '近7天', '近30天', '自定义'];
    const ranges: NotificationHistoryRange[] = ['all', 'today', '7days', '30days', 'custom'];
    const selected = ranges.findIndex((value: NotificationHistoryRange) => value === this.range);
    const uiContext = this.getUIContext();
    uiContext.showTextPickerDialog({
      range: labels,
      selected: selected,
      onAccept: (result: TextPickerResult) => {
        if (typeof result.index !== 'number') {
          return;
        }
        const index = result.index;
        uiContext.runScopedTask(() => {
          if (index < 0 || index >= ranges.length) {
            return;
          }
          this.range = ranges[index];
          void this.reload();
        });
      }
    });
  }

  private rangeLabel(): string {
    if (this.range === 'today') {
      return '今天';
    }
    if (this.range === '7days') {
      return '近7天';
    }
    if (this.range === '30days') {
      return '近30天';
    }
    if (this.range === 'custom') {
      return '自定义';
    }
    return '全部时间';
  }

  private chooseCustomDate(isStart: boolean): void {
    const uiContext = this.getUIContext();
    uiContext.showDatePickerDialog({
      selected: new Date(isStart ? this.customStart : this.customEnd),
      onDateAccept: (value: Date) => {
        uiContext.runScopedTask(() => {
          const day = new Date(value.getFullYear(), value.getMonth(), value.getDate()).getTime();
          if (isStart) {
            this.customStart = day;
          } else {
            this.customEnd = day;
          }
          void this.reload();
        });
      }
    });
  }

  private selectedSourceLabel(): string {
    const source = this.sources.find((item: NotificationSource) => item.bundleName === this.selectedBundle);
    if (source === undefined) {
      return '全部来源';
    }
    return source.appName.length > 0 ? source.appName + ' · ' + source.bundleName : source.bundleName;
  }

  private activeFilterCount(): number {
    let count = 0;
    if (this.selectedBundle.length > 0) {
      count++;
    }
    if (this.appliedKeyword.length > 0) {
      count++;
    }
    if (this.range !== 'all') {
      count++;
    }
    return count;
  }

  private activeFilterSummary(): string {
    const parts: string[] = [];
    if (this.selectedBundle.length > 0) {
      parts.push('来源：' + this.selectedSourceLabel());
    }
    if (this.appliedKeyword.length > 0) {
      parts.push('关键词：' + this.appliedKeyword);
    }
    if (this.range === 'today') {
      parts.push('今天');
    } else if (this.range === '7days') {
      parts.push('近7天');
    } else if (this.range === '30days') {
      parts.push('近30天');
    } else if (this.range === 'custom') {
      parts.push(formatDateOnly(this.customStart) + ' 至 ' + formatDateOnly(this.customEnd));
    }
    return parts.join(' · ');
  }

  private resetFilters(): void {
    this.selectedBundle = '';
    this.keywordInput = '';
    this.appliedKeyword = '';
    this.range = 'all';
    void this.reload();
  }

  private openEntry(entry: NotificationArchiveEntry): void {
    this.selectedEntry = entry;
    this.showTechnicalDetails = false;
    this.overlayOpen = true;
  }

  private closeOverlay(): void {
    this.selectedEntry = undefined;
    this.showTechnicalDetails = false;
    this.overlayOpen = false;
  }

  private applyKeyword(): void {
    this.appliedKeyword = this.keywordInput.trim();
    void this.reload();
  }

  private hasActiveFilter(): boolean {
    return this.selectedBundle.length > 0 || this.appliedKeyword.length > 0 || this.range !== 'all';
  }

}
