import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/openclash.dart';

void main() {
  test('parses the redacted overview response', () {
    final overview = OpenClashOverview.fromJson({
      'running': true,
      'version': 'v1.19.29',
      'mode': 'rule',
      'uploadTotal': 1200,
      'downloadTotal': 9800,
      'connections': 17,
      'memoryBytes': 52428800,
      'timestamp': 1785860000,
    });

    expect(overview.running, isTrue);
    expect(overview.version, 'v1.19.29');
    expect(overview.mode, OpenClashMode.rule);
    expect(overview.uploadTotal, 1200);
    expect(overview.downloadTotal, 9800);
    expect(overview.connectionCount, 17);
    expect(overview.memoryBytes, 52428800);
  });

  test('parses groups, nodes and providers without a dashboard secret', () {
    final snapshot = OpenClashProxySnapshot.fromJson({
      'groups': [
        {
          'name': '节点选择',
          'type': 'Selector',
          'now': '香港 01',
          'all': ['香港 01', '新加坡 01'],
        },
      ],
      'nodes': [
        {'name': '香港 01', 'type': 'Trojan', 'delay': 42, 'alive': true},
        {'name': '新加坡 01', 'type': 'Vless', 'delay': 86, 'alive': true},
      ],
      'providers': [
        {
          'name': 'Airport',
          'vehicleType': 'HTTP',
          'updatedAt': '2026-08-05T12:00:00Z',
          'proxies': ['香港 01', '新加坡 01'],
        },
      ],
    });

    expect(snapshot.groups.single.current, '香港 01');
    expect(snapshot.nodes['香港 01']?.delay, 42);
    expect(snapshot.providers.single.nodeNames, ['香港 01', '新加坡 01']);
    expect(snapshot.toString(), isNot(contains('secret')));
  });

  test('preserves node capabilities and bounded latency history', () {
    final node = OpenClashProxyNode.fromJson({
      'name': 'US 01',
      'type': 'VLESS',
      'delay': 95,
      'alive': true,
      'udp': true,
      'xudp': true,
      'tfo': false,
      'history': [
        {'time': '2026-08-05T12:00:00Z', 'delay': 82},
        {'time': '2026-08-05T12:05:00Z', 'delay': 95},
      ],
    });

    expect(node.udp, isTrue);
    expect(node.xudp, isTrue);
    expect(node.tfo, isFalse);
    expect(node.history.map((entry) => entry.delay), [82, 95]);
  });

  test('treats Lua empty-table history as an empty list', () {
    final node = OpenClashProxyNode.fromJson({
      'name': 'DIRECT',
      'type': 'Direct',
      'alive': false,
      'history': <String, dynamic>{},
    });

    expect(node.history, isEmpty);
  });

  test('calculates the MetaCubeXD health score from Mihomo history', () {
    final delays = [671, 683, 531, 701, 725, 689, 505, 674, 734, 672];
    final history = [
      for (var index = 0; index < delays.length; index++)
        OpenClashDelayHistoryEntry(
          time: '2026-08-09T08:${index.toString().padLeft(2, '0')}:00Z',
          delay: delays[index],
        ),
    ];

    final health = OpenClashNodeHealth.fromHistory(history);

    expect(health, isNotNull);
    expect(health!.score, 71);
    expect(health.lastTestTime, DateTime.utc(2026, 8, 9, 8, 9));
  });

  test('treats Lua empty-table snapshot collections as empty lists', () {
    final snapshot = OpenClashProxySnapshot.fromJson({
      'groups': <String, dynamic>{},
      'nodes': <String, dynamic>{},
      'providers': <String, dynamic>{},
    });

    expect(snapshot.groups, isEmpty);
    expect(snapshot.nodes, isEmpty);
    expect(snapshot.providers, isEmpty);
  });

  test('normalizes invalid or missing numeric values', () {
    final overview = OpenClashOverview.fromJson({
      'running': false,
      'uploadTotal': -1,
      'downloadTotal': 'invalid',
      'connections': null,
    });

    expect(overview.uploadTotal, 0);
    expect(overview.downloadTotal, 0);
    expect(overview.connectionCount, 0);
    expect(overview.memoryBytes, 0);
  });
}
