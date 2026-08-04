import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/luci_menu_item.dart';
import 'package:luci_mobile/services/luci_menu_service.dart';

LuciMenuItem menuItem(
  String key,
  List<String> path, {
  double order = 1,
  List<LuciMenuItem> children = const [],
}) => LuciMenuItem(
  key: key,
  title: key,
  order: order,
  pathSegments: path,
  children: children,
);

void main() {
  test('adds MetaCubeXD immediately after an existing OpenClash entry', () {
    final services = menuItem(
      'services',
      const ['admin', 'services'],
      children: [
        menuItem('appfilter', const [
          'admin',
          'services',
          'appfilter',
        ], order: 10),
        menuItem('openclash', const [
          'admin',
          'services',
          'openclash',
        ], order: 20),
        menuItem('homeassistant', const [
          'admin',
          'services',
          'homeassistant',
        ], order: 30),
      ],
    );

    final decorated = LuciMenuService.addAppEntries([services]);
    final children = decorated.single.children;

    expect(children.map((item) => item.key), [
      'appfilter',
      'openclash',
      'metacubexd',
      'homeassistant',
    ]);
    expect(children[2].title, 'MetaCubeXD');
    expect(children[2].pathSegments, [
      'admin',
      'services',
      'luci-mobile-mihomo',
    ]);
  });

  test('does not advertise MetaCubeXD without OpenClash', () {
    final services = menuItem(
      'services',
      const ['admin', 'services'],
      children: [
        menuItem('appfilter', const ['admin', 'services', 'appfilter']),
      ],
    );

    expect(
      LuciMenuService.addAppEntries([services]).single.children,
      hasLength(1),
    );
  });
}
