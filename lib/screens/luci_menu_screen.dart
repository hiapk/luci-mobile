import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/screens/luci_webview_screen.dart';
import 'package:luci_mobile/services/luci_menu_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

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
      MaterialPageRoute<void>(
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
      'quickstart' => Icons.home_outlined,
      'network_guide' => Icons.assistant_navigation,
      'status' => Icons.monitor_heart_outlined,
      'system' => Icons.settings_outlined,
      'store' => Icons.shopping_bag_outlined,
      'docker' => Icons.inventory_2_outlined,
      'services' => Icons.miscellaneous_services_outlined,
      'network' => Icons.account_tree_outlined,
      'vpn' => Icons.vpn_key_outlined,
      _ => Icons.open_in_browser_outlined,
    };
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

    return Scaffold(
      appBar: LuciAppBar(
        title: 'LuCI 管理',
        actions: [
          IconButton(
            onPressed: () => _refresh(appState),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新菜单',
          ),
        ],
      ),
      body: FutureBuilder<List<LuciMenuItem>>(
        future: _menuFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return LuciErrorDisplay(
              title: '菜单加载失败',
              message: snapshot.error.toString(),
              onAction: () => _refresh(appState),
            );
          }

          final items = _filterMenu(snapshot.data ?? const []);
          return RefreshIndicator(
            onRefresh: () async {
              _refresh(appState);
              await _menuFuture;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '搜索菜单',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear_rounded),
                            tooltip: '清除',
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: Text('没有匹配的菜单')),
                  ),
                ...items.map((item) {
                  if (item.children.isEmpty) {
                    return ListTile(
                      leading: Icon(_iconFor(item.key)),
                      title: Text(item.title),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                      onTap: () => _openItem(appState, item),
                    );
                  }
                  return ExpansionTile(
                    key: PageStorageKey<String>('luci-menu-${item.key}'),
                    initiallyExpanded: _query.isNotEmpty,
                    leading: Icon(_iconFor(item.key)),
                    title: Text(item.title),
                    children: item.children
                        .map(
                          (child) => ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 72,
                              right: 16,
                            ),
                            title: Text(child.title),
                            trailing: const Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                            ),
                            onTap: () => _openItem(appState, child),
                          ),
                        )
                        .toList(),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
