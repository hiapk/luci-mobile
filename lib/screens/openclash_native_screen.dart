import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import 'package:luci_mobile/widgets/native_navigation_bar.dart';

enum _OpenClashPage { overview, proxies }

enum _ProxySection { groups, providers }

class OpenClashNativeScreen extends ConsumerStatefulWidget {
  const OpenClashNativeScreen({super.key});

  @override
  ConsumerState<OpenClashNativeScreen> createState() =>
      _OpenClashNativeScreenState();
}

class _OpenClashNativeScreenState extends ConsumerState<OpenClashNativeScreen> {
  static const _pollInterval = Duration(seconds: 2);
  static const _historyLimit = 36;

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedProviders = {};
  final Set<String> _pendingActions = {};

  Timer? _pollTimer;
  _OpenClashPage _page = _OpenClashPage.overview;
  _ProxySection _proxySection = _ProxySection.groups;
  OpenClashOverview? _overview;
  OpenClashProxySnapshot? _proxySnapshot;
  Object? _overviewError;
  Object? _proxyError;
  bool _loadingOverview = false;
  bool _loadingProxies = false;
  bool _switchingMode = false;
  double _uploadRate = 0;
  double _downloadRate = 0;
  final List<double> _uploadHistory = [];
  final List<double> _downloadHistory = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_searchChanged);
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
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialLoad() async {
    await _loadOverview();
  }

  Future<void> _refreshCurrentPage() {
    return _page == _OpenClashPage.overview ? _loadOverview() : _loadProxies();
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
    if (_switchingMode || mode == _overview?.mode) return;
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
    if (_pendingActions.contains(key)) return;
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
    if (_pendingActions.contains(key)) return;
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
    return CupertinoPageScaffold(
      backgroundColor: background,
      navigationBar: NativeNavigationBar(
        context: context,
        middle: const Text('OpenClash'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _loadingOverview || _loadingProxies
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
                child: CupertinoSlidingSegmentedControl<_OpenClashPage>(
                  groupValue: _page,
                  children: const {
                    _OpenClashPage.overview: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('概览'),
                    ),
                    _OpenClashPage.proxies: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('代理'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() => _page = value);
                    if (value == _OpenClashPage.proxies &&
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
                children: [_buildOverview(), _buildProxies()],
              ),
            ),
          ],
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
        CupertinoSliverRefreshControl(onRefresh: _loadOverview),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.list(
            children: [
              _buildStatusHeader(overview),
              const SizedBox(height: 14),
              _buildMetricGrid(overview),
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
          Text(overview.running ? '运行中' : '已停止'),
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
        color: CupertinoColors.systemGreen,
      ),
      _MetricData(
        label: '下载',
        value: '${_formatBytes(_downloadRate)}/s',
        icon: CupertinoIcons.arrow_down_left,
        color: CupertinoColors.activeBlue,
      ),
      _MetricData(
        label: '活跃连接',
        value: '${overview.connectionCount}',
        icon: CupertinoIcons.link,
        color: CupertinoColors.systemOrange,
      ),
      _MetricData(
        label: '内存',
        value: _formatBytes(overview.memoryBytes.toDouble()),
        icon: CupertinoIcons.layers_fill,
        color: CupertinoColors.systemPurple,
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

  Widget _buildProxies() {
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
      key: const PageStorageKey('openclash-proxies'),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _loadProxies),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.list(
            children: [
              _buildModeControl(),
              const SizedBox(height: 12),
              CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '搜索节点或代理组',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<_ProxySection>(
                  groupValue: _proxySection,
                  children: {
                    _ProxySection.groups: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('代理组 ${snapshot.groups.length}'),
                    ),
                    _ProxySection.providers: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Provider ${snapshot.providers.length}'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => _proxySection = value);
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingProxies)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: CupertinoActivityIndicator(),
                ),
              if (_proxySection == _ProxySection.groups)
                ..._buildGroupCards(snapshot)
              else
                ..._buildProviderCards(snapshot),
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
          SizedBox(
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
                if (!_switchingMode && value != null) {
                  unawaited(_switchMode(value));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupCards(OpenClashProxySnapshot snapshot) {
    final query = _searchController.text.trim().toLowerCase();
    final groups = snapshot.groups.where((group) {
      if (query.isEmpty || group.name.toLowerCase().contains(query)) {
        return true;
      }
      return group.members.any((name) => name.toLowerCase().contains(query));
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
              pendingSelection: _pendingActions.contains(
                'select:${group.name}',
              ),
              pendingDelay: _pendingActions.contains(
                'delay:group::${group.name}',
              ),
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

  List<Widget> _buildProviderCards(OpenClashProxySnapshot snapshot) {
    final query = _searchController.text.trim().toLowerCase();
    final providers = snapshot.providers.where((provider) {
      if (query.isEmpty || provider.name.toLowerCase().contains(query)) {
        return true;
      }
      return provider.nodeNames.any(
        (name) => name.toLowerCase().contains(query),
      );
    });
    if (providers.isEmpty) return [const _EmptyResults()];
    return providers
        .map(
          (provider) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ProxyProviderCard(
              provider: provider,
              nodes: snapshot.nodes,
              expanded: _expandedProviders.contains(provider.name),
              pendingDelay: _pendingActions.contains(
                'delay:provider:${provider.name}:${provider.name}',
              ),
              query: provider.name.toLowerCase().contains(query) ? '' : query,
              onToggle: () => setState(() {
                if (!_expandedProviders.add(provider.name)) {
                  _expandedProviders.remove(provider.name);
                }
              }),
              onTestProvider: () => unawaited(
                _testDelay(
                  kind: 'provider',
                  name: provider.name,
                  provider: provider.name,
                ),
              ),
              onTestNode: (node) => unawaited(
                _testDelay(
                  kind: 'provider_node',
                  name: node,
                  provider: provider.name,
                ),
              ),
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
  final CupertinoDynamicColor color;

  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
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
    final color = metric.color.resolveFrom(context);
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
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, size: 20, color: color),
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
          _ExpandableHeader(
            title: group.name,
            subtitle: '${group.current}  ·  $alive/${group.members.length}',
            icon: CupertinoIcons.globe,
            expanded: expanded,
            busy: pendingSelection || pendingDelay,
            onToggle: onToggle,
            onTest: onTestGroup,
          ),
          if (expanded)
            for (final name in members)
              _ProxyNodeTile(
                name: name,
                node: nodes[name],
                selected: name == group.current,
                busy: pendingActions.contains('delay:node::$name'),
                onTap: pendingSelection || name == group.current
                    ? null
                    : () => onSelect(name),
                onTest: () => onTestNode(name),
              ),
        ],
      ),
    );
  }
}

class _ProxyProviderCard extends StatelessWidget {
  final OpenClashProxyProvider provider;
  final Map<String, OpenClashProxyNode> nodes;
  final bool expanded;
  final bool pendingDelay;
  final String query;
  final VoidCallback onToggle;
  final VoidCallback onTestProvider;
  final ValueChanged<String> onTestNode;
  final Set<String> pendingActions;

  const _ProxyProviderCard({
    required this.provider,
    required this.nodes,
    required this.expanded,
    required this.pendingDelay,
    required this.query,
    required this.onToggle,
    required this.onTestProvider,
    required this.onTestNode,
    required this.pendingActions,
  });

  @override
  Widget build(BuildContext context) {
    final surface = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final names = query.isEmpty
        ? provider.nodeNames
        : provider.nodeNames
              .where((name) => name.toLowerCase().contains(query))
              .toList(growable: false);
    final alive = provider.nodeNames
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
          _ExpandableHeader(
            title: provider.name,
            subtitle:
                '${provider.vehicleType}  ·  $alive/${provider.nodeNames.length}',
            icon: CupertinoIcons.cloud_download,
            expanded: expanded,
            busy: pendingDelay,
            onToggle: onToggle,
            onTest: onTestProvider,
          ),
          if (expanded)
            for (final name in names)
              _ProxyNodeTile(
                name: name,
                node: nodes[name],
                selected: false,
                busy: pendingActions.contains(
                  'delay:provider_node:${provider.name}:$name',
                ),
                onTest: () => onTestNode(name),
              ),
        ],
      ),
    );
  }
}

class _ExpandableHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onTest;

  const _ExpandableHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    return SizedBox(
      height: 70,
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: onToggle,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: blue, size: 19),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 15,
                    color: secondary,
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: '测试延迟',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onPressed: busy ? null : onTest,
              child: busy
                  ? const CupertinoActivityIndicator(radius: 8)
                  : const Icon(CupertinoIcons.speedometer, size: 20),
            ),
          ),
        ],
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
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final selectedColor = CupertinoColors.activeBlue.resolveFrom(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: selected
            ? selectedColor.withValues(alpha: 0.08)
            : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                context,
              ),
        border: Border(
          top: BorderSide(color: separator.withValues(alpha: 0.3)),
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
                            color: selected ? selectedColor : null,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (node?.type.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            node!.type,
                            style: TextStyle(fontSize: 11, color: secondary),
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
    final color = delay == null
        ? CupertinoColors.secondaryLabel.resolveFrom(context)
        : delay <= 100
        ? CupertinoColors.systemGreen.resolveFrom(context)
        : delay <= 250
        ? CupertinoColors.systemOrange.resolveFrom(context)
        : CupertinoColors.systemRed.resolveFrom(context);
    return SizedBox(
      width: 56,
      child: Text(
        delay == null ? '--' : '$delay ms',
        maxLines: 1,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
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
