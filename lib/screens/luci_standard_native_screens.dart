import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';

class RouterFirewallStatusScreen extends ConsumerStatefulWidget {
  const RouterFirewallStatusScreen({super.key});

  @override
  ConsumerState<RouterFirewallStatusScreen> createState() =>
      _RouterFirewallStatusScreenState();
}

class _RouterFirewallStatusScreenState
    extends ConsumerState<RouterFirewallStatusScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchFirewallStatus(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '防火墙状态',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final entries = data['entries'] is List
              ? (data['entries'] as List).whereType<Map>().toList()
              : const <Map>[];
          final tables = entries
              .where((entry) => entry['table'] is Map)
              .map((entry) => entry['table'] as Map)
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('规则集'),
                children: [
                  NativeValueTile(label: '表', value: '${data['tables'] ?? 0}'),
                  NativeValueTile(label: '链', value: '${data['chains'] ?? 0}'),
                  NativeValueTile(label: '规则', value: '${data['rules'] ?? 0}'),
                  NativeValueTile(label: '集合', value: '${data['sets'] ?? 0}'),
                ],
              ),
              if (tables.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('防火墙表'),
                  children: tables
                      .map(
                        (table) => CupertinoListTile(
                          title: Text(table['name']?.toString() ?? '-'),
                          additionalInfo: Text(
                            table['family']?.toString().toUpperCase() ?? '-',
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RouterChannelAnalysisScreen extends ConsumerStatefulWidget {
  const RouterChannelAnalysisScreen({super.key});

  @override
  ConsumerState<RouterChannelAnalysisScreen> createState() =>
      _RouterChannelAnalysisScreenState();
}

class _RouterChannelAnalysisScreenState
    extends ConsumerState<RouterChannelAnalysisScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchChannelAnalysis(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '信道分析',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final radios = snapshot.data?['radios'] is List
              ? (snapshot.data!['radios'] as List).whereType<Map>().toList()
              : const <Map>[];
          if (radios.isEmpty) {
            return const NativeRouterEmpty(label: '未检测到无线射频');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: radios.map((radio) {
              final info = radio['info'] is Map
                  ? radio['info'] as Map
                  : const {};
              final frequencies = radio['frequencies'] is Map
                  ? radio['frequencies'] as Map
                  : const {};
              final list = frequencies['results'] is List
                  ? frequencies['results'] as List
                  : const [];
              return CupertinoListSection.insetGrouped(
                header: Text(radio['name']?.toString() ?? '无线'),
                children: [
                  NativeValueTile(
                    label: '模式',
                    value: info['mode']?.toString() ?? '-',
                  ),
                  NativeValueTile(
                    label: '信道',
                    value: info['channel']?.toString() ?? '-',
                  ),
                  NativeValueTile(
                    label: '频率',
                    value: info['frequency']?.toString() ?? '-',
                  ),
                  NativeValueTile(label: '可用信道', value: '${list.length}'),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class RouterWireGuardStatusScreen extends ConsumerStatefulWidget {
  const RouterWireGuardStatusScreen({super.key});

  @override
  ConsumerState<RouterWireGuardStatusScreen> createState() =>
      _RouterWireGuardStatusScreenState();
}

class _RouterWireGuardStatusScreenState
    extends ConsumerState<RouterWireGuardStatusScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchWireGuardStatus(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: 'WireGuard',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final interfaces = snapshot.data ?? const {};
          if (interfaces.isEmpty) {
            return const NativeRouterEmpty(label: '没有运行中的 WireGuard 接口');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: interfaces.entries.map((entry) {
              final value = entry.value is Map ? entry.value as Map : const {};
              final peers = value['peers'] is List
                  ? value['peers'] as List
                  : value['peers'] is Map
                  ? (value['peers'] as Map).values.toList()
                  : const [];
              return CupertinoListSection.insetGrouped(
                header: Text(entry.key),
                children: [
                  NativeValueTile(label: '对端', value: '${peers.length}'),
                  NativeValueTile(
                    label: '监听端口',
                    value: value['listen_port']?.toString() ?? '-',
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class RouterWirelessScreen extends ConsumerStatefulWidget {
  const RouterWirelessScreen({super.key});

  @override
  ConsumerState<RouterWirelessScreen> createState() =>
      _RouterWirelessScreenState();
}

class _RouterWirelessScreenState extends ConsumerState<RouterWirelessScreen> {
  final Set<String> _saving = {};
  late Future<Map<String, Map<String, dynamic>>> _future = _load();

  Future<Map<String, Map<String, dynamic>>> _load() =>
      ref.read(appStateProvider).fetchUciSections('wireless', context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _setEnabled(
    String section,
    Map<String, dynamic> config,
    bool enabled,
  ) async {
    setState(() => _saving.add(section));
    try {
      await ref.read(appStateProvider).setUciSection('wireless', section, {
        ...config,
        'disabled': enabled ? '0' : '1',
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _saving.remove(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '无线网络',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final sections = snapshot.data ?? const {};
          final radios = sections.entries
              .where((entry) => entry.value['.type'] == 'wifi-device')
              .toList();
          final networks = sections.entries
              .where((entry) => entry.value['.type'] == 'wifi-iface')
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              if (radios.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('射频'),
                  children: radios.map((entry) {
                    final busy = _saving.contains(entry.key);
                    return CupertinoListTile(
                      title: Text(entry.key),
                      subtitle: Text(
                        '${entry.value['band'] ?? '-'} · 信道 ${entry.value['channel'] ?? '自动'}',
                      ),
                      trailing: busy
                          ? const CupertinoActivityIndicator()
                          : CupertinoSwitch(
                              value: !_boolValue(entry.value['disabled']),
                              onChanged: (value) =>
                                  _setEnabled(entry.key, entry.value, value),
                            ),
                    );
                  }).toList(),
                ),
              if (networks.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('无线网络'),
                  children: networks.map((entry) {
                    final busy = _saving.contains(entry.key);
                    return CupertinoListTile(
                      title: Text(entry.value['ssid']?.toString() ?? entry.key),
                      subtitle: Text(
                        '${entry.value['mode'] ?? '-'} · ${entry.value['encryption'] ?? '无加密'}',
                      ),
                      trailing: busy
                          ? const CupertinoActivityIndicator()
                          : CupertinoSwitch(
                              value: !_boolValue(entry.value['disabled']),
                              onChanged: (value) =>
                                  _setEnabled(entry.key, entry.value, value),
                            ),
                    );
                  }).toList(),
                ),
              if (radios.isEmpty && networks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: NativeRouterEmpty(label: '没有无线配置'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RouterNetworkRoutesScreen extends ConsumerStatefulWidget {
  const RouterNetworkRoutesScreen({super.key});

  @override
  ConsumerState<RouterNetworkRoutesScreen> createState() =>
      _RouterNetworkRoutesScreenState();
}

class _RouterNetworkRoutesScreenState
    extends ConsumerState<RouterNetworkRoutesScreen> {
  late Future<Map<String, Map<String, dynamic>>> _future = _load();

  Future<Map<String, Map<String, dynamic>>> _load() =>
      ref.read(appStateProvider).fetchUciSections('network', context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _addRoute() async {
    final values = await Navigator.of(context).push<Map<String, dynamic>>(
      CupertinoPageRoute(builder: (_) => const _RouteEditorScreen()),
    );
    if (values == null || !mounted) return;
    try {
      await ref
          .read(appStateProvider)
          .addUciSection(
            'network',
            values.remove('.type')?.toString() ?? 'route',
            values,
            context: context,
          );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  Future<void> _delete(String section) async {
    final confirmed = await confirmNativeRouterAction(
      context,
      title: '删除静态路由？',
      message: section,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(appStateProvider)
          .deleteUciSection('network', section, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '静态路由',
      onRefresh: _reload,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _addRoute,
        child: const Icon(CupertinoIcons.add, size: 22),
      ),
      child: FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final routes = (snapshot.data ?? const {}).entries
              .where(
                (entry) =>
                    entry.value['.type'] == 'route' ||
                    entry.value['.type'] == 'route6',
              )
              .toList();
          if (routes.isEmpty) {
            return const NativeRouterEmpty(label: '没有配置静态路由');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                children: routes.map((entry) {
                  final route = entry.value;
                  return CupertinoListTile(
                    title: Text(route['target']?.toString() ?? entry.key),
                    subtitle: Text(
                      '经由 ${route['gateway'] ?? '-'} · ${route['interface'] ?? '-'}',
                    ),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => _delete(entry.key),
                      child: const Icon(
                        CupertinoIcons.trash,
                        color: CupertinoColors.systemRed,
                        size: 20,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RouteEditorScreen extends StatefulWidget {
  const _RouteEditorScreen();

  @override
  State<_RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends State<_RouteEditorScreen> {
  final _target = TextEditingController();
  final _gateway = TextEditingController();
  final _interface = TextEditingController(text: 'wan');
  bool _ipv6 = false;

  @override
  void dispose() {
    _target.dispose();
    _gateway.dispose();
    _interface.dispose();
    super.dispose();
  }

  void _save() {
    if (_target.text.trim().isEmpty || _interface.text.trim().isEmpty) return;
    Navigator.of(context).pop(<String, dynamic>{
      '.type': _ipv6 ? 'route6' : 'route',
      'target': _target.text.trim(),
      if (_gateway.text.trim().isNotEmpty) 'gateway': _gateway.text.trim(),
      'interface': _interface.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('添加路由'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            CupertinoListSection.insetGrouped(
              margin: EdgeInsets.zero,
              children: [
                CupertinoListTile(
                  title: const Text('IPv6'),
                  trailing: CupertinoSwitch(
                    value: _ipv6,
                    onChanged: (value) => setState(() => _ipv6 = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _target,
              placeholder: _ipv6 ? '目标，如 2001:db8::/64' : '目标，如 10.0.0.0/24',
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _gateway,
              placeholder: '网关（可选）',
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _interface,
              placeholder: '接口',
              padding: const EdgeInsets.all(13),
            ),
          ],
        ),
      ),
    );
  }
}

class RouterDhcpDnsScreen extends ConsumerStatefulWidget {
  const RouterDhcpDnsScreen({super.key});

  @override
  ConsumerState<RouterDhcpDnsScreen> createState() =>
      _RouterDhcpDnsScreenState();
}

class _RouterDhcpDnsScreenState extends ConsumerState<RouterDhcpDnsScreen> {
  final Set<String> _saving = {};
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchDhcpDnsOverview(context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _toggleServer(
    String section,
    Map<String, dynamic> config,
    bool enabled,
  ) async {
    setState(() => _saving.add(section));
    try {
      await ref.read(appStateProvider).setUciSection('dhcp', section, {
        ...config,
        'ignore': enabled ? '0' : '1',
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _saving.remove(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: 'DHCP / DNS',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final leases = data['leases'] is List
              ? (data['leases'] as List).whereType<Map>().toList()
              : const <Map>[];
          final config = data['config'] is Map
              ? (data['config'] as Map).map(
                  (key, value) => MapEntry(
                    key.toString(),
                    value is Map
                        ? value.map((k, v) => MapEntry(k.toString(), v))
                        : <String, dynamic>{},
                  ),
                )
              : <String, Map<String, dynamic>>{};
          final servers = config.entries
              .where((entry) => entry.value['.type'] == 'dhcp')
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              if (servers.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('DHCP 服务'),
                  children: servers.map((entry) {
                    final busy = _saving.contains(entry.key);
                    return CupertinoListTile(
                      title: Text(
                        entry.value['interface']?.toString() ?? entry.key,
                      ),
                      subtitle: Text(
                        '${entry.value['start'] ?? '-'} 起 · ${entry.value['limit'] ?? '-'} 个地址 · ${entry.value['leasetime'] ?? '-'}',
                      ),
                      trailing: busy
                          ? const CupertinoActivityIndicator()
                          : CupertinoSwitch(
                              value: !_boolValue(entry.value['ignore']),
                              onChanged: (value) =>
                                  _toggleServer(entry.key, entry.value, value),
                            ),
                    );
                  }).toList(),
                ),
              CupertinoListSection.insetGrouped(
                header: Text('当前租约 ${leases.length}'),
                children: leases.map((lease) {
                  final hostname = lease['hostname']?.toString().trim() ?? '';
                  return CupertinoListTile(
                    title: Text(hostname.isEmpty ? '未知设备' : hostname),
                    subtitle: Text(lease['macaddr']?.toString() ?? '-'),
                    additionalInfo: Text(lease['ipaddr']?.toString() ?? '-'),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterFirewallConfigScreen extends ConsumerStatefulWidget {
  const RouterFirewallConfigScreen({super.key});

  @override
  ConsumerState<RouterFirewallConfigScreen> createState() =>
      _RouterFirewallConfigScreenState();
}

class _RouterFirewallConfigScreenState
    extends ConsumerState<RouterFirewallConfigScreen> {
  final Set<String> _saving = {};
  late Future<Map<String, Map<String, dynamic>>> _future = _load();

  Future<Map<String, Map<String, dynamic>>> _load() =>
      ref.read(appStateProvider).fetchUciSections('firewall', context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _setEnabled(
    String section,
    Map<String, dynamic> config,
    bool enabled,
  ) async {
    setState(() => _saving.add(section));
    try {
      await ref.read(appStateProvider).setUciSection('firewall', section, {
        ...config,
        'enabled': enabled ? '1' : '0',
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _saving.remove(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '防火墙',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final sections = snapshot.data ?? const {};
          const groups = <String, String>{
            'zone': '区域',
            'forwarding': '区域转发',
            'redirect': '端口转发',
            'rule': '通信规则',
            'nat': 'NAT 规则',
            'ipset': 'IP 集合',
          };
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: groups.entries.map((group) {
              final values = sections.entries
                  .where((entry) => entry.value['.type'] == group.key)
                  .toList();
              if (values.isEmpty) return const SizedBox.shrink();
              return CupertinoListSection.insetGrouped(
                header: Text('${group.value} ${values.length}'),
                children: values.map((entry) {
                  final config = entry.value;
                  final busy = _saving.contains(entry.key);
                  final toggleable = const {
                    'redirect',
                    'rule',
                    'nat',
                  }.contains(group.key);
                  final label =
                      config['name']?.toString() ??
                      config['src']?.toString() ??
                      entry.key;
                  final detail = [
                    config['src'],
                    config['dest'],
                    config['proto'],
                    config['dest_port'],
                  ].where((value) => value != null).join(' → ');
                  return CupertinoListTile(
                    title: Text(label),
                    subtitle: detail.isEmpty ? null : Text(detail),
                    additionalInfo: toggleable
                        ? null
                        : Text(config['input']?.toString().toUpperCase() ?? ''),
                    trailing: !toggleable
                        ? null
                        : busy
                        ? const CupertinoActivityIndicator()
                        : CupertinoSwitch(
                            value: config['enabled']?.toString() != '0',
                            onChanged: (value) =>
                                _setEnabled(entry.key, config, value),
                          ),
                  );
                }).toList(),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class RouterSystemSettingsScreen extends ConsumerStatefulWidget {
  const RouterSystemSettingsScreen({super.key});

  @override
  ConsumerState<RouterSystemSettingsScreen> createState() =>
      _RouterSystemSettingsScreenState();
}

class _RouterSystemSettingsScreenState
    extends ConsumerState<RouterSystemSettingsScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchSystemSettings(context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(
    String section,
    Map<String, dynamic> config,
    String option,
    String title,
  ) async {
    final value = await promptNativeRouterText(
      context,
      title: title,
      initialValue: config[option]?.toString() ?? '',
    );
    if (value == null || !mounted) return;
    try {
      await ref.read(appStateProvider).setUciSection('system', section, {
        ...config,
        option: value,
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  Future<void> _setNtp(
    String section,
    Map<String, dynamic> config,
    bool enabled,
  ) async {
    try {
      await ref.read(appStateProvider).setUciSection('system', section, {
        ...config,
        'enabled': enabled ? '1' : '0',
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  Future<void> _editTimezone(
    String section,
    Map<String, dynamic> config,
    Map<dynamic, dynamic> timezones,
  ) async {
    final value = await promptNativeRouterText(
      context,
      title: '时区，例如 Asia/Shanghai',
      initialValue: config['zonename']?.toString() ?? 'UTC',
    );
    if (value == null || !mounted) return;
    final selected = timezones[value];
    if (selected is! Map || selected['tzstring'] == null) {
      await showNativeRouterError(context, '没有找到这个时区。');
      return;
    }
    try {
      await ref.read(appStateProvider).setUciSection('system', section, {
        ...config,
        'zonename': value,
        'timezone': selected['tzstring'],
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '系统设置',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final config = data['config'] is Map
              ? (data['config'] as Map).map(
                  (key, value) => MapEntry(
                    key.toString(),
                    value is Map
                        ? value.map((k, v) => MapEntry(k.toString(), v))
                        : <String, dynamic>{},
                  ),
                )
              : <String, Map<String, dynamic>>{};
          final systemEntry = config.entries.firstWhere(
            (entry) => entry.value['.type'] == 'system',
            orElse: () => const MapEntry('', <String, dynamic>{}),
          );
          final ntpEntry = config.entries.firstWhere(
            (entry) => entry.value['.type'] == 'timeserver',
            orElse: () => const MapEntry('', <String, dynamic>{}),
          );
          final info = data['info'] is Map ? data['info'] as Map : const {};
          final timezones = data['timezones'] is Map
              ? data['timezones'] as Map
              : const {};
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('常规'),
                children: [
                  CupertinoListTile(
                    title: const Text('主机名'),
                    additionalInfo: Text(
                      systemEntry.value['hostname']?.toString() ?? '-',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: systemEntry.key.isEmpty
                        ? null
                        : () => _edit(
                            systemEntry.key,
                            systemEntry.value,
                            'hostname',
                            '主机名',
                          ),
                  ),
                  CupertinoListTile(
                    title: const Text('时区'),
                    additionalInfo: Text(
                      systemEntry.value['zonename']?.toString() ?? 'UTC',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: systemEntry.key.isEmpty
                        ? null
                        : () => _editTimezone(
                            systemEntry.key,
                            systemEntry.value,
                            timezones,
                          ),
                  ),
                  NativeValueTile(
                    label: '运行时间',
                    value: formatDuration(info['uptime']),
                  ),
                ],
              ),
              if (ntpEntry.key.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('时间同步'),
                  children: [
                    CupertinoListTile(
                      title: const Text('启用 NTP'),
                      trailing: CupertinoSwitch(
                        value: ntpEntry.value['enabled']?.toString() != '0',
                        onChanged: (value) =>
                            _setNtp(ntpEntry.key, ntpEntry.value, value),
                      ),
                    ),
                    NativeValueTile(
                      label: '服务器',
                      value: _listLabel(ntpEntry.value['server']),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class RouterAdministrationScreen extends StatelessWidget {
  const RouterAdministrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pages = <({String title, IconData icon, Widget page})>[
      (
        title: '路由器密码',
        icon: CupertinoIcons.lock_fill,
        page: const _RouterPasswordScreen(),
      ),
      (
        title: 'SSH 访问',
        icon: CupertinoIcons.chevron_left_slash_chevron_right,
        page: const _RouterSshSettingsScreen(),
      ),
      (
        title: 'SSH 密钥',
        icon: CupertinoIcons.lock_fill,
        page: const _RouterSshKeysScreen(),
      ),
    ];
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: const CupertinoNavigationBar(middle: Text('管理权')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          children: [
            CupertinoListSection.insetGrouped(
              children: pages
                  .map(
                    (item) => CupertinoListTile(
                      leading: Icon(
                        item.icon,
                        color: CupertinoColors.activeBlue,
                      ),
                      title: Text(item.title),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(builder: (_) => item.page),
                      ),
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

class _RouterPasswordScreen extends ConsumerStatefulWidget {
  const _RouterPasswordScreen();

  @override
  ConsumerState<_RouterPasswordScreen> createState() =>
      _RouterPasswordScreenState();
}

class _RouterPasswordScreenState extends ConsumerState<_RouterPasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text != _confirmation.text) {
      await showNativeRouterError(context, '两次输入的密码不一致。');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(appStateProvider)
          .setRouterPassword(_password.text, context: context);
      if (!mounted) return;
      _password.clear();
      _confirmation.clear();
      await showNativeRouterMessage(context, '密码已更新');
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('路由器密码')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            CupertinoTextField(
              controller: _password,
              obscureText: true,
              placeholder: '新密码',
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _confirmation,
              obscureText: true,
              placeholder: '再次输入',
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 18),
            CupertinoButton.filled(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Text('更新密码'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouterSshSettingsScreen extends ConsumerStatefulWidget {
  const _RouterSshSettingsScreen();

  @override
  ConsumerState<_RouterSshSettingsScreen> createState() =>
      _RouterSshSettingsScreenState();
}

class _RouterSshSettingsScreenState
    extends ConsumerState<_RouterSshSettingsScreen> {
  late Future<Map<String, Map<String, dynamic>>> _future = _load();

  Future<Map<String, Map<String, dynamic>>> _load() =>
      ref.read(appStateProvider).fetchUciSections('dropbear', context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _set(
    String section,
    Map<String, dynamic> config,
    String key,
    dynamic value,
  ) async {
    try {
      await ref.read(appStateProvider).setUciSection('dropbear', section, {
        ...config,
        key: value,
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: 'SSH 访问',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final entries = (snapshot.data ?? const {}).entries
              .where((entry) => entry.value['.type'] == 'dropbear')
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: entries.map((entry) {
              final config = entry.value;
              return CupertinoListSection.insetGrouped(
                header: Text(entry.key),
                children: [
                  CupertinoListTile(
                    title: const Text('允许密码登录'),
                    trailing: CupertinoSwitch(
                      value: config['PasswordAuth']?.toString() != 'off',
                      onChanged: (value) => _set(
                        entry.key,
                        config,
                        'PasswordAuth',
                        value ? 'on' : 'off',
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('允许 root 密码登录'),
                    trailing: CupertinoSwitch(
                      value: config['RootPasswordAuth']?.toString() != 'off',
                      onChanged: (value) => _set(
                        entry.key,
                        config,
                        'RootPasswordAuth',
                        value ? 'on' : 'off',
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('监听端口'),
                    additionalInfo: Text(config['Port']?.toString() ?? '22'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final value = await promptNativeRouterText(
                        context,
                        title: 'SSH 端口',
                        initialValue: config['Port']?.toString() ?? '22',
                        keyboardType: TextInputType.number,
                      );
                      if (value != null && mounted) {
                        await _set(entry.key, config, 'Port', value);
                      }
                    },
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _RouterSshKeysScreen extends ConsumerStatefulWidget {
  const _RouterSshKeysScreen();

  @override
  ConsumerState<_RouterSshKeysScreen> createState() =>
      _RouterSshKeysScreenState();
}

class _RouterSshKeysScreenState extends ConsumerState<_RouterSshKeysScreen> {
  late Future<String> _future = _load();

  Future<String> _load() => ref
      .read(appStateProvider)
      .readRouterFile('/etc/dropbear/authorized_keys', context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(String current) async {
    final value = await Navigator.of(context).push<String>(
      CupertinoPageRoute(
        builder: (_) =>
            RouterTextFileEditorScreen(title: 'SSH 密钥', initialValue: current),
      ),
    );
    if (value == null || !mounted) return;
    try {
      await ref
          .read(appStateProvider)
          .writeRouterFile(
            '/etc/dropbear/authorized_keys',
            value,
            context: context,
          );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: 'SSH 密钥',
      onRefresh: _reload,
      child: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final value = snapshot.data ?? '';
          final keys = value
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: Text('已授权密钥 ${keys.length}'),
                children: keys
                    .map(
                      (key) => CupertinoListTile(
                        title: Text(
                          key.split(RegExp(r'\s+')).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton.filled(
                  onPressed: () => _edit(value),
                  child: const Text('编辑密钥'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterScheduledTasksScreen extends ConsumerStatefulWidget {
  const RouterScheduledTasksScreen({super.key});

  @override
  ConsumerState<RouterScheduledTasksScreen> createState() =>
      _RouterScheduledTasksScreenState();
}

class _RouterScheduledTasksScreenState
    extends ConsumerState<RouterScheduledTasksScreen> {
  late Future<String> _future = _load();

  Future<String> _load() => ref
      .read(appStateProvider)
      .readRouterFile('/etc/crontabs/root', context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(String current) async {
    final value = await Navigator.of(context).push<String>(
      CupertinoPageRoute(
        builder: (_) =>
            RouterTextFileEditorScreen(title: '计划任务', initialValue: current),
      ),
    );
    if (value == null || !mounted) return;
    try {
      final state = ref.read(appStateProvider);
      await state.writeRouterFile(
        '/etc/crontabs/root',
        value.endsWith('\n') ? value : '$value\n',
        context: context,
      );
      if (!mounted) return;
      await state.controlStartupService('cron', 'reload', context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '计划任务',
      onRefresh: _reload,
      child: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final value = snapshot.data ?? '';
          final tasks = value
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty && !line.startsWith('#'))
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: Text('任务 ${tasks.length}'),
                children: tasks
                    .map(
                      (task) => CupertinoListTile(
                        title: Text(
                          task,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Menlo'),
                        ),
                      ),
                    )
                    .toList(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton.filled(
                  onPressed: () => _edit(value),
                  child: const Text('编辑任务'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterMountPointsScreen extends ConsumerStatefulWidget {
  const RouterMountPointsScreen({super.key});

  @override
  ConsumerState<RouterMountPointsScreen> createState() =>
      _RouterMountPointsScreenState();
}

class _RouterMountPointsScreenState
    extends ConsumerState<RouterMountPointsScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchMountPoints(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '挂载点',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final mounts = data['mounts'] is List
              ? (data['mounts'] as List).whereType<Map>().toList()
              : const <Map>[];
          final devices = data['devices'] is Map
              ? data['devices'] as Map
              : const {};
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: Text('已挂载 ${mounts.length}'),
                children: mounts.map((mount) {
                  final total = _number(mount['size']);
                  final available = _number(mount['avail'] ?? mount['free']);
                  final used = total > 0 ? total - available : 0;
                  return CupertinoListTile(
                    title: Text(mount['mount']?.toString() ?? '-'),
                    subtitle: Text(mount['device']?.toString() ?? '-'),
                    additionalInfo: Text(
                      '${formatBytes(used)} / ${formatBytes(total)}',
                    ),
                  );
                }).toList(),
              ),
              if (devices.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: Text('块设备 ${devices.length}'),
                  children: devices.entries.map((entry) {
                    final device = entry.value is Map
                        ? entry.value as Map
                        : const {};
                    return CupertinoListTile(
                      title: Text(entry.key.toString()),
                      subtitle: Text(device['model']?.toString() ?? '-'),
                      additionalInfo: Text(
                        formatBytes(_number(device['size'])),
                      ),
                    );
                  }).toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RouterLedSettingsScreen extends ConsumerStatefulWidget {
  const RouterLedSettingsScreen({super.key});

  @override
  ConsumerState<RouterLedSettingsScreen> createState() =>
      _RouterLedSettingsScreenState();
}

class _RouterLedSettingsScreenState
    extends ConsumerState<RouterLedSettingsScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchLedSettings(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: 'LED 配置',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final leds = data['leds'] is Map ? data['leds'] as Map : const {};
          final configs = data['config'] is Map
              ? (data['config'] as Map).entries.where((entry) {
                  return entry.value is Map &&
                      (entry.value as Map)['.type'] == 'led';
                }).toList()
              : const [];
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: Text('可用 LED ${leds.length}'),
                children: leds.keys
                    .map(
                      (name) => CupertinoListTile(title: Text(name.toString())),
                    )
                    .toList(),
              ),
              if (configs.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: const Text('触发规则'),
                  children: configs.map((entry) {
                    final config = entry.value as Map;
                    return CupertinoListTile(
                      title: Text(
                        config['name']?.toString() ?? entry.key.toString(),
                      ),
                      subtitle: Text(config['sysfs']?.toString() ?? '-'),
                      additionalInfo: Text(
                        config['trigger']?.toString() ?? '-',
                      ),
                    );
                  }).toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RouterDdnsScreen extends ConsumerStatefulWidget {
  const RouterDdnsScreen({super.key});

  @override
  ConsumerState<RouterDdnsScreen> createState() => _RouterDdnsScreenState();
}

class _RouterDdnsScreenState extends ConsumerState<RouterDdnsScreen> {
  final Set<String> _saving = {};
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchDdnsOverview(context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _setEnabled(
    String section,
    Map<String, dynamic> config,
    bool enabled,
  ) async {
    setState(() => _saving.add(section));
    try {
      await ref.read(appStateProvider).setUciSection('ddns', section, {
        ...config,
        'enabled': enabled ? '1' : '0',
      }, context: context);
      if (!mounted) return;
      await ref
          .read(appStateProvider)
          .controlStartupService('ddns', 'reload', context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _saving.remove(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '动态 DNS',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final statuses = data['status'] is Map
              ? data['status'] as Map
              : const {};
          final configs = data['config'] is Map
              ? (data['config'] as Map).map(
                  (key, value) => MapEntry(
                    key.toString(),
                    value is Map
                        ? value.map((k, v) => MapEntry(k.toString(), v))
                        : <String, dynamic>{},
                  ),
                )
              : <String, Map<String, dynamic>>{};
          final services = configs.entries
              .where((entry) => entry.value['.type'] == 'service')
              .toList();
          if (services.isEmpty) {
            return const NativeRouterEmpty(label: '没有 DDNS 服务');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                children: services.map((entry) {
                  final config = entry.value;
                  final status = statuses[entry.key] is Map
                      ? statuses[entry.key] as Map
                      : const {};
                  final busy = _saving.contains(entry.key);
                  final running = status['pid'] != null;
                  final state = config['enabled']?.toString() == '0'
                      ? '已停用'
                      : running
                      ? '运行中'
                      : '等待更新';
                  final detail = status['ip']?.toString();
                  return CupertinoListTile(
                    title: Text(config['lookup_host']?.toString() ?? entry.key),
                    subtitle: Text(
                      '${config['service_name'] ?? 'DDNS'} · $state${detail == null ? '' : ' · $detail'}',
                    ),
                    trailing: busy
                        ? const CupertinoActivityIndicator()
                        : CupertinoSwitch(
                            value: config['enabled']?.toString() != '0',
                            onChanged: (value) =>
                                _setEnabled(entry.key, config, value),
                          ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterTextFileEditorScreen extends StatefulWidget {
  final String title;
  final String initialValue;

  const RouterTextFileEditorScreen({
    super.key,
    required this.title,
    required this.initialValue,
  });

  @override
  State<RouterTextFileEditorScreen> createState() =>
      _RouterTextFileEditorScreenState();
}

class _RouterTextFileEditorScreenState
    extends State<RouterTextFileEditorScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CupertinoTextField(
            controller: _controller,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
            padding: const EdgeInsets.all(13),
          ),
        ),
      ),
    );
  }
}

class NativeRouterScaffold extends StatelessWidget {
  final String title;
  final VoidCallback onRefresh;
  final Widget child;
  final Widget? trailing;

  const NativeRouterScaffold({
    super.key,
    required this.title,
    required this.onRefresh,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing:
            trailing ??
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onRefresh,
              child: const Icon(CupertinoIcons.refresh, size: 21),
            ),
      ),
      child: SafeArea(child: child),
    );
  }
}

class NativeValueTile extends StatelessWidget {
  final String label;
  final String value;

  const NativeValueTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(label),
      additionalInfo: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
        ),
      ),
    );
  }
}

class NativeRouterLoading extends StatelessWidget {
  const NativeRouterLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CupertinoActivityIndicator());
  }
}

class NativeRouterEmpty extends StatelessWidget {
  final String label;

  const NativeRouterEmpty({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class NativeRouterError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const NativeRouterError({
    super.key,
    required this.error,
    required this.onRetry,
  });

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
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            CupertinoButton.filled(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

Future<void> showNativeRouterError(BuildContext context, Object error) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('操作失败'),
      content: Text(error.toString()),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('好'),
        ),
      ],
    ),
  );
}

Future<void> showNativeRouterMessage(BuildContext context, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('好'),
        ),
      ],
    ),
  );
}

Future<bool> confirmNativeRouterAction(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  return await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<String?> promptNativeRouterText(
  BuildContext context, {
  required String title,
  required String initialValue,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initialValue);
  final value = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: controller,
          keyboardType: keyboardType,
          autocorrect: false,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

bool _boolValue(dynamic value) {
  final normalized = value?.toString().toLowerCase();
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'on';
}

num _number(dynamic value) => num.tryParse(value?.toString() ?? '') ?? 0;

String formatBytes(num bytes) {
  final value = bytes.toDouble();
  if (value >= 1024 * 1024 * 1024) {
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  if (value >= 1024 * 1024) {
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${value.toStringAsFixed(0)} B';
}

String formatDuration(dynamic seconds) {
  final value = int.tryParse(seconds?.toString() ?? '') ?? 0;
  final days = value ~/ 86400;
  final hours = (value % 86400) ~/ 3600;
  final minutes = (value % 3600) ~/ 60;
  return days > 0 ? '$days 天 $hours 小时' : '$hours 小时 $minutes 分钟';
}

String _listLabel(dynamic value) {
  if (value is List) return value.join(', ');
  return value?.toString() ?? '-';
}
