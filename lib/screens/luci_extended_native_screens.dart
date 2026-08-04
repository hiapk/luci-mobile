import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/luci_standard_native_screens.dart';
import 'package:luci_mobile/services/luci_native_parsers.dart';
import 'package:luci_mobile/widgets/native_navigation_bar.dart';

class RouterPackageManagerScreen extends ConsumerStatefulWidget {
  const RouterPackageManagerScreen({super.key});

  @override
  ConsumerState<RouterPackageManagerScreen> createState() =>
      _RouterPackageManagerScreenState();
}

class _RouterPackageManagerScreenState
    extends ConsumerState<RouterPackageManagerScreen> {
  final _searchController = TextEditingController();
  late Future<List<RouterPackageInfo>> _future = _load();
  String _query = '';
  bool _installedOnly = true;
  bool _busy = false;

  Future<List<RouterPackageInfo>> _load() =>
      ref.read(appStateProvider).fetchPackageCatalog(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _run(String action, [RouterPackageInfo? package]) async {
    final label = switch (action) {
      'update' => '更新软件源',
      'install' => '安装',
      'upgrade' => '升级',
      'remove' => '卸载',
      _ => action,
    };
    if (action == 'remove') {
      final confirmed = await confirmNativeRouterAction(
        context,
        title: '卸载 ${package!.name}？',
        message: package.essential
            ? '这是必需软件包，卸载可能导致系统无法启动。'
            : '其它依赖该软件包的功能可能同时失效。',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final output = await ref
          .read(appStateProvider)
          .runPackageAction(
            action,
            packages: package == null ? const [] : [package.name],
            context: context,
          );
      if (!mounted) return;
      await showNativeRouterMessage(
        context,
        output.isEmpty ? '$label完成' : output,
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '软件包',
      onRefresh: _reload,
      trailing: _busy
          ? const CupertinoActivityIndicator()
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _run('update'),
              child: const Icon(CupertinoIcons.arrow_2_circlepath, size: 21),
            ),
      child: FutureBuilder<List<RouterPackageInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final query = _query.trim().toLowerCase();
          final packages = (snapshot.data ?? const <RouterPackageInfo>[])
              .where((item) => !_installedOnly || item.installed)
              .where(
                (item) =>
                    query.isEmpty ||
                    item.name.toLowerCase().contains(query) ||
                    item.description.toLowerCase().contains(query),
              )
              .take(300)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '搜索软件包',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              CupertinoSlidingSegmentedControl<bool>(
                groupValue: _installedOnly,
                children: const {true: Text('已安装'), false: Text('全部')},
                onValueChanged: (value) {
                  if (value != null) setState(() => _installedOnly = value);
                },
              ),
              const SizedBox(height: 12),
              CupertinoListSection.insetGrouped(
                margin: EdgeInsets.zero,
                header: Text('显示 ${packages.length} 项'),
                children: packages.map((item) {
                  return CupertinoListTile(
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.description.isEmpty
                          ? item.version
                          : '${item.version}  ${item.description}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    additionalInfo: Text(item.installed ? '已安装' : '可安装'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _busy
                        ? null
                        : () => _showPackageActions(context, item),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPackageActions(
    BuildContext context,
    RouterPackageInfo package,
  ) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(package.name),
        message: Text(package.description),
        actions: [
          if (!package.installed)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(popupContext, 'install'),
              child: const Text('安装'),
            ),
          if (package.installed)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(popupContext, 'upgrade'),
              child: const Text('升级'),
            ),
          if (package.installed)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(popupContext, 'remove'),
              child: const Text('卸载'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
    if (action != null && mounted) await _run(action, package);
  }
}

class RouterDockerScreen extends ConsumerStatefulWidget {
  final String initialSection;

  const RouterDockerScreen({super.key, this.initialSection = 'overview'});

  @override
  ConsumerState<RouterDockerScreen> createState() => _RouterDockerScreenState();
}

class _RouterDockerScreenState extends ConsumerState<RouterDockerScreen> {
  late String _section = _normalizeSection(widget.initialSection);
  late Future<Map<String, dynamic>> _future = _load();
  bool _busy = false;

  static String _normalizeSection(String value) =>
      const {
        'containers',
        'images',
        'networks',
        'volumes',
        'events',
      }.contains(value)
      ? value
      : 'overview';

  Future<Map<String, dynamic>> _load() async {
    final state = ref.read(appStateProvider);
    final overview = await state.fetchDockerOverview(context: context);
    if (_section == 'events' && mounted) {
      overview['events'] = await state.fetchDockerEvents(context: context);
    }
    return overview;
  }

  void _reload() => setState(() => _future = _load());

  void _setSection(String value) {
    setState(() {
      _section = value;
      _future = _load();
    });
  }

  Future<void> _containerAction(
    Map<String, dynamic> container,
    String action,
  ) async {
    final target = (container['ID'] ?? container['Names'])?.toString() ?? '';
    if (action == 'logs') {
      try {
        final logs = await ref
            .read(appStateProvider)
            .fetchDockerContainerLogs(target, context: context);
        if (!mounted) return;
        await Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => _NativeTextViewerScreen(
              title: container['Names']?.toString() ?? '容器日志',
              text: logs,
            ),
          ),
        );
      } catch (error) {
        if (mounted) await showNativeRouterError(context, error);
      }
      return;
    }
    if (action == 'remove') {
      final confirmed = await confirmNativeRouterAction(
        context,
        title: '强制删除容器？',
        message: '${container['Names'] ?? target}\n容器内未挂载的数据会丢失。',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(appStateProvider)
          .controlDockerContainer(target, action, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage(Map<String, dynamic> image) async {
    final target = (image['ID'] ?? image['Repository'])?.toString() ?? '';
    final confirmed = await confirmNativeRouterAction(
      context,
      title: '删除镜像？',
      message: '${image['Repository'] ?? target}:${image['Tag'] ?? ''}',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(appStateProvider)
          .removeDockerImage(target, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pullImage() async {
    final image = await promptNativeRouterText(
      context,
      title: '镜像名称（例如 nginx:latest）',
      initialValue: '',
    );
    if (image == null || image.isEmpty || !mounted) return;
    final confirmed = await confirmNativeRouterAction(
      context,
      title: '拉取镜像？',
      message: image,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(appStateProvider).pullDockerImage(image, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createContainer() async {
    final values = await Navigator.of(context).push<Map<String, dynamic>>(
      CupertinoPageRoute(builder: (_) => const _DockerCreateScreen()),
    );
    if (values == null || !mounted) return;
    final confirmed = await confirmNativeRouterAction(
      context,
      title: '创建容器？',
      message: '${values['name']}\n${values['image']}',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(appStateProvider)
          .createDockerContainer(
            name: values['name'].toString(),
            image: values['image'].toString(),
            ports: (values['ports'] as List).cast<String>(),
            volumes: (values['volumes'] as List).cast<String>(),
            start: values['start'] == true,
            context: context,
          );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCreateActions() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, 'create'),
            child: const Text('创建容器'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, 'pull'),
            child: const Text('拉取镜像'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'create') await _createContainer();
    if (action == 'pull') await _pullImage();
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: 'Docker',
      onRefresh: _reload,
      trailing: _busy
          ? const CupertinoActivityIndicator()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.only(right: 12),
                  onPressed: _showCreateActions,
                  child: const Icon(CupertinoIcons.add, size: 22),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _reload,
                  child: const Icon(CupertinoIcons.refresh, size: 21),
                ),
              ],
            ),
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
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children:
                      const {
                        'overview': '概览',
                        'containers': '容器',
                        'images': '镜像',
                        'networks': '网络',
                        'volumes': '存储卷',
                        'events': '事件',
                      }.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: _section == entry.key
                                ? CupertinoColors.activeBlue
                                : CupertinoColors
                                      .secondarySystemGroupedBackground
                                      .resolveFrom(context),
                            onPressed: () => _setSection(entry.key),
                            child: Text(entry.value),
                          ),
                        );
                      }).toList(),
                ),
              ),
              Expanded(child: _buildDockerSection(data)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDockerSection(Map<String, dynamic> data) {
    if (_section == 'overview') {
      final info = _map(data['info']);
      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          CupertinoListSection.insetGrouped(
            header: const Text('Docker 引擎'),
            children: [
              NativeValueTile(
                label: '版本',
                value: info['ServerVersion']?.toString() ?? '-',
              ),
              NativeValueTile(
                label: '容器',
                value: '${(data['containers'] as List?)?.length ?? 0}',
              ),
              NativeValueTile(
                label: '镜像',
                value: '${(data['images'] as List?)?.length ?? 0}',
              ),
              NativeValueTile(
                label: '存储驱动',
                value: info['Driver']?.toString() ?? '-',
              ),
              NativeValueTile(
                label: '根目录',
                value: info['DockerRootDir']?.toString() ?? '-',
              ),
            ],
          ),
        ],
      );
    }
    final entries =
        (data[_section] as List?)?.whereType<Map>().map(_map).toList() ??
        const <Map<String, dynamic>>[];
    if (entries.isEmpty) return const NativeRouterEmpty(label: '暂无数据');
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        CupertinoListSection.insetGrouped(
          children: entries.map((entry) {
            if (_section == 'containers') return _containerTile(entry);
            if (_section == 'images') {
              return CupertinoListTile(
                title: Text(
                  '${entry['Repository'] ?? '<none>'}:${entry['Tag'] ?? ''}',
                ),
                subtitle: Text('${entry['Size'] ?? '-'}  ${entry['ID'] ?? ''}'),
                trailing: const Icon(
                  CupertinoIcons.delete,
                  color: CupertinoColors.systemRed,
                  size: 20,
                ),
                onTap: _busy ? null : () => _removeImage(entry),
              );
            }
            final title =
                entry['Name'] ??
                entry['Type'] ??
                entry['Action'] ??
                entry.values.firstOrNull ??
                '-';
            return CupertinoListTile(
              title: Text(title.toString()),
              subtitle: Text(
                entry.entries
                    .skip(1)
                    .take(3)
                    .map((item) => '${item.key}: ${item.value}')
                    .join('  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _containerTile(Map<String, dynamic> container) {
    final state = container['State']?.toString() ?? '';
    return CupertinoListTile(
      title: Text(container['Names']?.toString() ?? container['ID'].toString()),
      subtitle: Text(
        '${container['Image'] ?? '-'}\n${container['Status'] ?? state}',
      ),
      additionalInfo: Text(state),
      trailing: const CupertinoListTileChevron(),
      onTap: _busy
          ? null
          : () async {
              final action = await showCupertinoModalPopup<String>(
                context: context,
                builder: (popupContext) => CupertinoActionSheet(
                  title: Text(container['Names']?.toString() ?? '容器'),
                  actions: [
                    CupertinoActionSheetAction(
                      onPressed: () => Navigator.pop(popupContext, 'logs'),
                      child: const Text('查看日志'),
                    ),
                    if (state != 'running')
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popupContext, 'start'),
                        child: const Text('启动'),
                      ),
                    if (state == 'running') ...[
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popupContext, 'restart'),
                        child: const Text('重启'),
                      ),
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popupContext, 'stop'),
                        child: const Text('停止'),
                      ),
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popupContext, 'pause'),
                        child: const Text('暂停'),
                      ),
                    ],
                    if (state == 'paused')
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popupContext, 'unpause'),
                        child: const Text('恢复'),
                      ),
                    CupertinoActionSheetAction(
                      isDestructiveAction: true,
                      onPressed: () => Navigator.pop(popupContext, 'remove'),
                      child: const Text('强制删除'),
                    ),
                  ],
                  cancelButton: CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(popupContext),
                    child: const Text('取消'),
                  ),
                ),
              );
              if (action != null && mounted) {
                await _containerAction(container, action);
              }
            },
    );
  }
}

class _DockerCreateScreen extends StatefulWidget {
  const _DockerCreateScreen();

  @override
  State<_DockerCreateScreen> createState() => _DockerCreateScreenState();
}

class _DockerCreateScreenState extends State<_DockerCreateScreen> {
  final _name = TextEditingController();
  final _image = TextEditingController();
  final _ports = TextEditingController();
  final _volumes = TextEditingController();
  bool _start = true;

  @override
  void dispose() {
    _name.dispose();
    _image.dispose();
    _ports.dispose();
    _volumes.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || _image.text.trim().isEmpty) return;
    List<String> mappings(String value) => value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    Navigator.of(context).pop(<String, dynamic>{
      'name': _name.text.trim(),
      'image': _image.text.trim(),
      'ports': mappings(_ports.text),
      'volumes': mappings(_volumes.text),
      'start': _start,
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: NativeNavigationBar(
        context: context,
        middle: const Text('创建容器'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: const Text('下一步'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            CupertinoTextField(
              controller: _name,
              placeholder: '容器名称',
              autocorrect: false,
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _image,
              placeholder: '镜像，例如 nginx:latest',
              autocorrect: false,
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _ports,
              placeholder: '端口，例如 8080:80, 8443:443',
              autocorrect: false,
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _volumes,
              placeholder: '目录，例如 /mnt/data:/data',
              autocorrect: false,
              padding: const EdgeInsets.all(13),
            ),
            const SizedBox(height: 12),
            CupertinoListSection.insetGrouped(
              margin: EdgeInsets.zero,
              children: [
                CupertinoListTile(
                  title: const Text('创建后立即启动'),
                  trailing: CupertinoSwitch(
                    value: _start,
                    onChanged: (value) => setState(() => _start = value),
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

class RouterSwitchScreen extends ConsumerStatefulWidget {
  const RouterSwitchScreen({super.key});

  @override
  ConsumerState<RouterSwitchScreen> createState() => _RouterSwitchScreenState();
}

class _RouterSwitchScreenState extends ConsumerState<RouterSwitchScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  final _busy = <String>{};

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchSwitchOverview(context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _control(String interface, String action) async {
    if (action == 'down') {
      final confirmed = await confirmNativeRouterAction(
        context,
        title: '断开 $interface？',
        message: '如果当前正通过该接口连接，App 会立即失联。',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy.add(interface));
    try {
      await ref
          .read(appStateProvider)
          .controlNetworkInterface(interface, action, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(interface));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '网络接口',
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
          final dump = _map(snapshot.data?['interfaces']);
          final interfaces =
              (dump['interface'] as List?)
                  ?.whereType<Map>()
                  .map(_map)
                  .where((item) => item['interface'] != 'loopback')
                  .toList() ??
              const <Map<String, dynamic>>[];
          if (interfaces.isEmpty) {
            return const NativeRouterEmpty(label: '没有可管理的接口');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: interfaces.map((item) {
              final name = item['interface']?.toString() ?? '-';
              final up = item['up'] == true;
              return CupertinoListSection.insetGrouped(
                header: Text(name),
                children: [
                  NativeValueTile(label: '状态', value: up ? '已连接' : '已断开'),
                  NativeValueTile(
                    label: '设备',
                    value:
                        item['l3_device']?.toString() ??
                        item['device']?.toString() ??
                        '-',
                  ),
                  NativeValueTile(
                    label: '协议',
                    value: item['proto']?.toString() ?? '-',
                  ),
                  CupertinoListTile(
                    title: const Text('接口操作'),
                    trailing: _busy.contains(name)
                        ? const CupertinoActivityIndicator()
                        : CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _showInterfaceActions(name, up),
                            child: const Icon(
                              CupertinoIcons.ellipsis_circle,
                              size: 22,
                            ),
                          ),
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _showInterfaceActions(String name, bool up) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(name),
        actions: [
          if (!up)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(popupContext, 'up'),
              child: const Text('连接'),
            ),
          if (up)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(popupContext, 'renew'),
              child: const Text('重新获取租约'),
            ),
          if (up)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(popupContext, 'down'),
              child: const Text('断开'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
    if (action != null && mounted) await _control(name, action);
  }
}

class RouterStorageManagementScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenAdvanced;

  const RouterStorageManagementScreen({super.key, this.onOpenAdvanced});

  @override
  ConsumerState<RouterStorageManagementScreen> createState() =>
      _RouterStorageManagementScreenState();
}

class _RouterStorageManagementScreenState
    extends ConsumerState<RouterStorageManagementScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  final _busy = <String>{};

  Future<Map<String, dynamic>> _load() => ref
      .read(appStateProvider)
      .fetchStorageManagementOverview(context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _toggle(
    String config,
    String section,
    Map<String, dynamic> values,
    bool enabled,
  ) async {
    final key = '$config/$section';
    setState(() => _busy.add(key));
    try {
      await ref.read(appStateProvider).setUciSection(config, section, {
        ...values,
        'enabled': enabled ? '1' : '0',
      }, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '存储与 NAS',
      onRefresh: _reload,
      trailing: widget.onOpenAdvanced == null
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: widget.onOpenAdvanced,
              child: const Icon(CupertinoIcons.slider_horizontal_3, size: 21),
            ),
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
          final mounts =
              (data['mounts'] as List?)?.whereType<Map>().toList() ??
              const <Map>[];
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('挂载点'),
                children: mounts.isEmpty
                    ? [const CupertinoListTile(title: Text('暂无挂载'))]
                    : mounts.map((mount) {
                        return CupertinoListTile(
                          title: Text(mount['mount']?.toString() ?? '-'),
                          subtitle: Text(
                            '${mount['device'] ?? '-'}  ${mount['fstype'] ?? ''}',
                          ),
                          additionalInfo: Text(
                            '${formatBytes(mountUsedBytes(mount))} / ${formatBytes(_num(mount['size']))}',
                          ),
                        );
                      }).toList(),
              ),
              ..._shareSections(data, 'mergerfs', 'MergerFS 存储池'),
              ..._shareSections(data, 'cifs', 'SMB / WebDAV'),
              ..._shareSections(data, 'nfs', 'NFS 共享与挂载'),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _shareSections(
    Map<String, dynamic> data,
    String config,
    String title,
  ) {
    final sections = _map(data[config]).entries
        .where((entry) => entry.value is Map)
        .map((entry) => MapEntry(entry.key, _map(entry.value)))
        .toList();
    if (sections.isEmpty) return const [];
    return [
      CupertinoListSection.insetGrouped(
        header: Text(title),
        children: sections.map((entry) {
          final values = entry.value;
          final name =
              values['name'] ??
              values['mountpoint'] ??
              values['path'] ??
              values['target'] ??
              entry.key;
          final key = '$config/${entry.key}';
          return CupertinoListTile(
            title: Text(name.toString()),
            subtitle: Text(
              values.entries
                  .where(
                    (item) =>
                        !item.key.startsWith('.') &&
                        !const {'pwd', 'password'}.contains(item.key),
                  )
                  .take(3)
                  .map((item) => '${item.key}: ${item.value}')
                  .join('  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _busy.contains(key)
                ? const CupertinoActivityIndicator()
                : CupertinoSwitch(
                    value: _bool(values['enabled']),
                    onChanged: (value) =>
                        _toggle(config, entry.key, values, value),
                  ),
          );
        }).toList(),
      ),
    ];
  }
}

class RouterSystemUpdateScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenAdvanced;

  const RouterSystemUpdateScreen({super.key, required this.onOpenAdvanced});

  @override
  ConsumerState<RouterSystemUpdateScreen> createState() =>
      _RouterSystemUpdateScreenState();
}

class _RouterSystemUpdateScreenState
    extends ConsumerState<RouterSystemUpdateScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _busy = false;

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchSystemUpdateOverview(context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _action(String action) async {
    if (action == 'download') {
      final confirmed = await confirmNativeRouterAction(
        context,
        title: '下载系统更新？',
        message: '固件会下载到路由器临时目录，不会自动刷写。',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final output = await ref
          .read(appStateProvider)
          .controlSystemUpdate(action, context: context);
      if (!mounted) return;
      await showNativeRouterMessage(
        context,
        output.trim().isEmpty ? '操作已完成' : _plainText(output),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '系统更新',
      onRefresh: _reload,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: widget.onOpenAdvanced,
        child: const Icon(CupertinoIcons.arrow_up_doc, size: 21),
      ),
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
          final release = _releaseFields(data['release']?.toString() ?? '');
          final update = _plainText(data['update']?.toString() ?? '');
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('当前系统'),
                children: [
                  NativeValueTile(
                    label: '名称',
                    value: release['PRETTY_NAME'] ?? release['NAME'] ?? '-',
                  ),
                  NativeValueTile(
                    label: '版本',
                    value: release['VERSION'] ?? release['VERSION_ID'] ?? '-',
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('可用更新'),
                children: [
                  CupertinoListTile(
                    title: Text(
                      update.isEmpty ? '当前没有更新信息' : update,
                      maxLines: 12,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.activeBlue,
                        onPressed: _busy ? null : () => _action('check'),
                        child: const Text('检查'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: _busy ? null : () => _action('download'),
                        child: _busy
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              )
                            : const Text('下载'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton(
                  onPressed: widget.onOpenAdvanced,
                  child: const Text('验证并刷写已下载的固件'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterSystemTuningScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenAdvanced;

  const RouterSystemTuningScreen({super.key, required this.onOpenAdvanced});

  @override
  ConsumerState<RouterSystemTuningScreen> createState() =>
      _RouterSystemTuningScreenState();
}

class _RouterSystemTuningScreenState
    extends ConsumerState<RouterSystemTuningScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(appStateProvider).fetchSystemTuningOverview(context: context);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '系统调优',
      onRefresh: _reload,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: widget.onOpenAdvanced,
        child: const Icon(CupertinoIcons.slider_horizontal_3, size: 21),
      ),
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
          final config = _map(data['config']);
          final sensors = data['sensors']?.toString() ?? '';
          final cpuinfo = data['cpuinfo']?.toString() ?? '';
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('CPU'),
                children: [
                  NativeValueTile(
                    label: '逻辑核心',
                    value:
                        '${RegExp(r'^processor\s*:', multiLine: true).allMatches(cpuinfo).length}',
                  ),
                  NativeValueTile(
                    label: '调频配置',
                    value: config.isEmpty ? '未配置' : '${config.length} 项',
                  ),
                  CupertinoListTile(
                    title: const Text('传感器详情'),
                    subtitle: Text(
                      sensors
                          .split('\n')
                          .where((line) => line.contains('°C'))
                          .take(3)
                          .join('\n'),
                      maxLines: 3,
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => _NativeTextViewerScreen(
                          title: '硬件传感器',
                          text: sensors,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton.filled(
                  onPressed: widget.onOpenAdvanced,
                  child: const Text('打开完整调优项'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RouterBackupFirmwareScreen extends StatelessWidget {
  final VoidCallback onOpenAdvanced;

  const RouterBackupFirmwareScreen({super.key, required this.onOpenAdvanced});

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: '备份与固件',
      onRefresh: () {},
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                leading: const Icon(CupertinoIcons.archivebox),
                title: const Text('备份与恢复'),
                subtitle: const Text('下载配置备份或上传已有备份'),
                trailing: const CupertinoListTileChevron(),
                onTap: onOpenAdvanced,
              ),
              CupertinoListTile(
                leading: const Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: CupertinoColors.systemOrange,
                ),
                title: const Text('刷写固件'),
                subtitle: const Text('上传、校验后才会进入刷写确认'),
                trailing: const CupertinoListTileChevron(),
                onTap: onOpenAdvanced,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RouterFileManagerScreen extends ConsumerStatefulWidget {
  const RouterFileManagerScreen({super.key, this.path = '/root'});

  final String path;

  @override
  ConsumerState<RouterFileManagerScreen> createState() =>
      _RouterFileManagerScreenState();
}

class _RouterFileManagerScreenState
    extends ConsumerState<RouterFileManagerScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => ref
      .read(appStateProvider)
      .listRouterDirectory(widget.path, context: context);

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Map<String, dynamic> entry) async {
    final name = entry['name']?.toString() ?? '';
    final path = '${widget.path}/$name'.replaceAll('//', '/');
    if (entry['type'] == 'directory') {
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => RouterFileManagerScreen(path: path),
        ),
      );
      if (mounted) _reload();
      return;
    }
    try {
      final value = await ref
          .read(appStateProvider)
          .readRouterFile(path, context: context);
      if (!mounted) return;
      final edited = await Navigator.of(context).push<String>(
        CupertinoPageRoute<String>(
          builder: (_) =>
              RouterTextFileEditorScreen(title: name, initialValue: value),
        ),
      );
      if (edited != null && mounted) {
        final confirmed = await confirmNativeRouterAction(
          context,
          title: '覆盖 $name？',
          message: '保存后会立即覆盖路由器上的原文件。',
        );
        if (confirmed && mounted) {
          await ref
              .read(appStateProvider)
              .writeRouterFile(path, edited, context: context);
          if (mounted) _reload();
        }
      }
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final name = entry['name']?.toString() ?? '';
    final path = '${widget.path}/$name'.replaceAll('//', '/');
    final confirmed = await confirmNativeRouterAction(
      context,
      title: '删除 $name？',
      message: '该操作不能撤销。非空目录会被路由器拒绝。',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(appStateProvider).removeRouterPath(path, context: context);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) await showNativeRouterError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NativeRouterScaffold(
      title: widget.path,
      onRefresh: _reload,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const NativeRouterLoading();
          }
          if (snapshot.hasError) {
            return NativeRouterError(error: snapshot.error, onRetry: _reload);
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) return const NativeRouterEmpty(label: '空目录');
          return ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              CupertinoListSection.insetGrouped(
                children: entries.map((entry) {
                  final directory = entry['type'] == 'directory';
                  return CupertinoListTile(
                    leading: Icon(
                      directory
                          ? CupertinoIcons.folder_fill
                          : CupertinoIcons.doc_fill,
                      color: directory
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey,
                    ),
                    title: Text(
                      entry['name']?.toString() ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      directory ? '目录' : formatBytes(_num(entry['size'])),
                    ),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => _delete(entry),
                      child: const Icon(
                        CupertinoIcons.delete,
                        color: CupertinoColors.systemRed,
                        size: 19,
                      ),
                    ),
                    onTap: () => _open(entry),
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

class _NativeTextViewerScreen extends StatelessWidget {
  final String title;
  final String text;

  const _NativeTextViewerScreen({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: NativeNavigationBar(context: context, middle: Text(title)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            text.isEmpty ? '暂无内容' : text,
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

bool _bool(dynamic value) {
  return const {
    '1',
    'true',
    'yes',
    'on',
  }.contains(value?.toString().toLowerCase());
}

num _num(dynamic value) => num.tryParse(value?.toString() ?? '') ?? 0;

Map<String, String> _releaseFields(String value) {
  final fields = <String, String>{};
  for (final line in value.split('\n')) {
    final index = line.indexOf('=');
    if (index <= 0) continue;
    fields[line.substring(0, index)] = line
        .substring(index + 1)
        .replaceAll(RegExp(r'^[\"\x27]|[\"\x27]$'), '');
  }
  return fields;
}

String _plainText(String value) => value
    .replaceAll(RegExp(r'<[^>]+>'), '\n')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
