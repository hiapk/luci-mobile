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
