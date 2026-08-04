import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/screens/luci_native_screens.dart';
import 'package:luci_mobile/screens/luci_extended_native_screens.dart';
import 'package:luci_mobile/screens/luci_standard_native_screens.dart';
import 'package:luci_mobile/screens/luci_webview_screen.dart';
import 'package:luci_mobile/screens/router_tools_screen.dart';
import 'package:luci_mobile/services/luci_menu_service.dart';
import 'package:luci_mobile/services/luci_navigation_policy.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/native_navigation_bar.dart';

class LuciMenuScreen extends ConsumerStatefulWidget {
  const LuciMenuScreen({super.key});

  @override
  ConsumerState<LuciMenuScreen> createState() => _LuciMenuScreenState();
}

class _LuciMenuScreenState extends ConsumerState<LuciMenuScreen> {
  final LuciMenuService _menuService = LuciMenuService();
  final TextEditingController _searchController = TextEditingController();
  Future<List<LuciMenuItem>>? _menuFuture;
  String? _sessionKey;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<LuciMenuItem>> _fetchMenu(AppState appState) {
    final router = appState.selectedRouter;
    final token = appState.sysauth;
    final cookieName = appState.authCookieName;
    if (router == null || token == null || cookieName == null) {
      return Future.error(const LuciMenuException('当前没有可用的 LuCI 登录会话。'));
    }
    return _menuService.fetchMenu(
      host: router.ipAddress,
      useHttps: router.useHttps,
      cookieName: cookieName,
      token: token,
      context: context,
    );
  }

  void _refresh(AppState appState) {
    setState(() => _menuFuture = _fetchMenu(appState));
  }

  Future<void> _openItem(AppState appState, LuciMenuItem item) async {
    final mainTabIndex = LuciNavigationPolicy.mainTabIndexFor(item);
    if (mainTabIndex != null) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) await navigator.maybePop();
      appState.requestTab(mainTabIndex);
      return;
    }
    final destination = LuciNavigationPolicy.nativeDestinationFor(item);
    if (destination == LuciNativeDestination.dashboard) {
      appState.requestTab(0);
      return;
    }
    if (destination == LuciNativeDestination.interfaces) {
      appState.requestTab(2);
      return;
    }
    if (destination != null) {
      final page = _nativePage(appState, item, destination);
      if (page != null && mounted) {
        await Navigator.of(
          context,
        ).push(CupertinoPageRoute<void>(builder: (_) => page));
        return;
      }
    }
    await _openWebView(appState, item);
  }

  Widget? _nativePage(
    AppState appState,
    LuciMenuItem item,
    LuciNativeDestination destination,
  ) {
    void openAdvanced() {
      unawaited(_openWebView(appState, item));
    }

    return switch (destination) {
      LuciNativeDestination.logs => const RouterLogsScreen(),
      LuciNativeDestination.processes => const RouterProcessesScreen(),
      LuciNativeDestination.startupServices =>
        const RouterStartupServicesScreen(),
      LuciNativeDestination.routes => const RouterRoutesScreen(),
      LuciNativeDestination.realtime => const RouterRealtimeScreen(),
      LuciNativeDestination.diagnostics => const RouterDiagnosticsScreen(),
      LuciNativeDestination.appFilter => AppFilterNativeScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.hddIdle => HddIdleNativeScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.homeAssistant => HomeAssistantNativeScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.reboot => const RouterRebootScreen(),
      LuciNativeDestination.firewallStatus =>
        const RouterFirewallStatusScreen(),
      LuciNativeDestination.channelAnalysis =>
        const RouterChannelAnalysisScreen(),
      LuciNativeDestination.wireGuardStatus =>
        const RouterWireGuardStatusScreen(),
      LuciNativeDestination.wireless => const RouterWirelessScreen(),
      LuciNativeDestination.networkRoutes => const RouterNetworkRoutesScreen(),
      LuciNativeDestination.dhcpDns => const RouterDhcpDnsScreen(),
      LuciNativeDestination.firewallConfig =>
        const RouterFirewallConfigScreen(),
      LuciNativeDestination.systemSettings =>
        const RouterSystemSettingsScreen(),
      LuciNativeDestination.administration =>
        const RouterAdministrationScreen(),
      LuciNativeDestination.scheduledTasks =>
        const RouterScheduledTasksScreen(),
      LuciNativeDestination.mountPoints => const RouterMountPointsScreen(),
      LuciNativeDestination.ledSettings => const RouterLedSettingsScreen(),
      LuciNativeDestination.ddns => const RouterDdnsScreen(),
      LuciNativeDestination.switchConfiguration => const RouterSwitchScreen(),
      LuciNativeDestination.packageManager =>
        const RouterPackageManagerScreen(),
      LuciNativeDestination.storageManagement => RouterStorageManagementScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.docker => RouterDockerScreen(
        initialSection: item.key,
      ),
      LuciNativeDestination.systemUpdate => RouterSystemUpdateScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.backupFirmware => RouterBackupFirmwareScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.fileTransfer => const RouterFileManagerScreen(),
      LuciNativeDestination.systemTuning => RouterSystemTuningScreen(
        onOpenAdvanced: openAdvanced,
      ),
      LuciNativeDestination.dashboard => null,
      LuciNativeDestination.interfaces => null,
    };
  }

  Future<void> _openWebView(AppState appState, LuciMenuItem item) async {
    final router = appState.selectedRouter;
    final token = appState.sysauth;
    final cookieName = appState.authCookieName;
    if (router == null || token == null || cookieName == null) return;

    final uri = LuciMenuService.routerUri(
      host: router.ipAddress,
      useHttps: router.useHttps,
      pathSegments: ['cgi-bin', 'luci', ...item.pathSegments],
    );
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => LuciWebViewScreen(
          title: item.title,
          targetUri: uri,
          router: router,
          cookieName: cookieName,
          token: token,
        ),
      ),
    );
  }

  List<LuciMenuItem> _filterMenu(List<LuciMenuItem> menu) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return menu;

    final filtered = <LuciMenuItem>[];
    for (final item in menu) {
      final children = item.children
          .where((child) => child.title.toLowerCase().contains(query))
          .toList();
      if (item.title.toLowerCase().contains(query)) {
        filtered.add(item);
      } else if (children.isNotEmpty) {
        filtered.add(
          LuciMenuItem(
            key: item.key,
            title: item.title,
            order: item.order,
            pathSegments: item.pathSegments,
            children: children,
          ),
        );
      }
    }
    return filtered;
  }

  IconData _iconFor(String key) {
    return switch (key) {
      'quickstart' => CupertinoIcons.house_fill,
      'network_guide' => CupertinoIcons.map_fill,
      'status' => CupertinoIcons.chart_bar_fill,
      'system' => CupertinoIcons.gear_alt_fill,
      'store' => CupertinoIcons.bag_fill,
      'docker' => CupertinoIcons.cube_box_fill,
      'services' => CupertinoIcons.slider_horizontal_3,
      'network' => CupertinoIcons.rectangle_3_offgrid_fill,
      'vpn' => CupertinoIcons.lock_shield_fill,
      _ => CupertinoIcons.compass_fill,
    };
  }

  Color _colorFor(String key) {
    return switch (key) {
      'quickstart' => CupertinoColors.systemTeal,
      'network_guide' => CupertinoColors.systemOrange,
      'status' => CupertinoColors.systemIndigo,
      'system' => CupertinoColors.systemRed,
      'store' => CupertinoColors.systemPurple,
      'docker' => CupertinoColors.activeBlue,
      'services' => CupertinoColors.systemGreen,
      'network' => CupertinoColors.systemBlue,
      'vpn' => CupertinoColors.systemGrey,
      _ => CupertinoColors.systemBlue,
    };
  }

  void _openSubmenu(AppState appState, LuciMenuItem item) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => _LuciSubmenuScreen(
          item: item,
          onOpenItem: (child) => _openItem(appState, child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final nextSessionKey =
        '${appState.selectedRouter?.id}:${appState.sysauth ?? ''}';
    if (_sessionKey != nextSessionKey) {
      _sessionKey = nextSessionKey;
      _menuFuture = _fetchMenu(appState);
    }

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: NativeNavigationBar(
        context: context,
        middle: const Text('LuCI 管理'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _refresh(appState),
          child: const Icon(CupertinoIcons.refresh, size: 21),
        ),
      ),
      child: SafeArea(
        child: FutureBuilder<List<LuciMenuItem>>(
          future: _menuFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CupertinoActivityIndicator());
            }
            if (snapshot.hasError) {
              return _NativeMenuError(
                message: snapshot.error.toString(),
                onRetry: () => _refresh(appState),
              );
            }

            final items = _filterMenu(snapshot.data ?? const []);
            return ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CupertinoSearchTextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    onSuffixTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    placeholder: '搜索菜单',
                  ),
                ),
                const SizedBox(height: 18),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: Text('没有匹配的菜单')),
                  )
                else
                  CupertinoListSection.insetGrouped(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    children: items
                        .map(
                          (item) => CupertinoListTile(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            leadingSize: 32,
                            leadingToTitle: 12,
                            leading: _MenuIcon(
                              icon: _iconFor(item.key),
                              color: _colorFor(item.key),
                            ),
                            title: Text(item.title),
                            trailing: const CupertinoListTileChevron(),
                            onTap:
                                LuciNavigationPolicy.shouldOpenItemDirectly(
                                  item,
                                )
                                ? () => _openItem(appState, item)
                                : () => _openSubmenu(appState, item),
                          ),
                        )
                        .toList(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LuciSubmenuScreen extends StatelessWidget {
  final LuciMenuItem item;
  final ValueChanged<LuciMenuItem> onOpenItem;

  const _LuciSubmenuScreen({required this.item, required this.onOpenItem});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: NativeNavigationBar(
        context: context,
        middle: Text(item.title),
        previousPageTitle: 'LuCI',
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          children: [
            CupertinoListSection.insetGrouped(
              header: Text(item.title),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: item.children
                  .map(
                    (child) => CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      title: Text(child.title),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => onOpenItem(child),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MenuIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: CupertinoColors.white, size: 19),
    );
  }
}

class _NativeMenuError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _NativeMenuError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 42,
              color: CupertinoColors.systemRed,
            ),
            const SizedBox(height: 14),
            const Text('菜单加载失败'),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton.filled(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
