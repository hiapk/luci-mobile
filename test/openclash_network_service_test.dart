import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/openclash_network_service.dart';

void main() {
  test('matches MetaCubeXD ten-second IP.SB timeout', () {
    expect(
      OpenClashNetworkService.defaultIpInfoTimeout,
      const Duration(seconds: 10),
    );
  });

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

  test('allows a response beyond the old request budget', () async {
    final service = OpenClashNetworkService(
      ipInfoClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return http.Response(
          '{"ip":"198.51.100.7","country":"United States"}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
      ipInfoTimeout: const Duration(milliseconds: 100),
    );

    final info = await service.fetchIpInfo();

    expect(info.ip, '198.51.100.7');
  });

  test('reports an IP.SB timeout instead of hiding the failure', () async {
    final service = OpenClashNetworkService(
      ipInfoClient: MockClient((_) => Completer<http.Response>().future),
      ipInfoTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      service.fetchIpInfo(),
      throwsA(
        isA<OpenClashIpInfoException>()
            .having(
              (error) => error.kind,
              'kind',
              OpenClashIpInfoErrorKind.timeout,
            )
            .having((error) => error.toString(), 'message', contains('超时')),
      ),
    );
  });

  test('reports the IP.SB HTTP status', () async {
    final service = OpenClashNetworkService(
      ipInfoClient: MockClient((_) async => http.Response('Forbidden', 403)),
    );

    await expectLater(
      service.fetchIpInfo(),
      throwsA(
        isA<OpenClashIpInfoException>()
            .having(
              (error) => error.kind,
              'kind',
              OpenClashIpInfoErrorKind.httpStatus,
            )
            .having((error) => error.toString(), 'message', contains('403')),
      ),
    );
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
