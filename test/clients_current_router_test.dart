import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/services/client_list_policy.dart';

void main() {
  test('devices page is scoped to the selected router', () {
    expect(ClientListPolicy.scope, ClientListScope.selectedRouter);
  });

  test('wireless discovery excludes station-mode uplinks', () {
    final interfaces = WirelessInterfacePolicy.apInterfaceNames({
      'radio0': {
        'interfaces': [
          {
            'ifname': 'phy0-ap0',
            'config': {'mode': 'ap'},
          },
          {
            'ifname': 'phy0-sta0',
            'config': {'mode': 'sta'},
          },
        ],
      },
      'radio1': {
        'interfaces': [
          {'ifname': 'phy1-ap0', 'config': <String, dynamic>{}},
          {
            'config': {'mode': 'ap'},
          },
        ],
      },
    });

    expect(interfaces, ['phy0-ap0', 'phy1-ap0']);
  });

  test('client cache is isolated by router', () {
    final cache = ClientListCache();
    final firstRouterClients = [
      Client.fromWirelessStation('AA:BB:CC:DD:EE:01'),
    ];
    final secondRouterClients = [
      Client.fromWirelessStation('AA:BB:CC:DD:EE:02'),
    ];

    cache.store('router-1', firstRouterClients);
    cache.store('router-2', secondRouterClients);

    expect(cache.forRouter('router-1'), firstRouterClients);
    expect(cache.forRouter('router-2'), secondRouterClients);
    expect(cache.forRouter('router-3'), isNull);
  });
}
