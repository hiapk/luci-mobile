import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import 'package:luci_mobile/services/openclash_api_protocol.dart';

void main() {
  const session = LuciSession(
    token: '2fa-session-token',
    cookieName: 'sysauth_https',
    useHttps: true,
  );

  group('OpenClash LuCI API protocol', () {
    test('uses only the authenticated LuCI cookie for reads', () {
      final request = OpenClashApiProtocol.overview(session);

      expect(
        request.path,
        '/cgi-bin/luci/admin/services/luci-mobile-mihomo/overview',
      );
      expect(request.method, OpenClashHttpMethod.get);
      expect(request.headers['Cookie'], 'sysauth_https=2fa-session-token');
      expect(request.headers, isNot(contains('Authorization')));
      expect(request.fields, isEmpty);
    });

    test('selects a proxy through a narrowly scoped form request', () {
      final request = OpenClashApiProtocol.selectProxy(
        session,
        group: '节点选择',
        proxy: '香港 01',
      );

      expect(request.method, OpenClashHttpMethod.post);
      expect(
        request.path,
        '/cgi-bin/luci/admin/services/luci-mobile-mihomo/proxies/select',
      );
      expect(request.fields, {
        'sessionid': '2fa-session-token',
        'group': '节点选择',
        'proxy': '香港 01',
      });
      expect(request.headers.values.join(' '), isNot(contains('Bearer')));
    });

    test('allows only supported OpenClash running modes', () {
      for (final mode in OpenClashMode.values) {
        final request = OpenClashApiProtocol.switchMode(session, mode);
        expect(request.fields, {
          'sessionid': '2fa-session-token',
          'mode': mode.apiValue,
        });
      }
    });
  });
}
