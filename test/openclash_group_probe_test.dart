import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/openclash_group_probe.dart';

void main() {
  test('tests proxy groups sequentially while the router fans out nodes', () async {
    final firstProbe = Completer<Map<String, dynamic>>();
    final started = <String>[];
    var inFlight = 0;
    var maxInFlight = 0;

    final future = testOpenClashGroupsSequentially(
      ['节点选择', '自动选择', '国际媒体'],
      (group) async {
        started.add(group);
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        try {
          if (group == '节点选择') return await firstProbe.future;
          return <String, dynamic>{'ok': true};
        } finally {
          inFlight--;
        }
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, ['节点选择']);
    firstProbe.complete({'delays': <String, int>{'us': 672}});

    final results = await future;

    expect(started, ['节点选择', '自动选择', '国际媒体']);
    expect(maxInFlight, 1);
    expect(results.keys, ['节点选择', '自动选择', '国际媒体']);
  });
}
