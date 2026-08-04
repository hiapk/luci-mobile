import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proxy collection remains a branch for mutation endpoints', () {
    final source = File(
      'router/luci-mobile-mihomo/usr/lib/lua/luci/controller/'
      'luci_mobile_mihomo.lua',
    ).readAsStringSync();
    final collectionEntry = RegExp(
      r'entry\(\s*\{\s*"admin",\s*"services",\s*'
      r'"luci-mobile-mihomo",\s*"proxies"\s*\},\s*'
      r'call\("action_proxies"\),\s*nil\s*\)([\s\S]*?)entry\(',
    ).firstMatch(source);

    expect(collectionEntry, isNotNull);
    expect(
      collectionEntry!.group(1),
      isNot(contains('.leaf = true')),
      reason:
          'A leaf collection route consumes /proxies/select and '
          '/proxies/delay, dispatching them to the GET-only action.',
    );
    expect(
      source,
      contains(
        '{ "admin", "services", "luci-mobile-mihomo", "proxies", "select" }',
      ),
    );
    expect(
      source,
      contains(
        '{ "admin", "services", "luci-mobile-mihomo", "proxies", "delay" }',
      ),
    );
  });
}
