import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { connection } from '@kit.ConnectivityKit';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  NotificationProbeSnapshot,
  clearNotificationProbe,
  emptyNotificationProbe,
  loadNotificationProbe
} from '../../services/NotificationProbeStore';
import { formatDateTime } from '../../model/LedgerModels';
import { NotificationSettingsView, PairedNotificationDevice } from '../../components/settings/NotificationSettingsView';
import { NotificationReminderService } from '../../services/NotificationReminderService';
import { formatReminderMinute, parseReminderMinute, reminderDateKey } from '../../services/NotificationReminderEngine';
import type { NotificationReminderState, ReminderSettingsDraft } from '../../model/NotificationReminderModels';
import { NotificationArchiveRepository } from '../../data/NotificationArchiveRepository';
import type { NotificationSource } from '../../model/NotificationArchiveModels';
import { filterNotificationSources } from '../../model/NotificationArchiveModels';
import { NotificationSourcePicker } from '../../components/notifications/NotificationSourcePicker';

@Component
export struct NotificationSettingsPage {
  @Watch('onProbeRevisionChanged')
  @Prop probeRevision: number = 0;

  onBack: () => void = () => {};
  onOpenRules: () => void = () => {};

  @State private permissionStatus: string = '尚未检查';
  @State private subscriptionStatus: string = '尚未检查';
  @State private probe: NotificationProbeSnapshot = emptyNotificationProbe();
  @State private pairedDevices: PairedNotificationDevice[] = [];
  @State private advancedHelp: boolean = false;
  private handledProbeRevision: number = -1;
  private reminderService: NotificationReminderService = new NotificationReminderService();
  private reminderLoaded: boolean = false;
  @State private reminderDraft: ReminderSettingsDraft = {
    enabled: false, bundleName: '', keyword: '', startTime: '17:00', deadlineTime: '20:00'
  };
  @State private reminderStatus: string = '尚未检查';
  @State private reminderBusy: boolean = false;
  private reminderSourceRepository: NotificationArchiveRepository = new NotificationArchiveRepository();
  private reminderSourceRequest: number = 0;
  @State private reminderSources: NotificationSource[] = [];
  @State private reminderSourcePickerOpen: boolean = false;
  @State private reminderSourceQuery: string = '';
  @State private reminderSourceLoading: boolean = false;
  @State private reminderSourceError: string = '';

  aboutToAppear(): void {
    this.refreshProbeForRevision();
    void this.refreshReminderSettings();
    void this.loadReminderSources();
  }

  aboutToDisappear(): void {
    this.closeReminderSourcePicker();
  }


  private onProbeRevisionChanged(): void {
    this.refreshProbeForRevision();
    void this.refreshReminderSettings();
  }


  private refreshProbeForRevision(): void {
    if (this.handledProbeRevision === this.probeRevision) {
      return;
    }
    this.handledProbeRevision = this.probeRevision;
    void this.refreshNotificationProbe();
  }

  build() {
    Stack() {
      this.settingsContent();
      if (this.reminderSourcePickerOpen) {
        NotificationSourcePicker({
          sources: this.filteredReminderSources(), sourceCount: this.reminderSources.length,
          query: this.reminderSourceQuery, selectedBundle: this.reminderDraft.bundleName,
          loading: this.reminderSourceLoading, error: this.reminderSourceError,
          onSearch: (query: string) => { this.reminderSourceQuery = query; },
          onSelect: (bundleName: string) => this.selectReminderSource(bundleName),
          onClose: () => this.closeReminderSourcePicker(),
          onRefresh: () => { void this.loadReminderSources(); }
        });
      }
    }.width('100%').height('100%');
  }

  @Builder
  private settingsContent() {
    NotificationSettingsView({
      permissionStatus: this.permissionStatus,
      subscriptionStatus: this.subscriptionStatus,
      probe: this.probe,
      pairedDevices: this.pairedDevices,
      advancedHelp: this.advancedHelp,
      reminderDraft: this.reminderDraft,
      reminderStatus: this.reminderStatus,
      reminderBusy: this.reminderBusy,
      reminderSourceLabel: this.reminderSourceLabel(),
      onReminderChange: (field: string, value: string) => this.changeReminderDraft(field, value),
      onReminderToggle: (enabled: boolean) => {
        this.changeReminderDraft('enabled', enabled ? 'true' : 'false');
      },
      onReminderSave: () => { void this.saveReminderSettings(); },
      onReminderRefresh: () => { void this.refreshReminderSettings(); },
      onReminderAuthorize: () => { void this.authorizeReminderCalendar(); },
      onReminderOpenSourcePicker: () => { void this.openReminderSourcePicker(); },
      onBack: () => this.onBack(),
      onOpenRules: () => this.onOpenRules(),
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
        this.advancedHelp = !this.advancedHelp;
      }
    });
  }

  private changeReminderDraft(field: string, value: string): void {
    const draft: ReminderSettingsDraft = {
      enabled: this.reminderDraft.enabled, bundleName: this.reminderDraft.bundleName,
      keyword: this.reminderDraft.keyword, startTime: this.reminderDraft.startTime,
      deadlineTime: this.reminderDraft.deadlineTime
    };
    if (field === 'enabled') { draft.enabled = value === 'true'; }
    if (field === 'bundleName') { draft.bundleName = value; }
    if (field === 'keyword') { draft.keyword = value; }
    if (field === 'startTime') { draft.startTime = value; }
    if (field === 'deadlineTime') { draft.deadlineTime = value; }
    this.reminderDraft = draft;
  }

  private async refreshReminderSettings(): Promise<void> {
    if (this.reminderBusy) { return; }
    this.reminderBusy = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const state = await this.reminderService.refresh(context);
      this.applyReminderState(state, !this.reminderLoaded);
    } catch (error) {
      this.reminderStatus = '读取提醒状态失败：' + (error as Error).message;
    } finally {
      this.reminderBusy = false;
    }
  }

  private async saveReminderSettings(): Promise<void> {
    if (this.reminderBusy) { return; }
    this.reminderBusy = true;
    try {
      if (this.reminderDraft.enabled) { await this.requestReminderCalendarAccess(); }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const state = await this.reminderService.save(context, {
        enabled: this.reminderDraft.enabled, bundleName: this.reminderDraft.bundleName,
        keyword: this.reminderDraft.keyword, startMinute: parseReminderMinute(this.reminderDraft.startTime),
        deadlineMinute: parseReminderMinute(this.reminderDraft.deadlineTime)
      });
      this.applyReminderState(state, true);
    } catch (error) {
      this.reminderStatus = '保存失败：' + (error as Error).message;
    } finally {
      this.reminderBusy = false;
    }
  }

  private applyReminderState(state: NotificationReminderState, updateDraft: boolean): void {
    if (updateDraft) {
      this.reminderDraft = {
        enabled: state.config.enabled, bundleName: state.config.bundleName, keyword: state.config.keyword,
        startTime: formatReminderMinute(state.config.startMinute),
        deadlineTime: formatReminderMinute(state.config.deadlineMinute)
      };
      this.reminderLoaded = true;
    }
    if (state.error.length > 0) {
      this.reminderStatus = state.error;
    } else if (!state.config.enabled) {
      this.reminderStatus = '未启用';
    } else {
      this.reminderStatus = '已安排系统日历周一至周五 ' + formatReminderMinute(state.config.deadlineMinute) + ' 提醒；' +
        (state.matchedDate === reminderDateKey(Date.now()) ? '今天已收到匹配通知，已跳过当天提醒。' :
          '今天尚未收到匹配通知。');
    }
  }

  private async requestReminderCalendarAccess(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const grant = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
      ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
    if (grant.authResults.length !== 2 || grant.authResults.some((result) => result !== 0)) {
      throw new Error('需要日历读写授权才能创建和跳过打卡提醒日程');
    }
  }

  private async authorizeReminderCalendar(): Promise<void> {
    try {
      await this.requestReminderCalendarAccess();
      await this.refreshReminderSettings();
    } catch (error) {
      this.reminderStatus = '日历授权失败：' + (error as Error).message + '，请在系统设置中允许本应用读写日历。';
    }
  }

  private async openReminderSourcePicker(): Promise<void> {
    if (this.reminderBusy) { return; }
    this.reminderSourceQuery = '';
    this.reminderSourcePickerOpen = true;
    await this.loadReminderSources();
  }

  private async loadReminderSources(): Promise<void> {
    const request = ++this.reminderSourceRequest;
    this.reminderSourceLoading = true;
    this.reminderSourceError = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.reminderSourceRepository.open(context);
      const sources = await this.reminderSourceRepository.listSources();
      if (request === this.reminderSourceRequest) {
        this.reminderSources = sources;
      }
    } catch (error) {
      if (request === this.reminderSourceRequest) {
        this.reminderSourceError = '读取通知来源失败：' + (error as Error).message;
      }
    } finally {
      if (request === this.reminderSourceRequest) { this.reminderSourceLoading = false; }
    }
  }

  private closeReminderSourcePicker(): void {
    this.reminderSourcePickerOpen = false;
    this.reminderSourceRequest++;
    this.reminderSourceLoading = false;
  }

  private selectReminderSource(bundleName: string): void {
    if (this.reminderSourceLoading || this.reminderSourceError.length > 0 ||
      !this.reminderSources.some((source: NotificationSource) => source.bundleName === bundleName)) { return; }
    this.changeReminderDraft('bundleName', bundleName);
    this.closeReminderSourcePicker();
  }

  private filteredReminderSources(): NotificationSource[] {
    return filterNotificationSources(this.reminderSources, this.reminderSourceQuery);
  }

  private reminderSourceLabel(): string {
    const bundleName = this.reminderDraft.bundleName;
    if (bundleName.length === 0) { return '选择来源应用'; }
    const source = this.reminderSources.find((source: NotificationSource) => source.bundleName === bundleName);
    return source !== undefined && source.appName.length > 0 ? source.appName : '已保存的来源：' + bundleName;
  }

  private async openNotificationSubscriptionSettings(): Promise<void> {
    this.permissionStatus = '正在打开通知授权设置…';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await notificationExtensionSubscription.openSubscriptionSettingsWithResult(context);
      await this.refreshNotificationProbe();
    } catch (error) {
      const businessError = error as BusinessError;
      this.permissionStatus = '打开失败（' + businessError.code + '）：' + businessError.message;
    }
  }


  private async loadPairedBluetoothDevices(): Promise<void> {
    this.subscriptionStatus = '正在读取已配对设备…';
    this.pairedDevices = [];
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const grant = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context, ['ohos.permission.ACCESS_BLUETOOTH']);
      if (grant.authResults[0] !== 0) {
        this.subscriptionStatus = '未获得蓝牙访问权限';
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
      this.pairedDevices = devices;
      this.subscriptionStatus = devices.length > 0 ?
        '请选择需要订阅通知的穿戴设备' : '未找到已配对蓝牙设备';
    } catch (error) {
      const businessError = error as BusinessError;
      this.subscriptionStatus = '读取设备失败（' + businessError.code + '）：' + businessError.message;
    }
  }


  private async subscribeToPairedDevice(device: PairedNotificationDevice): Promise<void> {
    this.subscriptionStatus = '正在订阅 ' + device.label + '…';
    try {
      await notificationExtensionSubscription.subscribe([{
        type: notificationExtensionSubscription.SubscribeType.BLUETOOTH,
        addr: device.address
      }]);
      await this.refreshNotificationProbe();
    } catch (error) {
      const businessError = error as BusinessError;
      this.subscriptionStatus = '订阅失败（' + businessError.code + '）：' + businessError.message;
    }
  }


  private async refreshNotificationProbe(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      this.probe = await loadNotificationProbe(context);
    } catch (error) {
      const businessError = error as BusinessError;
      this.permissionStatus = '读取本地诊断状态失败：' + businessError.message;
      return;
    }
    try {
      const subscriptions = await notificationExtensionSubscription.getSubscribeInfo();
      this.subscriptionStatus = subscriptions.length > 0 ?
        '已订阅 ' + subscriptions.length + ' 个设备（地址尾号：' +
        subscriptions.map((subscription) => subscription.addr.slice(-5)).join('、') + '）' :
        '尚未订阅穿戴设备';
    } catch (error) {
      const businessError = error as BusinessError;
      this.subscriptionStatus = '查询订阅失败（' + businessError.code + '）：' + businessError.message;
    }
    try {
      const isGranted = await notificationExtensionSubscription.isUserGranted();
      if (!isGranted) {
        this.permissionStatus = '本机通知访问尚未开启';
        return;
      }
      const enabledBundles = await notificationExtensionSubscription.getUserGrantedEnabledBundles();
      this.permissionStatus = '本机通知访问已开启，已选择 ' + enabledBundles.length + ' 个来源应用';
    } catch (error) {
      const businessError = error as BusinessError;
      this.permissionStatus = '权限或设备暂不支持查询：' + businessError.message;
    }
  }


  private async showNotificationProbeDetails(): Promise<void> {
    await this.refreshNotificationProbe();
    const sourceName = this.probe.appName.length > 0 ?
      this.probe.appName : this.probe.bundleName;
    const title = this.probe.title.length > 0 ? this.probe.title : '（无标题）';
    const body = this.probe.body.length > 0 ? this.probe.body : '（无正文）';
    const message = '来源：' + sourceName +
      '\n时间：' + formatDateTime(this.probe.deliveryTime) +
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
      this.permissionStatus = '打开通知详情失败（' + businessError.code + '）：' + businessError.message;
    }
  }


  private async clearNotificationProbeState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await clearNotificationProbe(context);
      await this.refreshNotificationProbe();
    } catch (error) {
      const businessError = error as BusinessError;
      this.permissionStatus = '清除诊断记录失败：' + businessError.message;
    }
  }
}
