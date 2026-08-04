import 'package:luci_mobile/models/luci_menu_item.dart';

enum LuciPagePresentation { mainTab, nativePage, webView }

enum LuciNativeDestination {
  dashboard,
  logs,
  processes,
  startupServices,
  interfaces,
  routes,
  realtime,
  diagnostics,
  appFilter,
  hddIdle,
  homeAssistant,
  reboot,
  firewallStatus,
  channelAnalysis,
  wireGuardStatus,
  wireless,
  networkRoutes,
  dhcpDns,
  firewallConfig,
  systemSettings,
  administration,
  scheduledTasks,
  mountPoints,
  ledSettings,
  ddns,
  switchConfiguration,
  packageManager,
  storageManagement,
  docker,
  systemUpdate,
  backupFirmware,
  fileTransfer,
  systemTuning,
}

class LuciNavigationPolicy {
  static const Set<String> _hiddenRootKeys = {
    'quickstart',
    'network_guide',
    'vpn',
  };
  static const Set<String> _hiddenChildKeys = {'interfaceconfig', 'luci-fan'};

  static List<LuciMenuItem> filterVisibleRoots(List<LuciMenuItem> items) {
    return items
        .where((item) => !_hiddenRootKeys.contains(item.key))
        .toList(growable: false);
  }

  static List<LuciMenuItem> filterVisibleChildren(List<LuciMenuItem> items) {
    return items
        .where((item) => !_hiddenChildKeys.contains(item.key))
        .toList(growable: false);
  }

  static LuciPagePresentation presentationFor(LuciMenuItem item) {
    if (mainTabIndexFor(item) != null) return LuciPagePresentation.mainTab;
    return nativeDestinationFor(item) == null
        ? LuciPagePresentation.webView
        : LuciPagePresentation.nativePage;
  }

  static bool shouldOpenItemDirectly(LuciMenuItem item) {
    final path = item.pathSegments.join('/');
    return path == 'admin/store' ||
        item.children.isEmpty ||
        nativeDestinationFor(item) != null;
  }

  static int? mainTabIndexFor(LuciMenuItem item) {
    final path = item.pathSegments.join('/');
    if (path == 'admin/status/overview') return 0;
    if (path == 'admin/network/network') return 2;
    return null;
  }

  static LuciNativeDestination? nativeDestinationFor(LuciMenuItem item) {
    final path = item.pathSegments.join('/');
    if (path == 'admin/quickstart' || path.startsWith('admin/quickstart/')) {
      return LuciNativeDestination.dashboard;
    }
    if (path == 'admin/status/logs' || path.startsWith('admin/status/logs/')) {
      return LuciNativeDestination.logs;
    }
    if (path == 'admin/status/processes') {
      return LuciNativeDestination.processes;
    }
    if (path == 'admin/system/startup') {
      return LuciNativeDestination.startupServices;
    }
    if (path == 'admin/system/reboot') {
      return LuciNativeDestination.reboot;
    }
    if (path == 'admin/status/routes') {
      return LuciNativeDestination.routes;
    }
    if (path == 'admin/network/routes') {
      return LuciNativeDestination.networkRoutes;
    }
    if (path == 'admin/status/realtime' ||
        path.startsWith('admin/status/realtime/')) {
      return LuciNativeDestination.realtime;
    }
    if (path == 'admin/network/diagnostics') {
      return LuciNativeDestination.diagnostics;
    }
    if (path == 'admin/services/appfilter') {
      return LuciNativeDestination.appFilter;
    }
    if (path == 'admin/services/hd_idle' || path == 'admin/services/hd-idle') {
      return LuciNativeDestination.hddIdle;
    }
    if (path == 'admin/services/homeassistant') {
      return LuciNativeDestination.homeAssistant;
    }
    if (path == 'admin/status/nftables' || path == 'admin/status/iptables') {
      return LuciNativeDestination.firewallStatus;
    }
    if (path == 'admin/status/channel_analysis') {
      return LuciNativeDestination.channelAnalysis;
    }
    if (path == 'admin/status/wireguard') {
      return LuciNativeDestination.wireGuardStatus;
    }
    if (path == 'admin/network/wireless') {
      return LuciNativeDestination.wireless;
    }
    if (path == 'admin/network/dhcp') {
      return LuciNativeDestination.dhcpDns;
    }
    if (path == 'admin/network/firewall') {
      return LuciNativeDestination.firewallConfig;
    }
    if (path == 'admin/system/system') {
      return LuciNativeDestination.systemSettings;
    }
    if (path == 'admin/system/admin') {
      return LuciNativeDestination.administration;
    }
    if (path == 'admin/system/crontab') {
      return LuciNativeDestination.scheduledTasks;
    }
    if (path == 'admin/system/mounts') {
      return LuciNativeDestination.mountPoints;
    }
    if (path == 'admin/system/leds') {
      return LuciNativeDestination.ledSettings;
    }
    if (path == 'admin/services/ddns') {
      return LuciNativeDestination.ddns;
    }
    if (path == 'admin/network/switch') {
      return LuciNativeDestination.switchConfiguration;
    }
    if (path == 'admin/system/package-manager') {
      return LuciNativeDestination.packageManager;
    }
    if (path == 'admin/system/diskman' ||
        path == 'admin/nas' ||
        path.startsWith('admin/nas/')) {
      return LuciNativeDestination.storageManagement;
    }
    if (path == 'admin/system/flash') {
      return LuciNativeDestination.backupFirmware;
    }
    if (path == 'admin/system/filetransfer') {
      return LuciNativeDestination.fileTransfer;
    }
    return null;
  }
}
