import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

class LuciMenuService {
  final HttpClientManager _httpClientManager = HttpClientManager();

  Future<List<LuciMenuItem>> fetchMenu({
    required String host,
    required bool useHttps,
    required String cookieName,
    required String token,
    BuildContext? context,
  }) async {
    final client = _httpClientManager.getClient(
      host,
      useHttps,
      context: context,
    );
    final uri = routerUri(
      host: host,
      useHttps: useHttps,
      pathSegments: const ['cgi-bin', 'luci', 'admin', 'menu'],
    );
    final response = await client.getUri<dynamic>(
      uri,
      options: Options(
        headers: {'Cookie': '$cookieName=$token'},
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    if (response.realUri.path == '/cgi-bin/luci/' ||
        response.realUri.path == '/cgi-bin/luci') {
      throw const LuciMenuException('LuCI 会话已过期，请重新登录。');
    }

    final dynamic decoded = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    final root = _stringMap(decoded);
    final admin = _stringMap(_stringMap(root?['children'])?['admin']);
    final children = _stringMap(admin?['children']);
    if (children == null) {
      throw const LuciMenuException('路由器返回了无效的 LuCI 菜单。');
    }

    final items = <LuciMenuItem>[];
    for (final entry in children.entries) {
      if (entry.key == 'logout') continue;
      final item = _parseNode(entry.key, entry.value, const [
        'admin',
      ], includeChildren: true);
      if (item != null) items.add(item);
    }
    items.sort(_compareItems);
    return items;
  }

  LuciMenuItem? _parseNode(
    String key,
    dynamic value,
    List<String> parentPath, {
    required bool includeChildren,
  }) {
    final node = _stringMap(value);
    if (node == null || node['satisfied'] != true) return null;

    final rawTitle = node['title']?.toString().trim() ?? '';
    if (rawTitle.isEmpty) return null;

    final path = [...parentPath, key];
    final parsedChildren = <LuciMenuItem>[];
    final children = includeChildren ? _stringMap(node['children']) : null;
    if (children != null) {
      for (final entry in children.entries) {
        final child = _parseNode(
          entry.key,
          entry.value,
          path,
          includeChildren: false,
        );
        if (child != null) parsedChildren.add(child);
      }
    }
    parsedChildren.sort(_compareItems);

    return LuciMenuItem(
      key: key,
      title: _translateTitle(key, rawTitle),
      order: _orderOf(node['order']),
      pathSegments: path,
      children: parsedChildren,
    );
  }

  static Uri routerUri({
    required String host,
    required bool useHttps,
    required List<String> pathSegments,
  }) {
    return Uri.parse(
      '${useHttps ? 'https' : 'http'}://$host',
    ).replace(pathSegments: pathSegments, query: null, fragment: null);
  }

  static Map<String, dynamic>? _stringMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static double _orderOf(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 1000;
  }

  static int _compareItems(LuciMenuItem a, LuciMenuItem b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.title.compareTo(b.title);
  }

  static String _translateTitle(String key, String title) {
    const byKey = <String, String>{
      'quickstart': '首页',
      'network_guide': '网络向导',
      'status': '状态',
      'system': '系统',
      'store': 'iStore',
      'services': '服务',
      'docker': 'Docker',
      'network': '网络',
      'vpn': 'VPN',
      'overview': '概览',
      'routes': '路由表',
      'logs': '系统日志',
      'processes': '进程',
      'realtime': '实时信息',
      'wireguard': 'WireGuard',
      'admin': '管理权',
      'startup': '启动项',
      'crontab': '计划任务',
      'mounts': '挂载点',
      'leds': 'LED 配置',
      'flash': '备份与升级',
      'reboot': '重启',
      'interfaces': '接口',
      'wireless': '无线',
      'switch': '交换机',
      'dhcp': 'DHCP/DNS',
      'diagnostics': '诊断',
      'firewall': '防火墙',
      'containers': '容器',
      'images': '镜像',
      'networks': '网络',
      'volumes': '存储卷',
      'events': '事件',
    };
    const byTitle = <String, String>{
      'Status': '状态',
      'System': '系统',
      'Services': '服务',
      'Network': '网络',
      'Overview': '概览',
      'Routes': '路由表',
      'System Log': '系统日志',
      'Kernel Log': '内核日志',
      'Processes': '进程',
      'Startup': '启动项',
      'Scheduled Tasks': '计划任务',
      'Mount Points': '挂载点',
      'Backup / Flash Firmware': '备份与升级',
      'Reboot': '重启',
      'Interfaces': '接口',
      'Wireless': '无线',
      'DHCP and DNS': 'DHCP/DNS',
      'Diagnostics': '诊断',
      'Firewall': '防火墙',
    };
    return byKey[key] ?? byTitle[title] ?? title;
  }
}

class LuciMenuException implements Exception {
  final String message;

  const LuciMenuException(this.message);

  @override
  String toString() => message;
}
