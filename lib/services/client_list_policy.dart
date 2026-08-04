import 'package:luci_mobile/models/client.dart';

enum ClientListScope { selectedRouter }

class ClientListPolicy {
  static const ClientListScope scope = ClientListScope.selectedRouter;
}

class WirelessInterfacePolicy {
  static List<String> apInterfaceNames(dynamic wirelessData) {
    if (wirelessData is! Map) return const [];

    final interfaces = <String>{};
    for (final radio in wirelessData.values) {
      if (radio is! Map || radio['interfaces'] is! List) continue;
      for (final interface in radio['interfaces'] as List) {
        if (interface is! Map) continue;
        final ifname = interface['ifname']?.toString().trim() ?? '';
        final config = interface['config'];
        final mode = config is Map
            ? config['mode']?.toString().toLowerCase()
            : null;
        if (ifname.isNotEmpty && mode != 'sta') interfaces.add(ifname);
      }
    }
    return interfaces.toList(growable: false);
  }
}

class ClientListCache {
  final Map<String, List<Client>> _clientsByRouter = {};

  List<Client>? forRouter(String? routerId) =>
      routerId == null ? null : _clientsByRouter[routerId];

  void store(String routerId, List<Client> clients) {
    _clientsByRouter[routerId] = List<Client>.unmodifiable(clients);
  }
}
