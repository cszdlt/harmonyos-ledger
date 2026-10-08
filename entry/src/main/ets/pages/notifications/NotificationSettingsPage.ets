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

  aboutToAppear(): void {
    this.refreshProbeForRevision();
  }


  private onProbeRevisionChanged(): void {
    this.refreshProbeForRevision();
  }


  private refreshProbeForRevision(): void {
    if (this.handledProbeRevision === this.probeRevision) {
      return;
    }
    this.handledProbeRevision = this.probeRevision;
    void this.refreshNotificationProbe();
  }

  build() {
    NotificationSettingsView({
      permissionStatus: this.permissionStatus,
      subscriptionStatus: this.subscriptionStatus,
      probe: this.probe,
      pairedDevices: this.pairedDevices,
      advancedHelp: this.advancedHelp,
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