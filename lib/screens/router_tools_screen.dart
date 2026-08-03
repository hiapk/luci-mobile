import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class RouterToolsScreen extends StatelessWidget {
  const RouterToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools =
        <({IconData icon, String title, String subtitle, Widget page})>[
          (
            icon: Icons.article_outlined,
            title: '系统日志',
            subtitle: '查看系统和内核日志',
            page: const RouterLogsScreen(),
          ),
          (
            icon: Icons.memory_outlined,
            title: '进程',
            subtitle: '按 CPU 使用率查看运行进程',
            page: const RouterProcessesScreen(),
          ),
          (
            icon: Icons.power_settings_new_rounded,
            title: '启动服务',
            subtitle: '管理服务状态和开机启动',
            page: const RouterStartupServicesScreen(),
          ),
        ];
    return Scaffold(
      appBar: const LuciAppBar(title: '管理工具', showBack: true),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tools.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final tool = tools[index];
          return ListTile(
            minTileHeight: 72,
            leading: Icon(tool.icon),
            title: Text(tool.title),
            subtitle: Text(tool.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => tool.page)),
          );
        },
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
    return Scaffold(
      appBar: LuciAppBar(
        title: '日志',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_LogType>(
              segments: const [
                ButtonSegment(value: _LogType.system, label: Text('系统日志')),
                ButtonSegment(value: _LogType.kernel, label: Text('内核日志')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() {
                  _type = selection.first;
                  _future = _load();
                });
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ToolError(
                    message: snapshot.error.toString(),
                    onRetry: _reload,
                  );
                }
                final lines = snapshot.data ?? const [];
                if (lines.isEmpty) return const Center(child: Text('暂无日志'));
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _future;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) => SelectableText(
                      lines[index],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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

  String _value(Map<String, dynamic> process, List<String> keys) {
    for (final key in keys) {
      final value = process[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: '进程',
        showBack: true,
        actions: [
          IconButton(
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ToolError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final processes = snapshot.data ?? const [];
          if (processes.isEmpty) return const Center(child: Text('暂无进程数据'));
          return ListView.separated(
            itemCount: processes.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final process = processes[index];
              final command = _value(process, const ['COMMAND', 'command']);
              final name = command.split(' ').first.split('/').last;
              final pid = _value(process, const ['PID', 'pid']);
              final cpu = _value(process, const ['%CPU', 'cpu']);
              final memory = _value(process, const ['%MEM', 'mem']);
              return ExpansionTile(
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('PID $pid  ·  CPU $cpu  ·  内存 $memory'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        command,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name 操作成功')));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyServices.remove(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: '启动服务',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ToolError(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final entries = (snapshot.data ?? const {}).entries.toList()
            ..sort((a, b) {
              int startOf(MapEntry<String, dynamic> entry) {
                final value = entry.value;
                if (value is Map) {
                  return int.tryParse(
                        (value['start'] ?? value['index'])?.toString() ?? '',
                      ) ??
                      999;
                }
                return 999;
              }

              return startOf(a).compareTo(startOf(b));
            });
          if (entries.isEmpty) return const Center(child: Text('暂无启动服务数据'));

          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final data = entry.value is Map ? entry.value as Map : const {};
                final enabled = data['enabled'] == true;
                final running = data['running'] == true;
                final busy = _busyServices.contains(entry.key);
                return ExpansionTile(
                  title: Text(entry.key),
                  subtitle: Text(
                    '${running ? '运行中' : '已停止'}  ·  ${enabled ? '开机启动' : '未启用'}',
                  ),
                  leading: busy
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          running
                              ? Icons.check_circle_outline_rounded
                              : Icons.pause_circle_outline_rounded,
                          color: running ? Colors.green : null,
                        ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => unawaited(
                                    _runAction(
                                      entry.key,
                                      enabled ? 'disable' : 'enable',
                                    ),
                                  ),
                            child: Text(enabled ? '禁用启动' : '启用启动'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () =>
                                      unawaited(_runAction(entry.key, 'start')),
                            child: const Text('启动'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => unawaited(
                                    _runAction(entry.key, 'restart'),
                                  ),
                            child: const Text('重启'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () =>
                                      unawaited(_runAction(entry.key, 'stop')),
                            child: const Text('停止'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ToolError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ToolError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
