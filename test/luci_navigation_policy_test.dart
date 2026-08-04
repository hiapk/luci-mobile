import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/services/luci_navigation_policy.dart';

LuciMenuItem item(
  String key,
  List<String> path, {
  List<LuciMenuItem> children = const [],
}) => LuciMenuItem(
  key: key,
  title: key,
  order: 1,
  pathSegments: path,
  children: children,
);

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

    test('routes extended LuCI and iStoreOS pages to native screens', () {
      final expected = <List<String>, LuciNativeDestination>{
        const ['admin', 'network', 'switch']:
            LuciNativeDestination.switchConfiguration,
        const ['admin', 'system', 'package-manager']:
            LuciNativeDestination.packageManager,
        const ['admin', 'system', 'diskman']:
            LuciNativeDestination.storageManagement,
        const ['admin', 'nas']: LuciNativeDestination.storageManagement,
        const ['admin', 'nas', 'mergerfs']:
            LuciNativeDestination.storageManagement,
        const ['admin', 'nas', 'cifs']: LuciNativeDestination.storageManagement,
        const ['admin', 'nas', 'nfs']: LuciNativeDestination.storageManagement,
      };

      for (final entry in expected.entries) {
        final menuItem = item(entry.key.last, entry.key);
        expect(
          LuciNavigationPolicy.presentationFor(menuItem),
          LuciPagePresentation.nativePage,
          reason: entry.key.join('/'),
        );
        expect(
          LuciNavigationPolicy.nativeDestinationFor(menuItem),
          entry.value,
          reason: entry.key.join('/'),
        );
      }
    });

    test('uses WebView only for native pages rejected by router ACLs', () {
      for (final path in [
        const ['admin', 'docker'],
        const ['admin', 'docker', 'containers'],
        const ['admin', 'system', 'ota'],
        const ['admin', 'system', 'tuning'],
        const ['admin', 'system', 'tuning', 'ipk'],
      ]) {
        expect(
          LuciNavigationPolicy.presentationFor(item(path.last, path)),
          LuciPagePresentation.webView,
          reason: path.join('/'),
        );
      }
    });

    test('hides unavailable LuCI child pages', () {
      final visible = LuciNavigationPolicy.filterVisibleChildren([
        item('network', const ['admin', 'network', 'network']),
        item('interfaceconfig', const ['admin', 'network', 'interfaceconfig']),
        item('luci-fan', const ['admin', 'system', 'luci-fan']),
      ]);

      expect(visible.map((entry) => entry.key), ['network']);
    });

    test('keeps complex applications in the authenticated WebView', () {
      for (final path in [
        const ['admin', 'store'],
        const ['admin', 'services', 'linkease'],
      ]) {
        expect(
          LuciNavigationPolicy.presentationFor(item(path.last, path)),
          LuciPagePresentation.webView,
          reason: path.join('/'),
        );
      }
    });

    test('keeps OpenClash in WebView and routes MetaCubeXD natively', () {
      final openClash = item('openclash', const [
        'admin',
        'services',
        'openclash',
      ]);
      final metaCubeXd = item('metacubexd', const [
        'admin',
        'services',
        'luci-mobile-mihomo',
      ]);

      expect(
        LuciNavigationPolicy.presentationFor(openClash),
        LuciPagePresentation.webView,
      );
      expect(LuciNavigationPolicy.nativeDestinationFor(openClash), isNull);
      expect(
        LuciNavigationPolicy.presentationFor(metaCubeXd),
        LuciPagePresentation.nativePage,
      );
      expect(
        LuciNavigationPolicy.nativeDestinationFor(metaCubeXd),
        LuciNativeDestination.metaCubeXd,
      );
    });

    test('opens iStore directly instead of exposing its status API', () {
      final store = item(
        'store',
        const ['admin', 'store'],
        children: [
          item('status', const ['admin', 'store', 'status']),
        ],
      );
      final services = item(
        'services',
        const ['admin', 'services'],
        children: [
          item('openclash', const ['admin', 'services', 'openclash']),
        ],
      );

      expect(LuciNavigationPolicy.shouldOpenItemDirectly(store), isTrue);
      expect(LuciNavigationPolicy.shouldOpenItemDirectly(services), isFalse);
    });
  });
}
