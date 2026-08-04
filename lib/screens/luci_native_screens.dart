import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/luci_standard_native_screens.dart';
import 'package:luci_mobile/widgets/native_navigation_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class RouterRoutesScreen extends ConsumerStatefulWidget {
  const RouterRoutesScreen({super.key});

  @override
  ConsumerState<RouterRoutesScreen> createState() => _RouterRoutesScreenState();
}

class _RouterRoutesScreenState extends ConsumerState<RouterRoutesScreen> {
  String _family = 'IPv4';
  late Future<Map<String, List<String>>> _future = _load();

  Future<Map<String, List<String>>> _load() {
    return ref.read(appStateProvider).fetchRoutingTables(context: context);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return _NativeScaffold(
      title: '路由表',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, List<String>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _NativeLoading();
          }
          if (snapshot.hasError) {
            return _NativeError(error: snapshot.error, onRetry: _reload);
          }
          final routes = snapshot.data?[_family] ?? const [];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: _family,
                    children: const {
                      'IPv4': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Text('IPv4'),
                      ),
                      'IPv6': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Text('IPv6'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) setState(() => _family = value);
                    },
                  ),
                ),
              ),
              Expanded(
                child: routes.isEmpty
                    ? const _NativeEmpty(label: '没有路由记录')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: routes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) => SelectableText(
                          routes[index],
                          style: TextStyle(
                            color: CupertinoColors.label.resolveFrom(context),
                            fontFamily: 'Menlo',
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterRealtimeScreen extends ConsumerStatefulWidget {
  const RouterRealtimeScreen({super.key});

  @override
  ConsumerState<RouterRealtimeScreen> createState() =>
      _RouterRealtimeScreenState();
}

class _RouterRealtimeScreenState extends ConsumerState<RouterRealtimeScreen> {
  Timer? _timer;
  late Future<Map<String, dynamic>> _future = _load();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return ref.read(appStateProvider).fetchRealtimeOverview(context: context);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return _NativeScaffold(
      title: '实时状态',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _NativeLoading();
          }
          if (snapshot.hasError) {
            return _NativeError(error: snapshot.error, onRetry: _reload);
          }
          final data = snapshot.data ?? const {};
          final load = data['load'] is List ? data['load'] as List : const [];
          final connections = data['connections'] is List
              ? data['connections'] as List
              : const [];
          String loadValue(int index) {
            if (load.length <= index || load[index] is! num) return '-';
            return ((load[index] as num) / 100).toStringAsFixed(2);
          }

          String countValue(int index) =>
              connections.length > index ? connections[index].toString() : '-';
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('系统负载'),
                children: [
                  _ValueTile(label: '1 分钟', value: loadValue(1)),
                  _ValueTile(label: '5 分钟', value: loadValue(2)),
                  _ValueTile(label: '15 分钟', value: loadValue(3)),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('连接与流量'),
                children: [
                  _ValueTile(label: '连接数', value: countValue(1)),
                  _ValueTile(label: '下载', value: _formatRate(data['rxRate'])),
                  _ValueTile(label: '上传', value: _formatRate(data['txRate'])),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _DiagnosticOperation { ping, traceroute, nslookup }

class RouterDiagnosticsScreen extends ConsumerStatefulWidget {
  const RouterDiagnosticsScreen({super.key});

  @override
  ConsumerState<RouterDiagnosticsScreen> createState() =>
      _RouterDiagnosticsScreenState();
}

class _RouterDiagnosticsScreenState
    extends ConsumerState<RouterDiagnosticsScreen> {
  final TextEditingController _targetController = TextEditingController(
    text: 'openwrt.org',
  );
  _DiagnosticOperation _operation = _DiagnosticOperation.ping;
  bool _running = false;
  String _output = '';

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _output = '';
    });
    try {
      final output = await ref
          .read(appStateProvider)
          .runNetworkDiagnostic(
            _operation.name,
            _targetController.text,
            context: context,
          );
      if (mounted) setState(() => _output = output);
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: NativeNavigationBar(
        context: context,
        middle: const Text('网络诊断'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            CupertinoTextField(
              controller: _targetController,
              autocorrect: false,
              keyboardType: TextInputType.url,
              placeholder: '主机名或 IP 地址',
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoSlidingSegmentedControl<_DiagnosticOperation>(
              groupValue: _operation,
              children: const {
                _DiagnosticOperation.ping: Text('Ping'),
                _DiagnosticOperation.traceroute: Text('路由追踪'),
                _DiagnosticOperation.nslookup: Text('DNS 查询'),
              },
              onValueChanged: (value) {
                if (_running || value == null) return;
                setState(() => _operation = value);
              },
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: _running ? null : _run,
              child: _running
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Text('开始诊断'),
            ),
            if (_output.isNotEmpty) ...[
              const SizedBox(height: 20),
              SelectableText(
                _output,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(context),
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppFilterNativeScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenAdvanced;

  const AppFilterNativeScreen({super.key, required this.onOpenAdvanced});

  @override
  ConsumerState<AppFilterNativeScreen> createState() =>
      _AppFilterNativeScreenState();
}

class _AppFilterNativeScreenState extends ConsumerState<AppFilterNativeScreen> {
  bool _saving = false;
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() {
    return ref.read(appStateProvider).fetchAppFilterOverview(context: context);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(appStateProvider)
          .setAppFilterEnabled(enabled, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await _showOperationError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setAdvanced(
    Map<String, dynamic> advanced,
    String key,
    bool enabled,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(appStateProvider).setAppFilterAdvanced({
        ...advanced,
        key: enabled ? 1 : 0,
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await _showOperationError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _NativeScaffold(
      title: '应用过滤',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _NativeLoading();
          }
          if (snapshot.hasError) {
            return _NativeError(
              error: snapshot.error,
              onRetry: _reload,
              onOpenAdvanced: widget.onOpenAdvanced,
            );
          }
          final data = snapshot.data ?? const {};
          final status = data['status'] is Map
              ? data['status'] as Map
              : const {};
          final base = data['base'] is Map ? data['base'] as Map : const {};
          final devices = data['devices'] is List
              ? (data['devices'] as List).whereType<Map>().toList()
              : const <Map>[];
          final classes = data['classes'] is List
              ? (data['classes'] as List).whereType<Map>().toList()
              : const <Map>[];
          final schedule = data['schedule'] is Map
              ? (data['schedule'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : <String, dynamic>{};
          final advanced = data['advanced'] is Map
              ? (data['advanced'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : <String, dynamic>{};
          final usersData = data['users'] is Map
              ? data['users'] as Map
              : const {};
          final users = usersData['list'] is List
              ? usersData['list'] as List
              : const [];
          final enabled =
              (base['enable'] ?? status['config_enable']).toString() == '1';
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                children: [
                  CupertinoListTile(
                    title: const Text('启用应用过滤'),
                    subtitle: Text('版本 ${status['version'] ?? '-'}'),
                    trailing: _saving
                        ? const CupertinoActivityIndicator()
                        : CupertinoSwitch(
                            value: enabled,
                            onChanged: _setEnabled,
                          ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: Text('在线设备 ${devices.length}'),
                children: devices.map((device) {
                  final hostname = (device['nickname'] ?? '').toString().trim();
                  final fallback = (device['hostname'] ?? '').toString().trim();
                  return CupertinoListTile(
                    title: Text(
                      hostname.isNotEmpty
                          ? hostname
                          : fallback.isNotEmpty
                          ? fallback
                          : device['ip']?.toString() ?? '未知设备',
                    ),
                    subtitle: Text(
                      '${device['ip'] ?? '-'}  ·  ${device['mac'] ?? '-'}',
                    ),
                  );
                }).toList(),
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('过滤计划'),
                children: [
                  _ValueTile(
                    label: '时段',
                    value:
                        '${schedule['start_time'] ?? '00:00'} - ${schedule['end_time'] ?? '23:59'}',
                  ),
                  _ValueTile(
                    label: '生效星期',
                    value: schedule['weekday_list'] is List
                        ? (schedule['weekday_list'] as List).join(', ')
                        : '-',
                  ),
                  _ValueTile(label: '已识别用户', value: '${users.length}'),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('高级设置'),
                children: [
                  _ValueTile(
                    label: 'LAN 接口',
                    value: advanced['lan_ifname']?.toString() ?? 'br-lan',
                  ),
                  CupertinoListTile(
                    title: const Text('停用硬件加速'),
                    trailing: CupertinoSwitch(
                      value: advanced['disable_hnat'].toString() == '1',
                      onChanged: _saving
                          ? null
                          : (value) =>
                                _setAdvanced(advanced, 'disable_hnat', value),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('阻断时重置 TCP 连接'),
                    trailing: CupertinoSwitch(
                      value: advanced['tcp_rst'].toString() == '1',
                      onChanged: _saving
                          ? null
                          : (value) => _setAdvanced(advanced, 'tcp_rst', value),
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('自动加载识别引擎'),
                    trailing: CupertinoSwitch(
                      value: advanced['auto_load_engine'].toString() == '1',
                      onChanged: _saving
                          ? null
                          : (value) => _setAdvanced(
                              advanced,
                              'auto_load_engine',
                              value,
                            ),
                    ),
                  ),
                ],
              ),
              if (classes.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  header: Text('应用类别 ${classes.length}'),
                  children: classes.map((entry) {
                    final apps = entry['app_list'] is List
                        ? entry['app_list'] as List
                        : const [];
                    return CupertinoListTile(
                      title: Text(entry['name']?.toString() ?? '-'),
                      additionalInfo: Text('${apps.length} 个应用'),
                    );
                  }).toList(),
                ),
              _AdvancedButton(onPressed: widget.onOpenAdvanced),
            ],
          );
        },
      ),
    );
  }
}

class HddIdleNativeScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenAdvanced;

  const HddIdleNativeScreen({super.key, required this.onOpenAdvanced});

  @override
  ConsumerState<HddIdleNativeScreen> createState() =>
      _HddIdleNativeScreenState();
}

class _HddIdleNativeScreenState extends ConsumerState<HddIdleNativeScreen> {
  final Set<String> _saving = {};
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() {
    return ref.read(appStateProvider).fetchHddIdleSettings(context: context);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _setEnabled(String section, bool enabled) async {
    setState(() => _saving.add(section));
    try {
      await ref
          .read(appStateProvider)
          .setHddIdleEnabled(section, enabled, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await _showOperationError(context, error);
    } finally {
      if (mounted) setState(() => _saving.remove(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _NativeScaffold(
      title: '硬盘休眠',
      onRefresh: _reload,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _NativeLoading();
          }
          if (snapshot.hasError) {
            return _NativeError(
              error: snapshot.error,
              onRetry: _reload,
              onOpenAdvanced: widget.onOpenAdvanced,
            );
          }
          final settings = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                children: settings.map((setting) {
                  final section = setting['.name']?.toString() ?? '';
                  final busy = _saving.contains(section);
                  return CupertinoListTile(
                    title: Text('/dev/${setting['disk'] ?? '-'}'),
                    subtitle: Text(
                      '${setting['idle_time_interval'] ?? '-'} ${_unitLabel(setting['idle_time_unit'])}',
                    ),
                    trailing: busy
                        ? const CupertinoActivityIndicator()
                        : CupertinoSwitch(
                            value: setting['enabled'].toString() == '1',
                            onChanged: section.isEmpty
                                ? null
                                : (value) => _setEnabled(section, value),
                          ),
                  );
                }).toList(),
              ),
              _AdvancedButton(onPressed: widget.onOpenAdvanced),
            ],
          );
        },
      ),
    );
  }
}

class HomeAssistantNativeScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenAdvanced;

  const HomeAssistantNativeScreen({super.key, required this.onOpenAdvanced});

  @override
  ConsumerState<HomeAssistantNativeScreen> createState() =>
      _HomeAssistantNativeScreenState();
}

class _HomeAssistantNativeScreenState
    extends ConsumerState<HomeAssistantNativeScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() {
    return ref
        .read(appStateProvider)
        .fetchHomeAssistantOverview(context: context);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openHomeAssistant(int port) async {
    final router = ref.read(appStateProvider).selectedRouter;
    if (router == null) return;
    final base = Uri.parse(
      '${router.useHttps ? 'https' : 'http'}://${router.ipAddress}',
    );
    await launchUrl(
      base.replace(scheme: 'http', port: port, path: '/', query: null),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _NativeScaffold(
      title: 'Home Assistant',
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const _NativeLoading();
          }
          if (snapshot.hasError) {
            return _NativeError(
              error: snapshot.error,
              onRetry: _reload,
              onOpenAdvanced: widget.onOpenAdvanced,
            );
          }
          final data = snapshot.data ?? const {};
          final config = data['config'] is Map
              ? data['config'] as Map
              : const {};
          final running = data['status'] == 'running';
          final port = data['port'] is int ? data['port'] as int : 8123;
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                children: [
                  _ValueTile(
                    label: '状态',
                    value: data['status'].toString().isEmpty
                        ? '请在高级设置中查看'
                        : running
                        ? '运行中'
                        : '已停止',
                  ),
                  _ValueTile(
                    label: '镜像',
                    value: config['image_name']?.toString() ?? '-',
                  ),
                  _ValueTile(
                    label: '配置目录',
                    value: config['config_path']?.toString() ?? '-',
                  ),
                ],
              ),
              if (running)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CupertinoButton.filled(
                    onPressed: () => _openHomeAssistant(port),
                    child: const Text('打开 Home Assistant'),
                  ),
                ),
              _AdvancedButton(onPressed: widget.onOpenAdvanced),
            ],
          );
        },
      ),
    );
  }
}

class RouterRebootScreen extends ConsumerStatefulWidget {
  const RouterRebootScreen({super.key});

  @override
  ConsumerState<RouterRebootScreen> createState() => _RouterRebootScreenState();
}

class _RouterRebootScreenState extends ConsumerState<RouterRebootScreen> {
  bool _rebooting = false;

  Future<void> _reboot() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('重启路由器？'),
        content: const Text('连接会暂时中断。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重启'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rebooting = true);
    final success = await ref.read(appStateProvider).reboot(context: context);
    if (mounted) setState(() => _rebooting = false);
    if (!success && mounted) {
      await _showOperationError(context, '路由器没有接受重启命令。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: NativeNavigationBar(
        context: context,
        middle: const Text('重启'),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: CupertinoButton.filled(
              onPressed: _rebooting ? null : _reboot,
              child: _rebooting
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Text('重启路由器'),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeScaffold extends StatelessWidget {
  final String title;
  final VoidCallback onRefresh;
  final Widget child;

  const _NativeScaffold({
    required this.title,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: title,
      onRefresh: onRefresh,
      child: child,
    );
  }
}

class _ValueTile extends StatelessWidget {
  final String label;
  final String value;

  const _ValueTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(label),
      additionalInfo: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 210),
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

class _AdvancedButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AdvancedButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CupertinoButton(onPressed: onPressed, child: const Text('高级设置')),
    );
  }
}

class _NativeLoading extends StatelessWidget {
  const _NativeLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CupertinoActivityIndicator());
  }
}

class _NativeEmpty extends StatelessWidget {
  final String label;

  const _NativeEmpty({required this.label});

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

class _NativeError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onOpenAdvanced;

  const _NativeError({
    required this.error,
    required this.onRetry,
    this.onOpenAdvanced,
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
            if (onOpenAdvanced != null)
              CupertinoButton(
                onPressed: onOpenAdvanced,
                child: const Text('打开高级设置'),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatRate(dynamic bytesPerSecond) {
  final value = bytesPerSecond is num ? bytesPerSecond.toDouble() : 0.0;
  if (value >= 1024 * 1024) {
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB/s';
  return '${value.toStringAsFixed(0)} B/s';
}

String _unitLabel(dynamic unit) {
  return switch (unit?.toString()) {
    'seconds' => '秒',
    'hours' => '小时',
    'days' => '天',
    _ => '分钟',
  };
}

Future<void> _showOperationError(BuildContext context, Object error) {
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
