import 'package:luci_mobile/models/luci_menu_item.dart';

enum LuciPagePresentation { nativePage, webView }

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
}

class LuciNavigationPolicy {
  static const Set<String> _hiddenRootKeys = {'network_guide', 'vpn'};

  static List<LuciMenuItem> filterVisibleRoots(List<LuciMenuItem> items) {
    return items
        .where((item) => !_hiddenRootKeys.contains(item.key))
        .toList(growable: false);
  }

  static LuciPagePresentation presentationFor(LuciMenuItem item) {
    return nativeDestinationFor(item) == null
        ? LuciPagePresentation.webView
        : LuciPagePresentation.nativePage;
  }

  static LuciNativeDestination? nativeDestinationFor(LuciMenuItem item) {
    final path = item.pathSegments.join('/');
    if (path == 'admin/quickstart' ||
        path.startsWith('admin/quickstart/') ||
        path == 'admin/status/overview') {
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
    if (path == 'admin/network/network') {
      return LuciNativeDestination.interfaces;
    }
    if (path == 'admin/status/routes' || path == 'admin/network/routes') {
      return LuciNativeDestination.routes;
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
    if (path == 'admin/services/hd_idle' ||
        path == 'admin/services/hd-idle') {
      return LuciNativeDestination.hddIdle;
    }
    if (path == 'admin/services/homeassistant') {
      return LuciNativeDestination.homeAssistant;
    }
    return null;
  }
}
