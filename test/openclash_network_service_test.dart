import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/openclash_network_service.dart';

void main() {
  test('parses the allowlisted IP.SB response fields', () {
    final info = OpenClashIpInfo.fromIpSbJson({
      'ip': '198.51.100.7',
      'country': 'United States',
      'city': 'San Jose',
      'asn': 64500,
      'asn_organization': 'Example Network',
      'ignored': 'must not be retained',
    });

    expect(info.ip, '198.51.100.7');
    expect(info.country, 'United States');
    expect(info.city, 'San Jose');
    expect(info.asn, '64500');
    expect(info.organization, 'Example Network');
  });

  test('tests the same three device-side targets as MetaCubeXD', () async {
    final requested = <Uri>[];
    final service = OpenClashNetworkService(
      latencyProbe: (uri) async {
        requested.add(uri);
        return switch (uri.host) {
          'www.google.com' => 80,
          'cp.cloudflare.com' => 120,
          _ => null,
        };
      },
    );

    final results = await service.testLatencies();

    expect(requested.map((uri) => uri.toString()), [
      'https://www.google.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
      'https://github.com',
    ]);
    expect(results.map((result) => result.name), [
      'Google',
      'Cloudflare',
      'GitHub',
    ]);
    expect(results.map((result) => result.delay), [80, 120, null]);
  });
}
