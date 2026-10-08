import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { LedgerRepository } from '../data/LedgerRepository';
import {
  EntrySource,
  LedgerEntry,
  formatDateOnly,
  formatDateTime,
  formatMoney
} from '../model/LedgerModels';
import { LedgerEditorPage } from './ledger/LedgerEditorPage';
import { LedgerTabPage } from './ledger/LedgerTabPage';
import type { LedgerScreen } from './ledger/LedgerTabPage';
import { OcrDraftConfirmationPlan } from '../services/OcrImportCoordinator';
import { OcrImportPage, OcrImportSaveResult } from './import/OcrImportPage';
import {
  backNotificationRoute,
  initialMainTabNavigationState,
  MainTabNavigationState,
  navigateNotificationTo,
  selectMainTab
} from '../model/MainTabNavigation';
import { indexStorage } from '../state/IndexStorage';
import { NotificationSettingsPage } from './notifications/NotificationSettingsPage';
import { NotificationHistoryView } from './notifications/NotificationHistoryView';
import { NotificationRuleSettingsView } from './notifications/NotificationRuleSettingsView';

@Entry(indexStorage)
@Component
struct Index {
  @LocalStorageLink('shareImportMode') private shareImportMode: boolean = false;
  @LocalStorageLink('sharedImageUris') private sharedImageUris: string[] = [];
  @LocalStorageLink('shareImportError') private sharedImportError: string = '';
  @LocalStorageLink('ledgerRefreshRevision')
  @Watch('onLedgerRefreshRevisionChanged')
  private ledgerRefreshRevision: number = 0;
  @State
  @Watch('onScreenChanged')
  private screen: LedgerScreen = 'ledger';
  @State
  @Watch('onMainTabNavigationChanged')
  private mainTabNavigation: MainTabNavigationState = initialMainTabNavigationState();
  @State private notificationHistoryOverlayOpen: boolean = false;
  @State private notificationHistoryBackRequestRevision: number = 0;
  @State private notificationProbeRefreshRevision: number = 0;
  @State private ocrImportSessionRevision: number = 0;
  @State private ocrImportBackRequestRevision: number = 0;
  @State private ledgerTabBackRequestRevision: number = 0;
  @State private editorSessionRevision: number = 0;
  @State private editorBackRequestRevision: number = 0;
  private sharedImportUris: string[] = [];
  @State private entries: LedgerEntry[] = [];
  @State private entriesViewRevision: number = 0;
  @State private ready: boolean = false;
  @State private errorMessage: string = '';
  @State private pendingDeleteId: string = '';
  @State private statisticsEditorOpen: boolean = false;
  @State private monthCursor: number = Date.now();
  @State private editingId: string = '';

  @State private cycleStartDay: number = 15;
  private settingsPreferences: preferences.Preferences | undefined = undefined;
  private repository: LedgerRepository = new LedgerRepository();
  private ledgerEntriesChangedObserver: (() => void) | undefined = undefined;
  private pendingLedgerEntriesRefresh: boolean = false;
  private entriesReloadRequestId: number = 0;

  aboutToAppear(): void {
    void this.initialize();
  }

  aboutToDisappear(): void {
    if (this.ledgerEntriesChangedObserver !== undefined) {
      this.repository.removeLedgerEntriesChangedObserver(this.ledgerEntriesChangedObserver);
      this.ledgerEntriesChangedObserver = undefined;
    }
  }

  private onLedgerRefreshRevisionChanged(): void {
    if (this.isNotificationSettingsVisible()) {
      this.notificationProbeRefreshRevision++;
    }
    this.refreshEntriesForCurrentScreen();
  }

  private onScreenChanged(): void {
    if (this.isNotificationSettingsVisible()) {
      this.notificationProbeRefreshRevision++;
    }
    this.refreshEntriesForCurrentScreen();
  }

  private onMainTabNavigationChanged(): void {
    if (this.isNotificationSettingsVisible()) {
      this.notificationProbeRefreshRevision++;
    }
    this.refreshEntriesForCurrentScreen();
  }

  private isNotificationSettingsVisible(): boolean {
    return this.mainTabNavigation.activeTab === 'notifications' &&
      (this.mainTabNavigation.notificationRoute === 'settings' ||
        this.mainTabNavigation.notificationRoute === 'rules');
  }

  private refreshEntriesForCurrentScreen(): void {
    if (!this.ready || this.shareImportMode || this.mainTabNavigation.activeTab !== 'ledger' ||
      this.screen === 'settings' || this.screen === 'ocrRules') {
      return;
    }
    void this.reloadEntriesSafely();
  }

  private async reloadEntriesSafely(): Promise<void> {
    try {
      await this.reloadEntries();
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('刷新账目失败：' + businessError.message);
    }
  }

  onBackPress(): boolean {
    if (this.pendingDeleteId.length > 0) {
      this.pendingDeleteId = '';
      return true;
    }
    if (this.screen === 'import' || this.shareImportMode) {
      this.ocrImportBackRequestRevision++;
      return true;
    }
    if (this.mainTabNavigation.activeTab === 'notifications') {
      if (this.mainTabNavigation.notificationRoute === 'history') {
        if (this.notificationHistoryOverlayOpen) {
          this.notificationHistoryBackRequestRevision++;
          return true;
        }
        return false;
      }
      const previousRoute = backNotificationRoute(this.mainTabNavigation);
      if (previousRoute !== undefined) {
        this.mainTabNavigation = previousRoute;
        return true;
      }
      return false;
    }
    if (this.statisticsEditorOpen || this.screen === 'editor') {
      this.editorBackRequestRevision++;
      return true;
    }
    if (this.screen === 'statistics' || this.screen === 'settings' || this.screen === 'ocrRules') {
      this.ledgerTabBackRequestRevision++;
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      if (!this.ready) {
        this.loadingView();
      } else if (this.shareImportMode) {
        this.ocrImportScreen();
      } else {

        Tabs({
          barPosition: BarPosition.End,
          index: this.mainTabNavigation.activeTab === 'ledger' ? 0 : 1
        }) {
          TabContent() {
            this.ledgerTabContent();
          }
          .tabBar('账本');

          TabContent() {
            this.notificationTabContent();
          }
          .tabBar('通知');
        }
        .width('100%')
        .height('100%')
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .barHeight(this.shareImportMode || this.screen === 'editor' || this.screen === 'import' ? 0 : 60)
        .barBackgroundColor('#FFFFFF')
        .onContentWillChange((currentIndex: number, comingIndex: number) => {
          return currentIndex === comingIndex ||
            (!this.shareImportMode && this.screen !== 'editor' && this.screen !== 'import');
        })
        .onChange((index: number) => {
          const selectedTab = index === 0 ? 'ledger' : 'notifications';
          if (this.mainTabNavigation.activeTab !== selectedTab) {
            this.screen = 'ledger';
            this.mainTabNavigation = selectMainTab(this.mainTabNavigation, selectedTab);
          }
        });

        if (this.screen === 'import') {
          this.ocrImportScreen();
        } else if (this.screen === 'editor') {
          this.ledgerEditorScreen();
        }

        if (this.statisticsEditorOpen) {
          this.statisticsEditorOverlay();
        }
        if (this.pendingDeleteId.length > 0) {
          this.deleteConfirmationView();
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7F9');
  }

  @Builder
  private ledgerTabContent() {
    LedgerTabPage({
      screen: $screen,
      monthCursor: $monthCursor,
      pendingDeleteId: $pendingDeleteId,
      backRequestRevision: this.ledgerTabBackRequestRevision,
      entries: this.entries,
      entriesViewRevision: this.entriesViewRevision,
      cycleStartDay: this.cycleStartDay,
      sourceLabel: (source: EntrySource) => this.sourceLabel(source),
      onOpenEditor: (entry: LedgerEntry | undefined, fromStatistics: boolean) =>
        this.openEditor(entry, fromStatistics),
      onStartImport: () => this.openOcrImport(),
      onCycleStartDayChange: (day: number) => {
        void this.changeCycleStartDay(day);
      },
      onListEntries: () => this.repository.listEntries(),
      onSaveCsvEntries: (entries: LedgerEntry[], duplicateCount: number, invalidCount: number) =>
        this.saveCsvEntries(entries, duplicateCount, invalidCount),
      onToast: (message: string) => this.showToast(message)
    });
  }

  @Builder
  private notificationTabContent() {
    if (this.mainTabNavigation.notificationRoute === 'settings') {
      NotificationSettingsPage({
        probeRevision: this.notificationProbeRefreshRevision,
        onBack: () => {
          this.mainTabNavigation = navigateNotificationTo('history');
        },
        onOpenRules: () => {
          this.mainTabNavigation = navigateNotificationTo('rules');
        }
      });
    } else if (this.mainTabNavigation.notificationRoute === 'rules') {
      NotificationRuleSettingsView({
        onBack: () => {
          this.mainTabNavigation = navigateNotificationTo('settings');
        }
      });
    } else {
      NotificationHistoryView({
        overlayOpen: $notificationHistoryOverlayOpen,
        backRequestRevision: $notificationHistoryBackRequestRevision,
        onOpenSettings: () => {
          this.notificationHistoryOverlayOpen = false;
          this.mainTabNavigation = navigateNotificationTo('settings');
        }
      });
    }
  }

  @Builder
  private ocrImportScreen() {
    OcrImportPage({
      entries: this.entries,
      shareImportMode: this.shareImportMode,
      sharedImportUris: this.sharedImportUris,
      sharedImportError: this.sharedImportError,
      sessionRevision: this.ocrImportSessionRevision,
      backRequestRevision: this.ocrImportBackRequestRevision,
      sourceLabel: (source: EntrySource) => this.sourceLabel(source),
      onBack: () => {
        this.screen = 'ledger';
      },
      onToast: (message: string) => this.showToast(message),
      onConfirmDrafts: (plan: OcrDraftConfirmationPlan) => this.saveDrafts(plan)
    });
  }

  @Builder
  private ledgerEditorScreen() {
    this.editorPage();
  }

  @Builder
  private editorPage() {
    LedgerEditorPage({
      editingEntry: this.findEntry(this.editingId),
      sessionRevision: this.editorSessionRevision,
      backRequestRevision: this.editorBackRequestRevision,
      onBack: () => this.closeEditor(),
      onSave: (entry: LedgerEntry, isEditing: boolean) => this.saveEditor(entry, isEditing)
    });
  }

  @Builder
  private loadingView() {
    Column({ space: 12 }) {
      Text(this.errorMessage.length > 0 ? this.errorMessage : '正在打开本地账本…')
        .fontSize(16)
        .fontColor('#52606D');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private statisticsEditorOverlay() {
    Column() {
      this.editorPage();
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7F9')
    .zIndex(1);
  }

  @Builder
  private deleteConfirmationView() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.pendingDeleteId = '';
        });
      Column({ space: 10 }) {
        Text('确定删除这条账目吗？')
          .fontSize(14)
          .fontColor('#344563');
        Text(this.pendingDeleteSummary())
          .width('100%')
          .fontSize(13)
          .fontColor('#7B8794');
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => {
              this.pendingDeleteId = '';
            });
          Button('确认删除')
            .layoutWeight(1)
            .backgroundColor('#B42318')
            .fontColor('#FFFFFF')
            .onClick(() => {
              void this.confirmDelete();
            });
        }
      }
      .width('90%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .onClick(() => {});
    }
    .width('100%')
    .height('100%')
    .zIndex(1);
  }

  private openOcrImport(): void {
    this.ocrImportSessionRevision++;
    this.screen = 'import';
  }

  private async saveDrafts(plan: OcrDraftConfirmationPlan): Promise<OcrImportSaveResult> {
    try {
      for (const entry of plan.categoryUpdates) {
        await this.repository.updateEntry(entry);
      }
      await this.repository.addEntries(plan.additions);
      await this.reloadEntries();
      if (plan.firstSelectedAt !== undefined) {
        this.monthCursor = plan.firstSelectedAt;
      }
      const messages: string[] = [];
      if (plan.additions.length > 0) {
        messages.push('新增 ' + plan.additions.length + ' 笔');
      }
      if (plan.matchedCount > 0) {
        messages.push('匹配已有 ' + plan.matchedCount + ' 笔');
      }
      if (plan.categoryUpdates.length > 0) {
        messages.push('更新分类 ' + plan.categoryUpdates.length + ' 笔');
      }
      return { success: true, message: messages.join('，') };
    } catch (error) {
      const businessError = error as BusinessError;
      return { success: false, message: '保存失败：' + businessError.message };
    }
  }

  private async initialize(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      await this.repository.open(context);
      if (this.ledgerEntriesChangedObserver === undefined) {
        const observer = () => {
          if (!this.ready) {
            this.pendingLedgerEntriesRefresh = true;
            return;
          }
          this.refreshEntriesForCurrentScreen();
        };
        this.repository.observeLedgerEntriesChanged(observer);
        this.ledgerEntriesChangedObserver = observer;
      }
      await this.loadCycleStartDay(context);
      await this.reloadEntries();
      this.ready = true;
      if (this.pendingLedgerEntriesRefresh) {
        this.pendingLedgerEntriesRefresh = false;
        this.refreshEntriesForCurrentScreen();
      }
      if (this.shareImportMode) {
        this.sharedImportUris = this.sharedImageUris.slice();
        this.sharedImageUris = [];
        if (this.sharedImportError.length === 0) {
          if (this.sharedImportUris.length === 0) {
            this.sharedImportError = '没有收到可导入的图片。';
          }
        }
      }
    } catch (error) {
      const businessError = error as BusinessError;
      this.errorMessage = '本地账本打开失败：' + businessError.message;
    }
  }

  private async reloadEntries(): Promise<void> {
    const requestId = ++this.entriesReloadRequestId;
    const entries = await this.repository.listEntries();
    if (requestId === this.entriesReloadRequestId) {
      this.entries = entries;
      this.entriesViewRevision++;
    }
  }

  private async loadCycleStartDay(context: common.Context): Promise<void> {
    try {
      this.settingsPreferences = await preferences.getPreferences(context, 'ledger_settings');
      const savedDay = this.settingsPreferences.getSync('cycleStartDay', 15);
      if (typeof savedDay === 'number' && savedDay >= 1 && savedDay <= 31) {
        this.cycleStartDay = savedDay;
      }
    } catch (error) {
      this.cycleStartDay = 15;
    }
  }

  private async changeCycleStartDay(day: number): Promise<void> {
    this.cycleStartDay = day;
    try {
      if (this.settingsPreferences === undefined) {
        const context = this.getUIContext().getHostContext() as common.Context;
        this.settingsPreferences = await preferences.getPreferences(context, 'ledger_settings');
      }
      await this.settingsPreferences.put('cycleStartDay', day);
      await this.settingsPreferences.flush();
      this.showToast('周期起始日已设为每月 ' + day + ' 号');
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('保存周期起始日失败：' + businessError.message);
    }
  }

  private sourceLabel(source: EntrySource): string {
    if (source === 'manual') {
      return '手动';
    }
    if (source === 'wechat') {
      return '微信支付';
    }
    if (source === 'alipay') {
      return '支付宝';
    }
    if (source === 'icbc') {
      return '工商银行';
    }
    if (source === 'citic') {
      return '中信银行';
    }
    return source;
  }

  private openEditor(entry?: LedgerEntry, fromStatistics: boolean = false): void {
    this.errorMessage = '';
    this.editingId = entry === undefined ? '' : entry.id;
    this.editorSessionRevision++;
    if (fromStatistics) {
      this.statisticsEditorOpen = true;
    } else {
      this.statisticsEditorOpen = false;
      this.screen = 'editor';
    }
  }

  private async saveEditor(entry: LedgerEntry, isEditing: boolean): Promise<boolean> {
    const existing = isEditing ? this.findEntry(entry.id) : undefined;
    const savedEntry: LedgerEntry = {
      id: entry.id,
      happenedAt: entry.happenedAt,
      hasTime: entry.hasTime,
      amountFen: entry.amountFen,
      direction: entry.direction,
      source: existing === undefined ? 'manual' : existing.source,
      merchant: entry.merchant,
      category: entry.category,
      note: entry.note
    };
    try {
      if (isEditing) {
        await this.repository.updateEntry(savedEntry);
      } else {
        await this.repository.addEntry(savedEntry);
      }
      await this.reloadEntries();
      if (!this.statisticsEditorOpen) {
        this.monthCursor = savedEntry.happenedAt;
      }
      this.showToast('账目已保存');
      return true;
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('保存失败：' + businessError.message);
      return false;
    }
  }

  private findEntry(id: string): LedgerEntry | undefined {
    return this.entries.find((entry: LedgerEntry) => entry.id === id);
  }

  private pendingDeleteSummary(): string {
    const entry = this.findEntry(this.pendingDeleteId);
    if (entry === undefined) {
      return '该账目已不存在';
    }
    const dateText = entry.hasTime ? formatDateTime(entry.happenedAt) : formatDateOnly(entry.happenedAt);
    const merchant = entry.merchant.length > 0 ? entry.merchant : '未填写摘要';
    return merchant + ' · ' + formatMoney(entry.amountFen) + '\n' + dateText;
  }

  private async confirmDelete(): Promise<void> {
    try {
      const deletedId = this.pendingDeleteId;
      await this.repository.deleteEntry(deletedId);
      await this.reloadEntries();
      this.pendingDeleteId = '';
      this.showToast('账目已删除');
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('删除失败：' + businessError.message);
    }
  }

  private closeEditor(): void {
    if (this.statisticsEditorOpen) {
      this.statisticsEditorOpen = false;
    } else {
      this.screen = 'ledger';
    }
  }

  private async saveCsvEntries(entries: LedgerEntry[], duplicateCount: number, invalidCount: number): Promise<void> {
    try {
      await this.repository.addEntries(entries);
      await this.reloadEntries();
      this.showToast('导入完成：新增 ' + entries.length + ' 条，跳过重复 ' + duplicateCount +
        ' 条，无效 ' + invalidCount + ' 条');
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('CSV 导入失败：' + businessError.message);
    }
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
