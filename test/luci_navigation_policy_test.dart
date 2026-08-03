import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/services/luci_navigation_policy.dart';

LuciMenuItem item(String key, List<String> path) => LuciMenuItem(
  key: key,
  title: key,
  order: 1,
  pathSegments: path,
);

void main() {
  group('LuCI navigation policy', () {
    test('hides network guide and VPN roots', () {
      final visible = LuciNavigationPolicy.filterVisibleRoots([
        item('status', const ['admin', 'status']),
        item('network_guide', const ['admin', 'network_guide']),
        item('vpn', const ['admin', 'vpn']),
      ]);

      expect(visible.map((entry) => entry.key), ['status']);
    });

    test('routes supported pages to native Flutter screens', () {
      expect(
        LuciNavigationPolicy.presentationFor(
          item('logs', const ['admin', 'status', 'logs']),
        ),
        LuciPagePresentation.nativePage,
      );
      expect(
        LuciNavigationPolicy.presentationFor(
          item('processes', const ['admin', 'status', 'processes']),
        ),
        LuciPagePresentation.nativePage,
      );
      expect(
        LuciNavigationPolicy.presentationFor(
          item('startup', const ['admin', 'system', 'startup']),
        ),
        LuciPagePresentation.nativePage,
      );
      expect(
        LuciNavigationPolicy.presentationFor(
          item('network', const ['admin', 'network', 'network']),
        ),
        LuciPagePresentation.nativePage,
      );
    });

    test('keeps complex applications in the authenticated WebView', () {
      for (final key in ['store', 'docker', 'openclash', 'linkease']) {
        expect(
          LuciNavigationPolicy.presentationFor(
            item(key, ['admin', 'services', key]),
          ),
          LuciPagePresentation.webView,
        );
      }
    });
  });
}
