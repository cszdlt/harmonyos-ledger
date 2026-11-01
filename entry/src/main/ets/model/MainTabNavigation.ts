export type MainTab = 'ledger' | 'notifications';

export type NotificationRoute = 'history' | 'settings' | 'rules';

export interface MainTabNavigationState {
  activeTab: MainTab;
  notificationRoute: NotificationRoute;
}

export function initialMainTabNavigationState(): MainTabNavigationState {
  return {
    activeTab: 'ledger',
    notificationRoute: 'history'
  };
}

export function selectMainTab(state: MainTabNavigationState, activeTab: MainTab): MainTabNavigationState {
  return {
    activeTab: activeTab,
    notificationRoute: 'history'
  };
}

export function navigateNotificationTo(notificationRoute: NotificationRoute): MainTabNavigationState {
  return {
    activeTab: 'notifications',
    notificationRoute: notificationRoute
  };
}

export function backNotificationRoute(state: MainTabNavigationState): MainTabNavigationState | undefined {
  if (state.notificationRoute === 'rules') {
    return navigateNotificationTo('settings');
  }
  if (state.notificationRoute === 'settings') {
    return navigateNotificationTo('history');
  }
  return selectMainTab(state, 'ledger');
}
