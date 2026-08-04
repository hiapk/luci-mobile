import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/services/luci_navigation_policy.dart';

LuciMenuItem item(String key, List<String> path) =>
    LuciMenuItem(key: key, title: key, order: 1, pathSegments: path);

void main() {
  group('LuCI navigation policy', () {
    test('hides QuickStart, network guide and VPN roots', () {
      final visible = LuciNavigationPolicy.filterVisibleRoots([
        item('quickstart', const ['admin', 'quickstart']),
        item('status', const ['admin', 'status']),
        item('network_guide', const ['admin', 'network_guide']),
        item('vpn', const ['admin', 'vpn']),
      ]);

      expect(visible.map((entry) => entry.key), ['status']);
    });

    test('routes overview and interfaces through the main tab bar', () {
      final overview = item('overview', const ['admin', 'status', 'overview']);
      final interfaces = item('network', const ['admin', 'network', 'network']);

      expect(
        LuciNavigationPolicy.presentationFor(overview),
        LuciPagePresentation.mainTab,
      );
      expect(LuciNavigationPolicy.mainTabIndexFor(overview), 0);
      expect(
        LuciNavigationPolicy.presentationFor(interfaces),
        LuciPagePresentation.mainTab,
      );
      expect(LuciNavigationPolicy.mainTabIndexFor(interfaces), 2);
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
    });

    test('routes standard OpenWrt pages to native Flutter screens', () {
      const paths = <List<String>>[
        ['admin', 'status', 'nftables'],
        ['admin', 'status', 'channel_analysis'],
        ['admin', 'status', 'wireguard'],
        ['admin', 'network', 'wireless'],
        ['admin', 'network', 'routes'],
        ['admin', 'network', 'dhcp'],
        ['admin', 'network', 'firewall'],
        ['admin', 'system', 'system'],
        ['admin', 'system', 'admin'],
        ['admin', 'system', 'crontab'],
        ['admin', 'system', 'mounts'],
        ['admin', 'system', 'leds'],
        ['admin', 'services', 'ddns'],
      ];

      for (final path in paths) {
        expect(
          LuciNavigationPolicy.presentationFor(item(path.last, path)),
          LuciPagePresentation.nativePage,
          reason: path.join('/'),
        );
      }
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
