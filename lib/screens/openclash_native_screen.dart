import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import 'package:luci_mobile/services/openclash_group_probe.dart';
import 'package:luci_mobile/services/openclash_network_service.dart';
import 'package:luci_mobile/widgets/native_navigation_bar.dart';

enum _MetaCubePage { overview, nodes }

class MetaCubeXdScreen extends ConsumerStatefulWidget {
  final bool loadOnInit;
  final OpenClashNetworkService? networkService;

  const MetaCubeXdScreen({
    super.key,
    this.loadOnInit = true,
    this.networkService,
  });

  @override
  ConsumerState<MetaCubeXdScreen> createState() => _MetaCubeXdScreenState();
}

class _MetaCubeXdScreenState extends ConsumerState<MetaCubeXdScreen> {
  static const _pollInterval = Duration(seconds: 2);
  static const _historyLimit = 36;

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedGroups = {};
  final Set<String> _pendingActions = {};
  late final OpenClashNetworkService _networkService;
  late final bool _ownsNetworkService;

  Timer? _pollTimer;
  _MetaCubePage _page = _MetaCubePage.overview;
  OpenClashOverview? _overview;
  OpenClashProxySnapshot? _proxySnapshot;
  Object? _overviewError;
  Object? _proxyError;
  OpenClashIpInfo? _ipInfo;
  List<OpenClashLatencyResult> _latencyResults = const [];
  Object? _ipInfoError;
  bool _loadingOverview = false;
  bool _loadingProxies = false;
  bool _loadingIpInfo = false;
  bool _testingLatencies = false;
  bool _testingAllGroups = false;
  bool _switchingMode = false;
  int _testedGroupCount = 0;
  int _totalGroupCount = 0;
  double _uploadRate = 0;
  double _downloadRate = 0;
  final List<double> _uploadHistory = [];
  final List<double> _downloadHistory = [];

  @override
  void initState() {
    super.initState();
    _ownsNetworkService = widget.networkService == null;
    _networkService = widget.networkService ?? OpenClashNetworkService();
    _searchController.addListener(_searchChanged);
    if (!widget.loadOnInit) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initialLoad());
      _pollTimer = Timer.periodic(
        _pollInterval,
        (_) => unawaited(_loadOverview()),
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_ownsNetworkService) _networkService.dispose();
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialLoad() async {
    await Future.wait([_loadOverview(), _loadDeviceNetwork()]);
  }

  Future<void> _refreshCurrentPage() async {
    if (_page == _MetaCubePage.nodes) {
      await _loadProxies();
      return;
    }
    await Future.wait([_loadOverview(), _loadDeviceNetwork()]);
  }

  Future<void> _loadDeviceNetwork() async {
    await Future.wait([_loadIpInfo(), _testNetworkLatencies()]);
  }

  Future<void> _loadIpInfo() async {
    if (_loadingIpInfo) return;
    if (mounted) setState(() => _loadingIpInfo = true);
    try {
      final info = await _networkService.fetchIpInfo();
      if (!mounted) return;
      setState(() {
        _ipInfo = info;
        _ipInfoError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _ipInfoError = error);
    } finally {
      if (mounted) setState(() => _loadingIpInfo = false);
    }
  }

  Future<void> _testNetworkLatencies() async {
    if (_testingLatencies) return;
    if (mounted) setState(() => _testingLatencies = true);
    try {
      final results = await _networkService.testLatencies();
      if (!mounted) return;
      setState(() => _latencyResults = results);
    } finally {
      if (mounted) setState(() => _testingLatencies = false);
    }
  }

  Future<void> _loadOverview() async {
    if (_loadingOverview) return;
    _loadingOverview = true;
    try {
      final next = await ref
          .read(appStateProvider)
          .fetchOpenClashOverview(context: context);
      if (!mounted) return;
      final previous = _overview;
      final elapsed = previous == null
          ? 0
          : next.timestamp - previous.timestamp;
      final uploadDelta = previous == null
          ? 0
          : next.uploadTotal - previous.uploadTotal;
      final downloadDelta = previous == null
          ? 0
          : next.downloadTotal - previous.downloadTotal;
      final uploadRate = elapsed > 0 && uploadDelta >= 0
          ? uploadDelta / elapsed
          : 0.0;
      final downloadRate = elapsed > 0 && downloadDelta >= 0
          ? downloadDelta / elapsed
          : 0.0;
      setState(() {
        _overview = next;
        _overviewError = null;
        _uploadRate = uploadRate;
        _downloadRate = downloadRate;
        _appendHistory(_uploadHistory, uploadRate);
        _appendHistory(_downloadHistory, downloadRate);
      });
    } catch (error) {
      if (mounted) setState(() => _overviewError = error);
    } finally {
      _loadingOverview = false;
    }
  }

  Future<void> _loadProxies() async {
    if (_loadingProxies) return;
    if (mounted) setState(() => _loadingProxies = true);
    try {
      final snapshot = await ref
          .read(appStateProvider)
          .fetchOpenClashProxies(context: context);
      if (!mounted) return;
      setState(() {
        _proxySnapshot = snapshot;
        _proxyError = null;
        if (_expandedGroups.isEmpty && snapshot.groups.isNotEmpty) {
          final preferred = snapshot.groups.where(
            (group) => group.name.contains('节点选择'),
          );
          _expandedGroups.add(
            preferred.isEmpty
                ? snapshot.groups.first.name
                : preferred.first.name,
          );
        }
      });
    } catch (error) {
      if (mounted) setState(() => _proxyError = error);
    } finally {
      if (mounted) setState(() => _loadingProxies = false);
    }
  }

  void _appendHistory(List<double> history, double value) {
    history.add(value.isFinite && value >= 0 ? value : 0);
    if (history.length > _historyLimit) history.removeAt(0);
  }

  Future<void> _switchMode(OpenClashMode mode) async {
    if (_testingAllGroups || _switchingMode || mode == _overview?.mode) return;
    setState(() => _switchingMode = true);
    try {
      final selected = await ref
          .read(appStateProvider)
          .switchOpenClashMode(mode, context: context);
      if (!mounted) return;
      final current = _overview;
      if (current != null) {
        setState(() {
          _overview = OpenClashOverview(
            running: current.running,
            version: current.version,
            mode: selected,
            uploadTotal: current.uploadTotal,
            downloadTotal: current.downloadTotal,
            connectionCount: current.connectionCount,
            memoryBytes: current.memoryBytes,
            timestamp: current.timestamp,
          );
        });
      }
    } catch (error) {
      if (mounted) await _showActionError(error);
    } finally {
      if (mounted) setState(() => _switchingMode = false);
    }
  }

  Future<void> _selectProxy(String group, String proxy) async {
    final key = 'select:$group';
    if (_testingAllGroups || _pendingActions.contains(key)) return;
    setState(() => _pendingActions.add(key));
    try {
      await ref
          .read(appStateProvider)
          .selectOpenClashProxy(group, proxy, context: context);
      await _loadProxies();
    } catch (error) {
      if (mounted) await _showActionError(error);
    } finally {
      if (mounted) setState(() => _pendingActions.remove(key));
    }
  }

  Future<void> _testDelay({
    required String kind,
    required String name,
    String? provider,
  }) async {
    final key = 'delay:$kind:${provider ?? ''}:$name';
    if (_testingAllGroups || _pendingActions.contains(key)) return;
    setState(() => _pendingActions.add(key));
    try {
      await ref
          .read(appStateProvider)
          .testOpenClashDelay(
            kind: kind,
            name: name,
            provider: provider,
            context: context,
          );
      await _loadProxies();
    } catch (error) {
      if (mounted) await _showActionError(error);
    } finally {
      if (mounted) setState(() => _pendingActions.remove(key));
    }
  }

  Future<Map<String, dynamic>> _testGroupForBatch(String group) async {
    final key = 'delay:group::$group';
    if (_pendingActions.contains(key)) return const {};
    if (mounted) setState(() => _pendingActions.add(key));
    try {
      final result = await ref
          .read(appStateProvider)
          .testOpenClashDelay(kind: 'group', name: group, context: context);
      await _loadProxies();
      return result;
    } finally {
      if (mounted) {
        setState(() {
          _pendingActions.remove(key);
          _testedGroupCount++;
        });
      }
    }
  }

  Future<void> _testAllGroups() async {
    final snapshot = _proxySnapshot;
    if (_testingAllGroups ||
        _pendingActions.isNotEmpty ||
        snapshot == null ||
        snapshot.groups.isEmpty) {
      return;
    }
    final groups = snapshot.groups.map((group) => group.name).toList();
    Object? firstFailure;
    var failureCount = 0;
    setState(() {
      _testingAllGroups = true;
      _testedGroupCount = 0;
      _totalGroupCount = groups.length;
    });
    try {
      await testOpenClashGroupsSequentially(groups, (group) async {
        try {
          return await _testGroupForBatch(group);
        } on LuciSessionExpiredException {
          rethrow;
        } catch (error) {
          firstFailure ??= error;
          failureCount++;
          return const {};
        }
      });
      if (mounted && firstFailure != null) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('测速完成'),
            content: Text('$failureCount 个策略测速失败。\n$firstFailure'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('好'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) await _showActionError(error);
    } finally {
      if (mounted) {
        setState(() {
          _testingAllGroups = false;
          _testedGroupCount = 0;
          _totalGroupCount = 0;
        });
      }
    }
  }

  Future<void> _showActionError(Object error) async {
    final expired = error is LuciSessionExpiredException;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(expired ? '会话已过期' : '操作失败'),
        content: Text(error.toString()),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
          if (expired)
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              },
              child: const Text('重新登录'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
      color: CupertinoColors.label.resolveFrom(context),
      decoration: TextDecoration.none,
    );
    return DefaultTextStyle(
      style: textStyle,
      child: CupertinoPageScaffold(
        backgroundColor: background,
        navigationBar: NativeNavigationBar(
          context: context,
          middle: const Text('MetaCubeXD'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed:
                _loadingOverview ||
                    _loadingProxies ||
                    _loadingIpInfo ||
                    _testingLatencies ||
                    _testingAllGroups
                ? null
                : () => unawaited(_refreshCurrentPage()),
            child: const Icon(CupertinoIcons.refresh, size: 21),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<_MetaCubePage>(
                    groupValue: _page,
                    children: const {
                      _MetaCubePage.overview: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text('概览'),
                      ),
                      _MetaCubePage.nodes: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text('节点'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() => _page = value);
                      if (value == _MetaCubePage.nodes &&
                          _proxySnapshot == null) {
                        unawaited(_loadProxies());
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _page.index,
                  children: [_buildOverview(), _buildNodes()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverview() {
    final overview = _overview;
    if (overview == null && _overviewError != null) {
      return _OpenClashError(
        error: _overviewError!,
        onRetry: () => unawaited(_loadOverview()),
      );
    }
    if (overview == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return CustomScrollView(
      key: const PageStorageKey('openclash-overview'),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            await Future.wait([_loadOverview(), _loadDeviceNetwork()]);
          },
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.list(
            children: [
              _buildStatusHeader(overview),
              const SizedBox(height: 14),
              _buildMetricGrid(overview),
              const SizedBox(height: 14),
              _buildNetworkCards(),
              const SizedBox(height: 14),
              _TrafficChart(upload: _uploadHistory, download: _downloadHistory),
              const SizedBox(height: 14),
              _buildOverviewDetails(overview),
              if (_overviewError != null) ...[
                const SizedBox(height: 12),
                _InlineError(error: _overviewError!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusHeader(OpenClashOverview overview) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final border = CupertinoColors.separator.resolveFrom(context);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue
                  .resolveFrom(context)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              CupertinoIcons.cube_box_fill,
              color: CupertinoColors.activeBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MetaCube XD',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  overview.version.isEmpty ? 'Mihomo' : overview.version,
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: overview.running
                  ? CupertinoColors.systemGreen
                  : CupertinoColors.systemRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            overview.running ? '运行中' : '已停止',
            style: TextStyle(
              color: CupertinoColors.label.resolveFrom(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(OpenClashOverview overview) {
    final metrics = [
      _MetricData(
        label: '上传',
        value: '${_formatBytes(_uploadRate)}/s',
        icon: CupertinoIcons.arrow_up_right,
      ),
      _MetricData(
        label: '下载',
        value: '${_formatBytes(_downloadRate)}/s',
        icon: CupertinoIcons.arrow_down_left,
      ),
      _MetricData(
        label: '活跃连接',
        value: '${overview.connectionCount}',
        icon: CupertinoIcons.link,
      ),
      _MetricData(
        label: '内存',
        value: _formatBytes(overview.memoryBytes.toDouble()),
        icon: CupertinoIcons.layers_fill,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (metric) => SizedBox(width: width, child: _MetricCard(metric)),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildNetworkCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _IpInfoCard(
            info: _ipInfo,
            error: _ipInfoError,
            loading: _loadingIpInfo,
            onRefresh: () => unawaited(_loadIpInfo()),
          ),
          _NetworkLatencyCard(
            results: _latencyResults,
            loading: _testingLatencies,
            onRefresh: () => unawaited(_testNetworkLatencies()),
          ),
        ];
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          );
        }
        return Column(
          children: [cards[0], const SizedBox(height: 10), cards[1]],
        );
      },
    );
  }

  Widget _buildOverviewDetails(OpenClashOverview overview) {
    return CupertinoListSection.insetGrouped(
      margin: EdgeInsets.zero,
      header: const Text('流量统计'),
      children: [
        _DetailTile(
          label: '累计上传',
          value: _formatBytes(overview.uploadTotal.toDouble()),
        ),
        _DetailTile(
          label: '累计下载',
          value: _formatBytes(overview.downloadTotal.toDouble()),
        ),
        _DetailTile(label: '运行模式', value: overview.mode.label),
      ],
    );
  }

  Widget _buildNodes() {
    final snapshot = _proxySnapshot;
    if (snapshot == null && _proxyError != null) {
      return _OpenClashError(
        error: _proxyError!,
        onRetry: () => unawaited(_loadProxies()),
      );
    }
    if (snapshot == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return CustomScrollView(
      key: const PageStorageKey('metacubexd-nodes'),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _loadProxies),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.list(
            children: [
              _buildModeControl(),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '节点选择',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${snapshot.groups.length} 个策略',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: '测试所有代理组',
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      minimumSize: const Size(0, 30),
                      onPressed: _testingAllGroups || _pendingActions.isNotEmpty
                          ? null
                          : () => unawaited(_testAllGroups()),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_testingAllGroups)
                            const CupertinoActivityIndicator(radius: 7)
                          else
                            const Icon(CupertinoIcons.speedometer, size: 17),
                          const SizedBox(width: 5),
                          Text(
                            _testingAllGroups
                                ? '$_testedGroupCount/$_totalGroupCount'
                                : '全部测速',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '搜索策略或节点',
              ),
              const SizedBox(height: 12),
              if (_loadingProxies)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: CupertinoActivityIndicator(),
                ),
              ..._buildGroupCards(snapshot),
              if (_proxyError != null) ...[
                const SizedBox(height: 12),
                _InlineError(error: _proxyError!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeControl() {
    final mode = _overview?.mode ?? OpenClashMode.rule;
    final interactionEnabled = !_testingAllGroups && !_switchingMode;
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final border = CupertinoColors.separator.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '运行模式',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (_switchingMode) const CupertinoActivityIndicator(radius: 8),
            ],
          ),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: !interactionEnabled,
            child: Opacity(
              opacity: interactionEnabled ? 1 : 0.45,
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<OpenClashMode>(
                  groupValue: mode,
                  children: {
                    for (final value in OpenClashMode.values)
                      value: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(value.label),
                      ),
                  },
                  onValueChanged: (value) {
                    if (value != null) unawaited(_switchMode(value));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupCards(OpenClashProxySnapshot snapshot) {
    final query = _searchController.text.trim().toLowerCase();
    final groups = snapshot.groups
        .where((group) {
          if (query.isEmpty || group.name.toLowerCase().contains(query)) {
            return true;
          }
          return group.members.any(
            (name) => name.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
    int priority(OpenClashProxyGroup group) {
      if (group.name.contains('节点选择')) return 0;
      if (group.name.contains('自动选择')) return 1;
      return 2;
    }

    groups.sort((a, b) {
      final byPriority = priority(a).compareTo(priority(b));
      return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
    });
    if (groups.isEmpty) {
      return [const _EmptyResults()];
    }
    return groups
        .map(
          (group) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ProxyGroupCard(
              group: group,
              nodes: snapshot.nodes,
              expanded: _expandedGroups.contains(group.name),
              pendingSelection:
                  _testingAllGroups ||
                  _pendingActions.contains('select:${group.name}'),
              pendingDelay:
                  _testingAllGroups ||
                  _pendingActions.contains('delay:group::${group.name}'),
              query: group.name.toLowerCase().contains(query) ? '' : query,
              onToggle: () => setState(() {
                if (!_expandedGroups.add(group.name)) {
                  _expandedGroups.remove(group.name);
                }
              }),
              onSelect: (proxy) => unawaited(_selectProxy(group.name, proxy)),
              onTestGroup: () =>
                  unawaited(_testDelay(kind: 'group', name: group.name)),
              onTestNode: (node) =>
                  unawaited(_testDelay(kind: 'node', name: node)),
              pendingActions: _pendingActions,
            ),
          ),
        )
        .toList(growable: false);
  }
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;

  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricData metric;

  const _MetricCard(this.metric);

  @override
  Widget build(BuildContext context) {
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final border = CupertinoColors.separator.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, size: 20, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    metric.value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IpInfoCard extends StatelessWidget {
  final OpenClashIpInfo? info;
  final Object? error;
  final bool loading;
  final VoidCallback onRefresh;

  const _IpInfoCard({
    required this.info,
    required this.error,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return _NetworkCardShell(
      icon: CupertinoIcons.globe,
      title: '当前 IP',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'IP.SB',
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 2),
          _CardRefreshButton(loading: loading, onPressed: onRefresh),
        ],
      ),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final current = info;
    if (current == null && loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (current == null) {
      final message = error == null ? '暂无数据' : error.toString();
      return Center(
        child: Text(
          message,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: 13,
          ),
        ),
      );
    }
    return Column(
      children: [
        _IpInfoRow(label: 'IP 地址', value: current.ip, emphasized: true),
        if (current.country.isNotEmpty)
          _IpInfoRow(label: '国家', value: current.country),
        if (current.city.isNotEmpty)
          _IpInfoRow(label: '城市', value: current.city),
        if (current.organization.isNotEmpty)
          _IpInfoRow(label: '组织', value: current.organization),
        if (current.asn.isNotEmpty)
          _IpInfoRow(label: 'ASN', value: 'AS${current.asn}'),
      ],
    );
  }
}

class _NetworkLatencyCard extends StatelessWidget {
  final List<OpenClashLatencyResult> results;
  final bool loading;
  final VoidCallback onRefresh;

  const _NetworkLatencyCard({
    required this.results,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final successful = results
        .map((result) => result.delay)
        .whereType<int>()
        .toList(growable: false);
    final average = successful.isEmpty
        ? null
        : (successful.reduce((left, right) => left + right) / successful.length)
              .round();
    return _NetworkCardShell(
      icon: CupertinoIcons.waveform_path_ecg,
      title: '网络延迟',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (average != null)
            Text(
              '平均 ${average}ms',
              style: TextStyle(
                color: _latencyColor(context, average),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 2),
          _CardRefreshButton(loading: loading, onPressed: onRefresh),
        ],
      ),
      child: results.isEmpty
          ? Center(
              child: loading
                  ? const CupertinoActivityIndicator()
                  : Text(
                      '暂无数据',
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                        fontSize: 13,
                      ),
                    ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final result in results) _LatencyResultRow(result: result),
              ],
            ),
    );
  }
}

class _NetworkCardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget trailing;
  final Widget child;

  const _NetworkCardShell({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return Container(
      height: 210,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: separator.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              trailing,
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CardRefreshButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _CardRefreshButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(6),
      minimumSize: const Size(30, 30),
      onPressed: loading ? null : onPressed,
      child: loading
          ? const CupertinoActivityIndicator(radius: 7)
          : const Icon(CupertinoIcons.refresh, size: 16),
    );
  }
}

class _IpInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _IpInfoRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: emphasized ? 13 : 12,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                color: emphasized
                    ? CupertinoColors.activeBlue.resolveFrom(context)
                    : CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatencyResultRow extends StatelessWidget {
  final OpenClashLatencyResult result;

  const _LatencyResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final delay = result.delay;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final color = _latencyColor(context, delay);
    final widthFactor = delay == null ? 0.0 : math.min(delay / 500, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              result.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 6,
                color: secondary.withValues(alpha: 0.12),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widthFactor,
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              delay == null ? '超时' : '${delay}ms',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: delay == null ? secondary : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _latencyColor(BuildContext context, int? delay) {
  if (delay == null) return CupertinoColors.systemGrey.resolveFrom(context);
  if (delay < 100) return CupertinoColors.systemGreen.resolveFrom(context);
  if (delay < 300) return CupertinoColors.systemOrange.resolveFrom(context);
  return CupertinoColors.systemRed.resolveFrom(context);
}

Color _proxyLatencyColor(BuildContext context, int? delay) {
  if (delay == null || delay == 0) {
    return CupertinoColors.systemGrey.resolveFrom(context);
  }
  if (delay <= 800) return CupertinoColors.systemGreen.resolveFrom(context);
  if (delay <= 1500) return CupertinoColors.systemYellow.resolveFrom(context);
  return CupertinoColors.systemRed.resolveFrom(context);
}

Color _healthScoreColor(BuildContext context, int score) {
  if (score >= 80) return CupertinoColors.systemGreen.resolveFrom(context);
  if (score >= 50) return CupertinoColors.systemYellow.resolveFrom(context);
  return CupertinoColors.systemRed.resolveFrom(context);
}

String _formatTimeSince(DateTime timestamp) {
  final difference = DateTime.now().toUtc().difference(timestamp.toUtc());
  final seconds = math.max(0, difference.inSeconds).toInt();
  if (seconds < 60) return '${seconds}s ago';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  if (seconds < 86400) return '${seconds ~/ 3600}h ago';
  return '${seconds ~/ 86400}d ago';
}

class _TrafficChart extends StatelessWidget {
  final List<double> upload;
  final List<double> download;

  const _TrafficChart({required this.upload, required this.download});

  LineChartBarData _series(List<double> values, Color color) {
    return LineChartBarData(
      spots: values.isEmpty
          ? const [FlSpot(0, 0)]
          : values.indexed
                .map((entry) => FlSpot(entry.$1.toDouble(), entry.$2))
                .toList(growable: false),
      isCurved: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final border = CupertinoColors.separator.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final uploadColor = CupertinoColors.systemGreen.resolveFrom(context);
    final downloadColor = CupertinoColors.activeBlue.resolveFrom(context);
    final maxY = math.max(
      1.0,
      [...upload, ...download].fold<double>(0, math.max) * 1.2,
    );
    return Container(
      height: 238,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '实时流量',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              _ChartLegend(label: '下载', color: downloadColor),
              const SizedBox(width: 12),
              _ChartLegend(label: '上传', color: uploadColor),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: RepaintBoundary(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: secondary.withValues(alpha: 0.12),
                      strokeWidth: 1,
                    ),
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    _series(download, downloadColor),
                    _series(upload, uploadColor),
                  ],
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final String label;
  final Color color;

  const _ChartLegend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;

  const _DetailTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(label),
      additionalInfo: Text(
        value,
        textAlign: TextAlign.end,
        style: TextStyle(
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class _ProxyGroupCard extends StatelessWidget {
  final OpenClashProxyGroup group;
  final Map<String, OpenClashProxyNode> nodes;
  final bool expanded;
  final bool pendingSelection;
  final bool pendingDelay;
  final String query;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelect;
  final VoidCallback onTestGroup;
  final ValueChanged<String> onTestNode;
  final Set<String> pendingActions;

  const _ProxyGroupCard({
    required this.group,
    required this.nodes,
    required this.expanded,
    required this.pendingSelection,
    required this.pendingDelay,
    required this.query,
    required this.onToggle,
    required this.onSelect,
    required this.onTestGroup,
    required this.onTestNode,
    required this.pendingActions,
  });

  @override
  Widget build(BuildContext context) {
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final members = query.isEmpty
        ? group.members
        : group.members
              .where((name) => name.toLowerCase().contains(query))
              .toList(growable: false);
    final alive = group.members
        .where((name) => nodes[name]?.alive == true)
        .length;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: separator.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          _ProxyGroupHeader(
            group: group,
            nodes: nodes,
            alive: alive,
            expanded: expanded,
            busy: pendingSelection || pendingDelay,
            onToggle: onToggle,
            onTest: onTestGroup,
          ),
          if (expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGroupedBackground
                    .resolveFrom(context)
                    .withValues(alpha: 0.55),
                border: Border(
                  top: BorderSide(color: separator.withValues(alpha: 0.28)),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 560 ? 2 : 1;
                  const gap = 8.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final name in members)
                        SizedBox(
                          width: width,
                          child: _ProxyNodeTile(
                            name: name,
                            node: nodes[name],
                            selected: name == group.current,
                            busy:
                                pendingDelay ||
                                pendingActions.contains('delay:node::$name'),
                            onTap: pendingSelection || name == group.current
                                ? null
                                : () => onSelect(name),
                            onTest: () => onTestNode(name),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ProxyGroupHeader extends StatelessWidget {
  final OpenClashProxyGroup group;
  final Map<String, OpenClashProxyNode> nodes;
  final int alive;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onTest;

  const _ProxyGroupHeader({
    required this.group,
    required this.nodes,
    required this.alive,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
            onPressed: onToggle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: label,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(
                          context,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$alive/${group.members.length}',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Icon(
                      expanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 15,
                      color: secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        size: 14,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          group.current,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: label,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                _LatencyDistribution(nodeNames: group.members, nodes: nodes),
              ],
            ),
          ),
        ),
        Semantics(
          button: true,
          label: '测试 ${group.name} 延迟',
          child: CupertinoButton(
            padding: const EdgeInsets.fromLTRB(8, 13, 14, 10),
            onPressed: busy ? null : onTest,
            child: busy
                ? const CupertinoActivityIndicator(radius: 8)
                : const Icon(CupertinoIcons.speedometer, size: 20),
          ),
        ),
      ],
    );
  }
}

class _LatencyDistribution extends StatelessWidget {
  final List<String> nodeNames;
  final Map<String, OpenClashProxyNode> nodes;

  const _LatencyDistribution({required this.nodeNames, required this.nodes});

  @override
  Widget build(BuildContext context) {
    var fast = 0;
    var medium = 0;
    var slow = 0;
    var unavailable = 0;
    for (final name in nodeNames) {
      final node = nodes[name];
      final delay = node?.delay;
      if (node?.alive != true || delay == null) {
        unavailable++;
      } else if (delay <= 800) {
        fast++;
      } else if (delay <= 1500) {
        medium++;
      } else {
        slow++;
      }
    }
    final segments = <(int, Color)>[
      if (fast > 0) (fast, CupertinoColors.systemGreen.resolveFrom(context)),
      if (medium > 0)
        (medium, CupertinoColors.systemYellow.resolveFrom(context)),
      if (slow > 0) (slow, CupertinoColors.systemRed.resolveFrom(context)),
      if (unavailable > 0)
        (unavailable, CupertinoColors.systemGrey.resolveFrom(context)),
    ];
    if (segments.isEmpty) {
      segments.add((1, CupertinoColors.systemGrey.resolveFrom(context)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                flex: segment.$1,
                child: ColoredBox(color: segment.$2),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProxyNodeTile extends StatelessWidget {
  final String name;
  final OpenClashProxyNode? node;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback onTest;

  const _ProxyNodeTile({
    required this.name,
    required this.node,
    required this.selected,
    required this.busy,
    this.onTap,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final selectedColor = CupertinoColors.activeBlue.resolveFrom(context);
    final health = OpenClashNodeHealth.fromHistory(
      node?.history ?? const <OpenClashDelayHistoryEntry>[],
    );
    final hasMetadata =
        node != null &&
        (node!.type.isNotEmpty || node!.udp || node!.xudp || node!.tfo);
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? selectedColor.withValues(alpha: 0.07)
            : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                context,
              ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected
              ? selectedColor.withValues(alpha: 0.6)
              : separator.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              onPressed: onTap,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: selected
                        ? Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            color: selectedColor,
                            size: 18,
                          )
                        : Icon(
                            CupertinoIcons.circle,
                            color: secondary,
                            size: 16,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: label,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (hasMetadata) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (node!.udp || node!.xudp) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemTeal
                                        .resolveFrom(context)
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'U',
                                    style: TextStyle(
                                      color: CupertinoColors.systemTeal
                                          .resolveFrom(context),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  [
                                    if (node!.xudp) 'XUDP',
                                    if (node!.udp) 'UDP',
                                    if (node!.tfo) 'TFO',
                                    if (node!.type.isNotEmpty) node!.type,
                                  ].join(' / '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: secondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (health != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${health.score}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _healthScoreColor(
                                    context,
                                    health.score,
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (health.lastTestTime != null) ...[
                                const SizedBox(width: 5),
                                Text(
                                  _formatTimeSince(health.lastTestTime!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _LatencyLabel(node: node),
          Semantics(
            button: true,
            label: '测试 $name 延迟',
            child: CupertinoButton(
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
              onPressed: busy ? null : onTest,
              child: busy
                  ? const CupertinoActivityIndicator(radius: 7)
                  : const Icon(CupertinoIcons.refresh_thick, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatencyLabel extends StatelessWidget {
  final OpenClashProxyNode? node;

  const _LatencyLabel({required this.node});

  @override
  Widget build(BuildContext context) {
    final delay = node?.delay;
    final color = node?.alive == false
        ? CupertinoColors.systemRed.resolveFrom(context)
        : _proxyLatencyColor(context, delay);
    final textColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                delay == null ? '--' : '$delay ms',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (node?.history.isNotEmpty == true) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                width: 58,
                height: 3,
                child: Row(
                  children: [
                    for (final entry in node!.history)
                      Expanded(
                        child: ColoredBox(
                          color: _proxyLatencyColor(context, entry.delay),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final Object error;

  const _InlineError({required this.error});

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.systemRed.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_circle, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(error.toString())),
        ],
      ),
    );
  }
}

class _OpenClashError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _OpenClashError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: CupertinoColors.systemOrange,
              size: 38,
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

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Center(
        child: Text(
          '没有匹配的代理节点',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

String _formatBytes(double bytes) {
  if (!bytes.isFinite || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
