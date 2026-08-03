import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';

class RouterToolsScreen extends StatelessWidget {
  const RouterToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <({IconData icon, String title, Color color, Widget page})>[
      (
        icon: CupertinoIcons.doc_text_fill,
        title: '系统日志',
        color: CupertinoColors.systemOrange,
        page: const RouterLogsScreen(),
      ),
      (
        icon: CupertinoIcons.chart_bar_fill,
        title: '进程',
        color: CupertinoColors.systemIndigo,
        page: const RouterProcessesScreen(),
      ),
      (
        icon: CupertinoIcons.gear_alt_fill,
        title: '启动服务',
        color: CupertinoColors.systemGreen,
        page: const RouterStartupServicesScreen(),
      ),
    ];
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('管理工具'),
        previousPageTitle: '更多',
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          children: [
            CupertinoListSection.insetGrouped(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: tools
                  .map(
                    (tool) => CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      leadingSize: 32,
                      leadingToTitle: 12,
                      leading: _NativeIcon(icon: tool.icon, color: tool.color),
                      title: Text(tool.title),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(builder: (_) => tool.page),
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

enum _LogType { system, kernel }

class RouterLogsScreen extends ConsumerStatefulWidget {
  const RouterLogsScreen({super.key});

  @override
  ConsumerState<RouterLogsScreen> createState() => _RouterLogsScreenState();
}

class _RouterLogsScreenState extends ConsumerState<RouterLogsScreen> {
  _LogType _type = _LogType.system;
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<String>> _load() {
    final state = ref.read(appStateProvider);
    return _type == _LogType.system
        ? state.fetchSystemLogs(context: context)
        : state.fetchKernelLogs(context: context);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('日志'),
        previousPageTitle: '管理工具',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _reload,
          child: const Icon(CupertinoIcons.refresh, size: 21),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<_LogType>(
                  groupValue: _type,
                  children: const {
                    _LogType.system: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('系统日志'),
                    ),
                    _LogType.kernel: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('内核日志'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value == null || value == _type) return;
                    setState(() {
                      _type = value;
                      _future = _load();
                    });
                  },
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const _NativeLoading();
                  }
                  if (snapshot.hasError) {
                    return _NativeError(
                      message: snapshot.error.toString(),
                      onRetry: _reload,
                    );
                  }
                  final lines = snapshot.data ?? const [];
                  if (lines.isEmpty) return const _NativeEmpty(label: '暂无日志');
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) => SelectableText(
                      lines[index],
                      style: TextStyle(
                        color: CupertinoColors.label.resolveFrom(context),
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RouterProcessesScreen extends ConsumerStatefulWidget {
  const RouterProcessesScreen({super.key});

  @override
  ConsumerState<RouterProcessesScreen> createState() =>
      _RouterProcessesScreenState();
}

class _RouterProcessesScreenState extends ConsumerState<RouterProcessesScreen> {
  Timer? _timer;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return ref.read(appStateProvider).fetchProcesses(context: context);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('进程'),
        previousPageTitle: '管理工具',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _reload,
          child: const Icon(CupertinoIcons.refresh, size: 21),
        ),
      ),
      child: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const _NativeLoading();
            }
            if (snapshot.hasError) {
              return _NativeError(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }
            final processes = snapshot.data ?? const [];
            if (processes.isEmpty) {
              return const _NativeEmpty(label: '暂无进程数据');
            }
            return ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                CupertinoListSection.insetGrouped(
                  header: Text('${processes.length} 个进程'),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  children: processes.map((process) {
                    final command = _processValue(process, const [
                      'COMMAND',
                      'command',
                    ]);
                    final name = command.split(' ').first.split('/').last;
                    final pid = _processValue(process, const ['PID', 'pid']);
                    final cpu = _processValue(process, const ['%CPU', 'cpu']);
                    final memory = _processValue(process, const [
                      '%MEM',
                      'mem',
                    ]);
                    return CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('PID $pid  ·  CPU $cpu  ·  内存 $memory'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => _ProcessDetailsScreen(
                            name: name,
                            command: command,
                            pid: pid,
                            cpu: cpu,
                            memory: memory,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProcessDetailsScreen extends StatelessWidget {
  final String name;
  final String command;
  final String pid;
  final String cpu;
  final String memory;

  const _ProcessDetailsScreen({
    required this.name,
    required this.command,
    required this.pid,
    required this.cpu,
    required this.memory,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(
        middle: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        previousPageTitle: '进程',
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          children: [
            CupertinoListSection.insetGrouped(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _ProcessDetailTile(label: 'PID', value: pid),
                _ProcessDetailTile(label: 'CPU', value: cpu),
                _ProcessDetailTile(label: '内存', value: memory),
                CupertinoListTile(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  title: const Text('命令'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: SelectableText(
                      command,
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                        fontFamily: 'Menlo',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessDetailTile extends StatelessWidget {
  final String label;
  final String value;

  const _ProcessDetailTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(label),
      additionalInfo: Text(value),
    );
  }
}

class RouterStartupServicesScreen extends ConsumerStatefulWidget {
  const RouterStartupServicesScreen({super.key});

  @override
  ConsumerState<RouterStartupServicesScreen> createState() =>
      _RouterStartupServicesScreenState();
}

class _RouterStartupServicesScreenState
    extends ConsumerState<RouterStartupServicesScreen> {
  late Future<Map<String, dynamic>> _future;
  final Set<String> _busyServices = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    return ref.read(appStateProvider).fetchStartupServices(context: context);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _runAction(String name, String action) async {
    setState(() => _busyServices.add(name));
    try {
      await ref
          .read(appStateProvider)
          .controlStartupService(name, action, context: context);
      if (!mounted) return;
      _reload();
    } catch (error) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
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
    } finally {
      if (mounted) setState(() => _busyServices.remove(name));
    }
  }

  Future<void> _showActions(
    String name, {
    required bool enabled,
    required bool running,
  }) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(name),
        message: Text(
          '${running ? '运行中' : '已停止'} · ${enabled ? '开机启动' : '未启用'}',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(popupContext).pop(enabled ? 'disable' : 'enable'),
            child: Text(enabled ? '禁用开机启动' : '启用开机启动'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('start'),
            child: const Text('启动'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('restart'),
            child: const Text('重新启动'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(popupContext).pop('stop'),
            child: const Text('停止'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (action != null && mounted) {
      await _runAction(name, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('启动服务'),
        previousPageTitle: '管理工具',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _reload,
          child: const Icon(CupertinoIcons.refresh, size: 21),
        ),
      ),
      child: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const _NativeLoading();
            }
            if (snapshot.hasError) {
              return _NativeError(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }
            final entries = (snapshot.data ?? const {}).entries.toList()
              ..sort((a, b) => _serviceOrder(a).compareTo(_serviceOrder(b)));
            if (entries.isEmpty) {
              return const _NativeEmpty(label: '暂无启动服务数据');
            }

            return ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                CupertinoListSection.insetGrouped(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  children: entries.map((entry) {
                    final data = entry.value is Map
                        ? entry.value as Map
                        : const {};
                    final enabled = data['enabled'] == true;
                    final running = data['running'] == true;
                    final busy = _busyServices.contains(entry.key);
                    return CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      leadingSize: 22,
                      leadingToTitle: 10,
                      leading: busy
                          ? const CupertinoActivityIndicator(radius: 9)
                          : Icon(
                              running
                                  ? CupertinoIcons.check_mark_circled_solid
                                  : CupertinoIcons.pause_circle,
                              size: 21,
                              color: running
                                  ? CupertinoColors.systemGreen
                                  : CupertinoColors.systemGrey,
                            ),
                      title: Text(entry.key),
                      subtitle: Text(
                        '${running ? '运行中' : '已停止'}  ·  ${enabled ? '开机启动' : '未启用'}',
                      ),
                      trailing: const CupertinoListTileChevron(),
                      onTap: busy
                          ? null
                          : () => _showActions(
                              entry.key,
                              enabled: enabled,
                              running: running,
                            ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _serviceOrder(MapEntry<String, dynamic> entry) {
    final value = entry.value;
    if (value is! Map) return 999;
    return int.tryParse((value['start'] ?? value['index'])?.toString() ?? '') ??
        999;
  }
}

String _processValue(Map<String, dynamic> process, List<String> keys) {
  for (final key in keys) {
    final value = process[key]?.toString();
    if (value != null && value.isNotEmpty) return value;
  }
  return '-';
}

class _NativeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _NativeIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: CupertinoColors.white, size: 19),
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
  final String message;
  final VoidCallback onRetry;

  const _NativeError({required this.message, required this.onRetry});

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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            CupertinoButton.filled(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
