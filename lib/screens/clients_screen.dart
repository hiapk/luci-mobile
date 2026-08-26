import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/client_list_policy.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/luci_refresh_components.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _searchQuery = '';
  final SecureStorageService _secureStorage = SecureStorageService();
  Map<String, String> _clientAliases = {};
  // Track expansion by client identity (MAC/IP), not list index - indices
  // shift when the search filter or the underlying data reorders the list.
  final Set<String> _expandedClientKeys = {};
  late TextEditingController _searchController;
  Future<List<Client>>? _clientsFuture;
  String? _lastSelectedRouterId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
    final initState = ref.read(appStateProvider);
    _lastSelectedRouterId = initState.selectedRouter?.id;
    _computeClientsFuture();
    unawaited(_loadClientAliases());
  }

  Future<void> _loadClientAliases() async {
    final aliases = await _secureStorage.getClientAliases();
    if (!mounted) return;
    setState(() => _clientAliases = aliases);
  }

  String? _clientAlias(Client client) =>
      _clientAliases[SecureStorageService.normalizeClientMac(
        client.macAddress,
      )];

  String _clientDisplayName(Client client) =>
      _clientAlias(client) ?? client.hostname;

  bool _canEditAlias(Client client) {
    final mac = SecureStorageService.normalizeClientMac(client.macAddress);
    return mac.isNotEmpty && mac != 'N/A';
  }

  Future<void> _editClientAlias(Client client) async {
    final currentAlias = _clientAlias(client);
    final controller = TextEditingController(text: currentAlias ?? '');
    final alias = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设备别名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: '本地别名',
            hintText: client.hostname,
            helperText: '仅保存在当前手机',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          if (currentAlias != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('删除别名'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alias == null) return;

    try {
      await _secureStorage.setClientAlias(
        macAddress: client.macAddress,
        alias: alias,
      );
      if (!mounted) return;
      final mac = SecureStorageService.normalizeClientMac(client.macAddress);
      final normalizedAlias = alias.trim();
      setState(() {
        if (normalizedAlias.isEmpty) {
          _clientAliases.remove(mac);
        } else {
          _clientAliases[mac] = normalizedAlias;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存别名失败：$error')));
    }
  }

  void _computeClientsFuture() {
    final appState = ref.read(appStateProvider);
    _clientsFuture = switch (ClientListPolicy.scope) {
      ClientListScope.selectedRouter =>
        appState.fetchClientsForSelectedRouter(),
    };
  }

  Future<void> _disconnectClient(Client client) async {
    final displayName = _clientDisplayName(client);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('断开无线设备'),
        content: Text('确定断开 $displayName 吗？设备将在 1 分钟内无法重新连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(appStateProvider)
          .disconnectWirelessClient(client.macAddress, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已断开 $displayName')));
      setState(_computeClientsFuture);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final watchedAppState = ref.watch(appStateProvider);
    // Recompute future only when selected router changes
    Future<List<Client>>? future = _clientsFuture;
    final currentId = watchedAppState.selectedRouter?.id;
    if (currentId != _lastSelectedRouterId) {
      _lastSelectedRouterId = currentId;
      _computeClientsFuture();
      future = _clientsFuture;
    }
    return FutureBuilder<List<Client>>(
      key: ValueKey(currentId),
      future: future,
      initialData: watchedAppState.cachedClientsForSelectedRouter,
      builder: (context, snapshot) {
        final loadedClients = snapshot.data ?? [];
        return Scaffold(
          appBar: const LuciAppBar(title: '设备'),
          body: Stack(
            children: [
              LuciPullToRefresh(
                onRefresh: () async {
                  // Trigger a refresh by re-fetching dashboard data for selected router
                  await ref.read(appStateProvider).fetchDashboardData();
                  setState(() {
                    _computeClientsFuture();
                  });
                },
                child: Builder(
                  builder: (context) {
                    final appState = ref.watch(appStateProvider);
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting &&
                        loadedClients.isEmpty;
                    final dashboardError = appState.dashboardError;

                    if (isLoading) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: LuciSpacing.md,
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: LuciSpacing.md),
                            // Search bar skeleton
                            LuciSkeleton(
                              width: double.infinity,
                              height: 56,
                              borderRadius: BorderRadius.circular(
                                LuciSpacing.sm,
                              ),
                            ),
                            SizedBox(height: LuciSpacing.md),
                            // Client list skeletons
                            Expanded(
                              child: ListView.separated(
                                itemCount: 6,
                                separatorBuilder: (context, index) =>
                                    SizedBox(height: LuciSpacing.sm),
                                itemBuilder: (context, index) =>
                                    LuciListItemSkeleton(
                                      showLeading: true,
                                      showTrailing: true,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (dashboardError != null && loadedClients.isEmpty) {
                      return LuciErrorDisplay(
                        title: '设备加载失败',
                        message: '无法连接路由器，请检查网络连接和路由器 IP 地址。',
                        actionLabel: '重试',
                        onAction: () =>
                            ref.read(appStateProvider).fetchDashboardData(),
                        icon: Icons.wifi_off_rounded,
                      );
                    }

                    final clients = loadedClients;

                    final filteredClients = clients.where((client) {
                      final query = _searchQuery.toLowerCase();
                      return (_clientAlias(
                                client,
                              )?.toLowerCase().contains(query) ??
                              false) ||
                          client.hostname.toLowerCase().contains(query) ||
                          client.ipAddress.toLowerCase().contains(query) ||
                          client.macAddress.toLowerCase().contains(query) ||
                          (client.vendor != null &&
                              client.vendor!.toLowerCase().contains(query)) ||
                          (client.dnsName != null &&
                              client.dnsName!.toLowerCase().contains(query));
                    }).toList();

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: TextField(
                            autofocus: false,
                            onChanged: (value) {
                              // No need to setState here, listener handles it
                            },
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: '按名称、IP、MAC 或厂商搜索…',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _searchController.clear();
                                        });
                                      },
                                      tooltip: '清除搜索',
                                    )
                                  : null,
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24.0),
                                borderSide: BorderSide.none,
                              ),
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: filteredClients.isEmpty
                              ? LuciEmptyState(
                                  title: _searchQuery.isEmpty
                                      ? '没有在线设备'
                                      : '没有匹配的设备',
                                  message: _searchQuery.isEmpty
                                      ? '当前没有设备连接到路由器，请下拉刷新。'
                                      : '没有设备符合搜索条件，请尝试其他关键词。',
                                  icon: Icons.people_outline,
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  separatorBuilder: (context, idx) =>
                                      const SizedBox(height: 4),
                                  itemCount: filteredClients.length,
                                  itemBuilder: (context, index) {
                                    final client = filteredClients[index];
                                    final clientKey =
                                        '${client.macAddress}|${client.ipAddress}';
                                    final isExpanded = _expandedClientKeys
                                        .contains(clientKey);

                                    return LuciSlideTransition(
                                      direction: LuciSlideDirection.up,
                                      delay: Duration(milliseconds: index * 50),
                                      distance: 30,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                          vertical: 8.0,
                                        ),
                                        child: _UnifiedClientCard(
                                          client: client,
                                          alias: _clientAlias(client),
                                          isExpanded: isExpanded,
                                          onEditAlias: _canEditAlias(client)
                                              ? () => _editClientAlias(client)
                                              : null,
                                          onDisconnect:
                                              client.connectionType ==
                                                  ConnectionType.wireless
                                              ? () => _disconnectClient(client)
                                              : null,
                                          onTap: () {
                                            setState(() {
                                              if (isExpanded) {
                                                _expandedClientKeys.remove(
                                                  clientKey,
                                                );
                                              } else {
                                                _expandedClientKeys.add(
                                                  clientKey,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                  },
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
      },
    );
  }

  String normalizeMac(String mac) => mac.toUpperCase().replaceAll('-', ':');
}

class _UnifiedClientCard extends StatefulWidget {
  final Client client;
  final String? alias;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onEditAlias;
  final Future<void> Function()? onDisconnect;

  const _UnifiedClientCard({
    required this.client,
    required this.alias,
    required this.isExpanded,
    required this.onTap,
    this.onEditAlias,
    this.onDisconnect,
  });

  @override
  State<_UnifiedClientCard> createState() => _UnifiedClientCardState();
}

class _UnifiedClientCardState extends State<_UnifiedClientCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _disconnecting = false;

  String get _displayName => widget.alias ?? widget.client.hostname;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    if (widget.isExpanded) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_UnifiedClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: widget.isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedScale(
        scale: widget.isExpanded ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: Column(
          children: [
            InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(18.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.13,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedScale(
                            scale: widget.isExpanded ? 1.1 : 1.0,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.elasticOut,
                            child: Icon(
                              Icons.person_outline,
                              color: colorScheme.primary,
                              size: 22,
                              semanticLabel: '设备图标',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tooltip(
                            message:
                                widget.client.connectionType ==
                                    ConnectionType.unknown
                                ? '未知连接类型'
                                : '设备在线',
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: widget.client.isOnline == false
                                    ? Colors.grey
                                    : widget.client.isOnline == true
                                    ? Colors.green
                                    : Colors.amber,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.surface,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: LuciTextStyles.cardTitle(context),
                            semanticsLabel: '设备名称：$_displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: LuciSpacing.xs),
                          Container(
                            margin: const EdgeInsets.only(right: 32),
                            child: Divider(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.10),
                              thickness: 1,
                              height: 8,
                            ),
                          ),
                          Text(
                            _buildMinimalClientSubtitle(widget.client),
                            style: LuciTextStyles.cardSubtitle(context),
                            semanticsLabel:
                                '设备详情：${_buildMinimalClientSubtitle(widget.client)}',
                          ),
                          if (widget.client.vendor != null &&
                              widget.client.vendor!.isNotEmpty)
                            Text(
                              widget.client.vendor!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              semanticsLabel: '厂商：${widget.client.vendor}',
                            ),
                        ],
                      ),
                    ),
                    _buildConnectionTypeChip(context, widget.client),
                    const SizedBox(width: 8),
                    Icon(
                      widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 26,
                      semanticLabel: widget.isExpanded ? '收起详情' : '展开详情',
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildClientDetails(context, widget.client),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionTypeChip(BuildContext context, Client client) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _connectionLabel(context, client);
    IconData icon;
    Color bgColor;
    Color fgColor;

    if (client.isOnline == false) {
      icon = Icons.cloud_off_outlined;
      bgColor = colorScheme.surfaceContainerHighest;
      fgColor = colorScheme.onSurfaceVariant;
    } else if (client.wifiBand != null ||
        client.connectionType == ConnectionType.wireless) {
      icon = Icons.wifi;
      bgColor = colorScheme.primaryContainer;
      fgColor = colorScheme.onPrimaryContainer;
    } else if (client.connectionType == ConnectionType.wired) {
      icon = Icons.settings_ethernet;
      bgColor = colorScheme.secondaryContainer;
      fgColor = colorScheme.onSecondaryContainer;
    } else {
      icon = Icons.devices_other_outlined;
      bgColor = colorScheme.surfaceContainerHighest;
      fgColor = colorScheme.onSurfaceVariant;
    }

    return Chip(
      label: Text(label),
      avatar: Icon(icon, size: 16, color: fgColor),
      backgroundColor: bgColor,
      labelStyle: theme.textTheme.labelSmall?.copyWith(color: fgColor),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildClientDetails(BuildContext context, Client client) {
    final theme = Theme.of(context);

    Widget detailRow(
      String title,
      String value, {
      Color? valueColor,
      VoidCallback? onTap,
      String? semanticsLabel,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: LuciTextStyles.detailLabel(context),
                semanticsLabel: title,
              ),
              Row(
                children: [
                  Text(
                    value,
                    style: valueColor != null
                        ? LuciTextStyles.detailValue(
                            context,
                          ).copyWith(color: valueColor)
                        : LuciTextStyles.detailValue(context),
                    semanticsLabel: semanticsLabel ?? value,
                  ),
                  if (onTap != null)
                    GestureDetector(
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Icon(
                          Icons.copy_all_outlined,
                          size: 16,
                          semanticLabel: '复制',
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

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Column(
        children: [
          if (widget.onEditAlias != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              dense: true,
              title: const Text('本地别名'),
              subtitle: Text(widget.alias ?? '未设置'),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: widget.onEditAlias,
            ),
          if (widget.alias != null)
            detailRow(
              '原始名称',
              client.hostname,
              semanticsLabel: '原始名称：${client.hostname}',
            ),
          detailRow(
            'IP 地址',
            client.ipAddress,
            onTap: () => _copyToClipboard(context, client.ipAddress, 'IP 地址'),
            semanticsLabel: 'IP 地址：${client.ipAddress}',
          ),
          if (client.ipv6Addresses != null && client.ipv6Addresses!.isNotEmpty)
            ...client.ipv6Addresses!.map(
              (ipv6) => detailRow(
                'IPv6 地址',
                ipv6,
                onTap: () => _copyToClipboard(context, ipv6, 'IPv6 地址'),
                semanticsLabel: 'IPv6 地址：$ipv6',
              ),
            ),
          detailRow(
            'MAC 地址',
            client.macAddress,
            onTap: () => _copyToClipboard(context, client.macAddress, 'MAC 地址'),
            semanticsLabel: 'MAC 地址：${client.macAddress}',
          ),
          if (client.vendor != null && client.vendor!.isNotEmpty)
            detailRow(
              '厂商',
              client.vendor!,
              semanticsLabel: '厂商：${client.vendor}',
            ),
          if (client.dnsName != null && client.dnsName!.isNotEmpty)
            detailRow(
              'DNS 名称',
              client.dnsName!,
              semanticsLabel: 'DNS 名称：${client.dnsName}',
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          detailRow(
            '剩余租期',
            client.formattedLeaseTime,
            valueColor: client.formattedLeaseTime == 'Expired'
                ? theme.colorScheme.error
                : null,
            semanticsLabel: context.l10n.detailSemantics(
              context.l10n.leaseTimeRemaining,
              _leaseTime(context, client),
            ),
          ),
          if (widget.onDisconnect != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _disconnecting ? null : _disconnectClient,
                  icon: _disconnecting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_off_rounded),
                  label: const Text('断开无线设备（1 分钟）'),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _disconnectClient() async {
    final disconnect = widget.onDisconnect;
    if (disconnect == null || _disconnecting) return;
    setState(() => _disconnecting = true);
    try {
      await disconnect();
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  String _buildMinimalClientSubtitle(Client client) {
    final v4 = client.ipAddress;
    final v6s = client.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != 'N/A') {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return '';
    if (extra > 0) {
      return '$shown  +$extra';
    } else {
      return shown;
    }
  }

  String _connectionLabel(BuildContext context, Client client) {
    if (client.isOnline == false) return context.l10n.offline;
    if (client.wifiBand != null) return client.connectionLabel;
    return switch (client.connectionType) {
      ConnectionType.wireless => context.l10n.wifi,
      ConnectionType.wired => context.l10n.ethernet,
      ConnectionType.unknown => context.l10n.unknown,
    };
  }

  String _leaseTime(BuildContext context, Client client) {
    final seconds = client.leaseTime;
    if (seconds == null || seconds == 0) return context.l10n.unlimited;
    if (seconds < 0) return context.l10n.expired;
    return Client.formatDuration(seconds);
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
