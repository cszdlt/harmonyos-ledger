import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { connection } from '@kit.ConnectivityKit';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { NotificationProbeSnapshot, clearNotificationProbe, emptyNotificationProbe, loadNotificationProbe } from '../services/NotificationProbeStore';
import { LedgerRepository } from '../data/LedgerRepository';
import {
  EntryDirection,
  EntrySource,
  LedgerEntry,
  formatDateOnly,
  formatDateTime,
  formatMoney,
  hasClockTime,
  makeId,
  parseAmountFen,
  parseDateTime
} from '../model/LedgerModels';
import { LedgerDayGroup, LedgerHomeView } from './ledger/LedgerHomeView';
import { LedgerEditorView } from './ledger/LedgerEditorView';
import { StatisticsRange, statisticsRange } from '../services/LedgerStatistics';
import { StatisticsView } from './statistics/StatisticsView';
import { CsvExporter } from '../services/CsvExporter';
import { CsvImporter } from '../services/CsvImporter';
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
import { SettingsView } from '../components/settings/SettingsView';
import { NotificationSettingsView, PairedNotificationDevice } from '../components/settings/NotificationSettingsView';
import { NotificationHistoryView } from './notifications/NotificationHistoryView';
import { NotificationRuleSettingsView } from './notifications/NotificationRuleSettingsView';
import { OcrRuleSettingsView } from './ocr/OcrRuleSettingsView';

interface CsvImportDialogResponse {
  index: number;
}

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
  private screen: 'ledger' | 'editor' | 'statistics' | 'import' | 'settings' | 'ocrRules' = 'ledger';
  @State
  @Watch('onMainTabNavigationChanged')
  private mainTabNavigation: MainTabNavigationState = initialMainTabNavigationState();
  @State private notificationProbe: NotificationProbeSnapshot = emptyNotificationProbe();
  @State private notificationHistoryOverlayOpen: boolean = false;
  @State private notificationHistoryBackRequestRevision: number = 0;
  @State private ocrImportSessionRevision: number = 0;
  @State private ocrImportBackRequestRevision: number = 0;
  @State private notificationPermissionStatus: string = '尚未检查';
  @State private notificationSubscriptionStatus: string = '尚未检查';
  @State private pairedBluetoothDevices: PairedNotificationDevice[] = [];
  @State private showNotificationAdvancedHelp: boolean = false;
  private sharedImportUris: string[] = [];
  @State private entries: LedgerEntry[] = [];
  @State private entriesViewRevision: number = 0;
  @State private ready: boolean = false;
  @State private errorMessage: string = '';
  @State private pendingDeleteId: string = '';
  @State private statisticsEditorOpen: boolean = false;
  @State private selectedRankValue: string = '';
  @State private pendingDiscardConfirmation: boolean = false;
  @State private editorDirty: boolean = false;
  @State private editorDateError: string = '';
  @State private editorAmountError: string = '';
  @State private monthCursor: number = Date.now();
  @State private ledgerScrollOffset: number = 0;
  @State private restoreLedgerScrollOnAppear: boolean = false;
  @State private editingId: string = '';
  @State private formMerchant: string = '';
  @State private formDateText: string = '';
  @State private formAmountText: string = '';
  @State private formDirection: EntryDirection = 'expense';
  @State private formCategory: string = '其他';
  @State private formNote: string = '';

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
      void this.refreshNotificationProbe();
    }
    this.refreshEntriesForCurrentScreen();
  }

  private onScreenChanged(): void {
    if (this.isNotificationSettingsVisible()) {
      void this.refreshNotificationProbe();
    }
    this.refreshEntriesForCurrentScreen();
  }

  private onMainTabNavigationChanged(): void {
    if (this.isNotificationSettingsVisible()) {
      void this.refreshNotificationProbe();
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
    if (this.pendingDiscardConfirmation) {
      this.pendingDiscardConfirmation = false;
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
      this.requestLeaveEditor();
      return true;
    }
    if (this.screen === 'statistics') {
      if (this.selectedRankValue.length > 0) {
        this.selectedRankValue = '';
      } else {
        this.screen = 'ledger';
      }
      return true;
    }
    if (this.screen === 'ocrRules') {
      this.screen = 'settings';
      return true;
    }
    if (this.screen === 'settings') {
      this.screen = 'ledger';
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
        } else if (this.pendingDiscardConfirmation) {
          this.discardConfirmationView();
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7F9');
  }

  @Builder
  private ledgerTabContent() {
    if (this.screen === 'settings') {
      SettingsView({
        cycleStartDay: this.cycleStartDay,
        onBack: () => {
          this.screen = 'ledger';
        },
        onCycleStartDayChange: (day: number) => {
          void this.changeCycleStartDay(day);
        },
        onOpenOcrRules: () => {
          this.screen = 'ocrRules';
        },
        onExportCsv: () => {
          void this.exportCsv();
        },
        onImportCsv: () => {
          void this.importCsv();
        }
      });
    } else if (this.screen === 'ocrRules') {
      OcrRuleSettingsView({
        onBack: () => {
          this.screen = 'settings';
        }
      });
    } else if (this.screen === 'statistics') {
      StatisticsView({
        entries: this.entries,
        cycleStartDay: this.cycleStartDay,
        selectedRankValue: $selectedRankValue,
        onBack: () => {
          this.selectedRankValue = '';
          this.screen = 'ledger';
        },
        onEditEntry: (entry: LedgerEntry) => this.openEditor(entry, true),
        onDeleteRequest: (entry: LedgerEntry) => {
          this.pendingDeleteId = entry.id;
        }
      });
    } else {
      LedgerHomeView({
        entriesViewRevision: this.entriesViewRevision,
        monthEntries: this.monthEntries(),
        dayGroups: this.monthEntryGroupsByDay(),
        incomeTotalFen: this.monthTotal('income'),
        expenseTotalFen: this.monthTotal('expense'),
        monthLabel: this.monthLabel(),
        cycleStartDay: this.cycleStartDay,
        scrollOffset: this.ledgerScrollOffset,
        restoreScrollOnAppear: this.restoreLedgerScrollOnAppear,
        onSaveScroll: (offset: number) => {
          this.ledgerScrollOffset = Math.max(0, offset);
          this.restoreLedgerScrollOnAppear = true;
        },
        onRestoreScrollComplete: () => {
          this.restoreLedgerScrollOnAppear = false;
        },
        onPreviousMonth: () => this.moveMonth(-1),
        onNextMonth: () => this.moveMonth(1),
        onOpenStatistics: () => {
          this.selectedRankValue = '';
          this.screen = 'statistics';
        },
        onCycleStartDayChange: (day: number) => {
          void this.changeCycleStartDay(day);
        },
        onStartImport: () => this.openOcrImport(),
        onOpenSettings: () => {
          this.screen = 'settings';
        },
        onAddEntry: () => this.openEditor(),
        onEditEntry: (entry: LedgerEntry) => this.openEditor(entry),
        onDeleteRequest: (entry: LedgerEntry) => {
          this.pendingDeleteId = entry.id;
        },
        sourceLabel: (source: EntrySource) => this.sourceLabel(source)
      });
    }
  }

  @Builder
  private notificationTabContent() {
    if (this.mainTabNavigation.notificationRoute === 'settings') {
      NotificationSettingsView({
        permissionStatus: this.notificationPermissionStatus,
        subscriptionStatus: this.notificationSubscriptionStatus,
        probe: this.notificationProbe,
        pairedDevices: this.pairedBluetoothDevices,
        advancedHelp: this.showNotificationAdvancedHelp,
        onBack: () => {
          this.mainTabNavigation = navigateNotificationTo('history');
        },
        onOpenRules: () => {
          this.mainTabNavigation = navigateNotificationTo('rules');
        },
        onOpenPermission: () => {
          void this.openNotificationSubscriptionSettings();
        },
        onRefresh: () => {
          void this.refreshNotificationProbe();
        },
        onFindDevices: () => {
          void this.loadPairedBluetoothDevices();
        },
        onSubscribeDevice: (device: PairedNotificationDevice) => {
          void this.subscribeToPairedDevice(device);
        },
        onShowRecentNotification: () => {
          void this.showNotificationProbeDetails();
        },
        onClearDiagnostics: () => {
          void this.clearNotificationProbeState();
        },
        onToggleAdvancedHelp: () => {
          this.showNotificationAdvancedHelp = !this.showNotificationAdvancedHelp;
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
    LedgerEditorView({
      editingId: this.editingId,
      merchant: this.formMerchant,
      dateText: this.formDateText,
      amountText: this.formAmountText,
      entryDirection: this.formDirection,
      category: this.formCategory,
      note: this.formNote,
      dateError: this.editorDateError,
      amountError: this.editorAmountError,
      onBack: () => this.requestLeaveEditor(),
      onSave: () => {
        void this.saveEditor();
      },
      onChooseDate: () => this.chooseEditorDate(),
      onFieldChange: (field: string, value: string) => this.setFormValue(field, value),
      onDirectionChange: (direction: EntryDirection) => {
        this.editorDirty = this.editorDirty || this.formDirection !== direction;
        this.formDirection = direction;
      }
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
      LedgerEditorView({
        editingId: this.editingId,
        merchant: this.formMerchant,
        dateText: this.formDateText,
        amountText: this.formAmountText,
        entryDirection: this.formDirection,
        category: this.formCategory,
        note: this.formNote,
        dateError: this.editorDateError,
        amountError: this.editorAmountError,
        onBack: () => this.requestLeaveEditor(),
        onSave: () => {
          void this.saveEditor();
        },
        onChooseDate: () => this.chooseEditorDate(),
        onFieldChange: (field: string, value: string) => this.setFormValue(field, value),
        onDirectionChange: (direction: EntryDirection) => {
          this.editorDirty = this.editorDirty || this.formDirection !== direction;
          this.formDirection = direction;
        }
      });
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

  @Builder
  private discardConfirmationView() {
    Column() {
      Column({ space: 10 }) {
        Text('有内容尚未保存，确定放弃并离开吗？')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#344563');
        Row({ space: 10 }) {
          Button('继续编辑')
            .layoutWeight(1)
            .backgroundColor('#F1F3F5')
            .fontColor('#344563')
            .onClick(() => {
              this.pendingDiscardConfirmation = false;
            });
          Button('放弃并离开')
            .layoutWeight(1)
            .backgroundColor('#B42318')
            .fontColor('#FFFFFF')
            .onClick(() => this.discardEditor());
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
    .backgroundColor('#66000000')
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

  private async openNotificationSubscriptionSettings(): Promise<void> {
    this.notificationPermissionStatus = '正在打开通知授权设置…';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await notificationExtensionSubscription.openSubscriptionSettingsWithResult(context);
      await this.refreshNotificationProbe();
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationPermissionStatus = '打开失败（' + businessError.code + '）：' + businessError.message;
    }
  }

  private async loadPairedBluetoothDevices(): Promise<void> {
    this.notificationSubscriptionStatus = '正在读取已配对设备…';
    this.pairedBluetoothDevices = [];
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const grant = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context, ['ohos.permission.ACCESS_BLUETOOTH']);
      if (grant.authResults[0] !== 0) {
        this.notificationSubscriptionStatus = '未获得蓝牙访问权限';
        return;
      }
      const addresses = connection.getPairedDevices();
      const devices: PairedNotificationDevice[] = [];
      for (const address of addresses) {
        let label = address;
        try {
          const name = connection.getRemoteDeviceName(address);
          if (name.length > 0) {
            label = name + '（' + address.slice(-5) + '）';
          }
        } catch (_error) {
          label = address;
        }
        devices.push({ address: address, label: label });
      }
      this.pairedBluetoothDevices = devices;
      this.notificationSubscriptionStatus = devices.length > 0 ?
        '请选择需要订阅通知的穿戴设备' : '未找到已配对蓝牙设备';
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationSubscriptionStatus = '读取设备失败（' + businessError.code + '）：' + businessError.message;
    }
  }

  private async subscribeToPairedDevice(device: PairedNotificationDevice): Promise<void> {
    this.notificationSubscriptionStatus = '正在订阅 ' + device.label + '…';
    try {
      await notificationExtensionSubscription.subscribe([{
        type: notificationExtensionSubscription.SubscribeType.BLUETOOTH,
        addr: device.address
      }]);
      await this.refreshNotificationProbe();
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationSubscriptionStatus = '订阅失败（' + businessError.code + '）：' + businessError.message;
    }
  }

  private async refreshNotificationProbe(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      this.notificationProbe = await loadNotificationProbe(context);
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationPermissionStatus = '读取本地诊断状态失败：' + businessError.message;
      return;
    }
    try {
      const subscriptions = await notificationExtensionSubscription.getSubscribeInfo();
      this.notificationSubscriptionStatus = subscriptions.length > 0 ?
        '已订阅 ' + subscriptions.length + ' 个设备（地址尾号：' +
        subscriptions.map((subscription) => subscription.addr.slice(-5)).join('、') + '）' :
        '尚未订阅穿戴设备';
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationSubscriptionStatus = '查询订阅失败（' + businessError.code + '）：' + businessError.message;
    }
    try {
      const isGranted = await notificationExtensionSubscription.isUserGranted();
      if (!isGranted) {
        this.notificationPermissionStatus = '本机通知访问尚未开启';
        return;
      }
      const enabledBundles = await notificationExtensionSubscription.getUserGrantedEnabledBundles();
      this.notificationPermissionStatus = '本机通知访问已开启，已选择 ' + enabledBundles.length + ' 个来源应用';
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationPermissionStatus = '权限或设备暂不支持查询：' + businessError.message;
    }
  }

  private async showNotificationProbeDetails(): Promise<void> {
    await this.refreshNotificationProbe();
    const sourceName = this.notificationProbe.appName.length > 0 ?
      this.notificationProbe.appName : this.notificationProbe.bundleName;
    const title = this.notificationProbe.title.length > 0 ? this.notificationProbe.title : '（无标题）';
    const body = this.notificationProbe.body.length > 0 ? this.notificationProbe.body : '（无正文）';
    const message = '来源：' + sourceName +
      '\n时间：' + formatDateTime(this.notificationProbe.deliveryTime) +
      '\n标题：' + title +
      '\n正文：' + body;
    try {
      await this.getUIContext().getPromptAction().showDialog({
        title: '最近收到的通知',
        message: message,
        buttons: [{ text: '关闭', color: '#2457C5' }]
      });
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationPermissionStatus = '打开通知详情失败（' + businessError.code + '）：' + businessError.message;
    }
  }

  private async clearNotificationProbeState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await clearNotificationProbe(context);
      await this.refreshNotificationProbe();
    } catch (error) {
      const businessError = error as BusinessError;
      this.notificationPermissionStatus = '清除诊断记录失败：' + businessError.message;
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

  private monthRange(): StatisticsRange {
    return statisticsRange('month', this.monthCursor, 0, 0, this.cycleStartDay);
  }

  private monthEntries(): LedgerEntry[] {
    const range = this.monthRange();
    return this.entries.filter((entry: LedgerEntry) =>
      entry.happenedAt >= range.start && entry.happenedAt < range.endExclusive);
  }

  private monthEntryGroupsByDay(): LedgerDayGroup[] {
    const groups: LedgerDayGroup[] = [];
    this.monthEntries().forEach((entry: LedgerEntry) => {
      const dateKey = formatDateOnly(entry.happenedAt);
      let group = groups.find((item: LedgerDayGroup) => item.dateKey === dateKey);
      if (group === undefined) {
        group = { dateKey: dateKey, entries: [], expenseTotalFen: 0, incomeTotalFen: 0 };
        groups.push(group);
      }
      group.entries.push(entry);
      if (entry.direction === 'expense') {
        group.expenseTotalFen += entry.amountFen;
      } else {
        group.incomeTotalFen += entry.amountFen;
      }
    });
    return groups;
  }

  private monthTotal(direction: EntryDirection): number {
    let total = 0;
    this.monthEntries().forEach((entry: LedgerEntry) => {
      if (entry.direction === direction) {
        total += entry.amountFen;
      }
    });
    return total;
  }

  private monthLabel(): string {
    const range = this.monthRange();
    const start = new Date(range.start);
    const end = new Date(range.endExclusive - 24 * 60 * 60 * 1000);
    const endYear = start.getFullYear() === end.getFullYear() ? '' : end.getFullYear() + '年';
    return start.getFullYear() + '年' + (start.getMonth() + 1) + '月' + start.getDate() +
      '日—' + endYear + (end.getMonth() + 1) + '月' + end.getDate() + '日';
  }

  private moveMonth(offset: number): void {
    const date = new Date(this.monthCursor);
    this.monthCursor = new Date(date.getFullYear(), date.getMonth() + offset, 1).getTime();
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
    this.editorDirty = false;
    this.editorDateError = '';
    this.editorAmountError = '';
    if (entry === undefined) {
      this.editingId = '';
      this.formMerchant = '';
      this.formDateText = formatDateTime(Date.now());
      this.formAmountText = '';
      this.formDirection = 'expense';
      this.formCategory = '其他';
      this.formNote = '';
    } else {
      this.editingId = entry.id;
      this.formMerchant = entry.merchant;
      this.formDateText = entry.hasTime ? formatDateTime(entry.happenedAt) : formatDateOnly(entry.happenedAt);
      this.formAmountText = (entry.amountFen / 100).toFixed(2);
      this.formDirection = entry.direction;
      this.formCategory = entry.category;
      this.formNote = entry.note;
    }
    if (fromStatistics) {
      this.statisticsEditorOpen = true;
    } else {
      this.statisticsEditorOpen = false;
      this.screen = 'editor';
    }
  }

  private setFormValue(field: string, value: string): void {
    if (field === 'merchant') {
      this.editorDirty = this.editorDirty || this.formMerchant !== value;
      this.formMerchant = value;
    } else if (field === 'date') {
      this.editorDirty = this.editorDirty || this.formDateText !== value;
      this.formDateText = value;
      this.editorDateError = '';
    } else if (field === 'amount') {
      this.editorDirty = this.editorDirty || this.formAmountText !== value;
      this.formAmountText = value;
      this.editorAmountError = '';
    } else if (field === 'category') {
      this.editorDirty = this.editorDirty || this.formCategory !== value;
      this.formCategory = value;
    } else {
      this.editorDirty = this.editorDirty || this.formNote !== value;
      this.formNote = value;
    }
  }

  private chooseEditorDate(): void {
    const current = parseDateTime(this.formDateText) ?? Date.now();
    const uiContext = this.getUIContext();
    uiContext.showDatePickerDialog({
      selected: new Date(current),
      onDateAccept: (date: Date) => {
        const selected = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        const time = this.formDateText.trim().match(/(?:^|\s)(\d{1,2}):(\d{2})$/);
        const dateText = formatDateOnly(selected);
        const value = time === null ? dateText : dateText + ' ' +
          String(Number(time[1])).padStart(2, '0') + ':' + time[2];
        uiContext.runScopedTask(() => {
          this.setFormValue('date', value);
        });
      }
    });
  }

  private async saveEditor(): Promise<void> {
    const date = parseDateTime(this.formDateText);
    const amountFen = parseAmountFen(this.formAmountText);
    this.editorDateError = date === undefined ? '请填写有效日期，例如 2026-10-04 18:30。' : '';
    this.editorAmountError = amountFen === undefined || amountFen <= 0 ? '金额需为大于 0 的有效数字。' : '';
    if (this.editorDateError.length > 0 || this.editorAmountError.length > 0 ||
      date === undefined || amountFen === undefined || amountFen <= 0) {
      return;
    }
    const existing = this.findEntry(this.editingId);
    const entry: LedgerEntry = {
      id: this.editingId.length > 0 ? this.editingId : makeId('entry'),
      happenedAt: date,
      hasTime: hasClockTime(this.formDateText),
      amountFen: amountFen,
      direction: this.formDirection,
      source: existing === undefined ? 'manual' : existing.source,
      merchant: this.formMerchant.trim(),
      category: this.formCategory.trim().length > 0 ? this.formCategory.trim() : '其他',
      note: this.formNote.trim()
    };
    try {
      if (this.editingId.length > 0) {
        await this.repository.updateEntry(entry);
      } else {
        await this.repository.addEntry(entry);
      }
      await this.reloadEntries();
      const editingFromStatistics = this.statisticsEditorOpen;
      if (!editingFromStatistics) {
        this.monthCursor = date;
      }
      this.editorDirty = false;
      if (editingFromStatistics) {
        this.statisticsEditorOpen = false;
      } else {
        this.screen = 'ledger';
      }
      this.showToast('账目已保存');
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('保存失败：' + businessError.message);
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

  private requestLeaveEditor(): void {
    if (this.editorDirty) {
      this.pendingDiscardConfirmation = true;
      return;
    }
    this.discardEditor();
  }

  private discardEditor(): void {
    const editingFromStatistics = this.statisticsEditorOpen;
    this.pendingDiscardConfirmation = false;
    this.editorDirty = false;
    this.editorDateError = '';
    this.editorAmountError = '';
    if (editingFromStatistics) {
      this.statisticsEditorOpen = false;
    } else {
      this.screen = 'ledger';
    }
  }

  private async exportCsv(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const entries = await this.repository.listEntries();
      const exported = await CsvExporter.export(context, entries);
      this.showToast(exported ? 'CSV 已导出' : '已取消导出');
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('导出失败：' + businessError.message);
    }
  }

  private async importCsv(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const existingEntries = await this.repository.listEntries();
      const preview = await CsvImporter.selectAndPreview(context, existingEntries);
      if (preview === undefined) {
        this.showToast('已取消 CSV 导入');
        return;
      }
      if (preview.rowCount === 0) {
        this.showToast('CSV 中没有账目记录');
        return;
      }

      let message = '账目记录：' + preview.rowCount + ' 条' +
        '\n可导入：' + preview.entries.length + ' 条' +
        '\n与现有账本完全相同，跳过：' + preview.duplicateCount + ' 条' +
        '\n格式无效，不导入：' + preview.invalidRows.length + ' 条';
      preview.invalidRows.slice(0, 5).forEach((problem) => {
        message += '\n第 ' + problem.recordNumber + ' 条数据：' + problem.message;
      });
      if (preview.invalidRows.length > 5) {
        message += '\n其余 ' + (preview.invalidRows.length - 5) + ' 条无效记录未展开';
      }

      if (preview.entries.length === 0) {
        await this.getUIContext().getPromptAction().showDialog({
          title: 'CSV 导入预览',
          message: message,
          buttons: [{ text: '关闭', color: '#2457C5' }]
        });
        return;
      }
      this.getUIContext().getPromptAction().showDialog({
        title: 'CSV 导入预览',
        message: message,
        buttons: [
          { text: '取消', color: '#52606D' },
          { text: '导入 ' + preview.entries.length + ' 条', color: '#2457C5' }
        ]
      }, (error: BusinessError, response: CsvImportDialogResponse) => {
        if (error) {
          this.showToast('打开 CSV 导入预览失败：' + error.message);
          return;
        }
        if (response.index !== 1) {
          this.showToast('已取消 CSV 导入');
          return;
        }
        void this.saveCsvEntries(preview.entries, preview.duplicateCount, preview.invalidRows.length);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      this.showToast('CSV 导入失败：' + businessError.message);
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
