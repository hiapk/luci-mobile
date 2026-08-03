import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';

void main() {
  group('LuCI login protocol', () {
    test('includes a trimmed OTP only when supplied', () {
      expect(
        LuciAuthProtocol.loginFields(username: 'root', password: 'secret'),
        {'luci_username': 'root', 'luci_password': 'secret'},
      );

      expect(
        LuciAuthProtocol.loginFields(
          username: 'root',
          password: 'secret',
          otp: ' 123456 ',
        ),
        {
          'luci_username': 'root',
          'luci_password': 'secret',
          'luci_otp': '123456',
        },
      );
    });

    test('extracts only a LuCI authentication cookie', () {
      final cookie = LuciAuthProtocol.parseAuthCookie([
        'theme=argon; Path=/',
        'sysauth_https=abc123; Path=/cgi-bin/luci; HttpOnly; Secure',
      ]);

      expect(cookie?.name, 'sysauth_https');
      expect(cookie?.value, 'abc123');
    });

    test('recognizes a LuCI OTP challenge', () {
      final status = LuciAuthProtocol.classifyLoginResponse(
        statusCode: 403,
        headers: const {
          'x-luci-login-required': ['yes'],
        },
        body: '<input name="luci_otp" autocomplete="one-time-code">',
      );

      expect(status, LuciLoginStatus.otpRequired);
    });
  });

  group('LuCI RPC protocol', () {
    const session = LuciSession(
      token: 'abc123',
      cookieName: 'sysauth_https',
      useHttps: true,
    );

    test('protected RPC uses the authenticated cookie session', () {
      final request = LuciAuthProtocol.rpcRequest(
        session: session,
        object: 'system',
        method: 'board',
      );

      expect(request.path, '/cgi-bin/luci/admin/ubus2fa');
      expect(request.headers['Cookie'], 'sysauth_https=abc123');
      expect(request.body['params'][0], '00000000000000000000000000000000');
    });
  });
}
