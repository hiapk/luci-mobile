import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';

void main() {
  test('system log uses the authenticated LuCI CGI executor', () {
    const session = LuciSession(
      token: 'session-token',
      cookieName: 'sysauth_https',
      useHttps: true,
    );

    final request = LuciAuthProtocol.cgiExecRequest(
      session: session,
      command: '/usr/libexec/syslog-wrapper',
    );

    expect(request.path, '/cgi-bin/cgi-exec');
    expect(request.headers['Cookie'], 'sysauth_https=session-token');
    expect(
      request.headers['Content-Type'],
      'application/x-www-form-urlencoded',
    );
    expect(request.fields, {
      'sessionid': 'session-token',
      'command': '/usr/libexec/syslog-wrapper',
    });
  });

  test('CGI executor escapes command arguments like LuCI fs.exec_direct', () {
    const session = LuciSession(
      token: 'token',
      cookieName: 'sysauth_http',
      useHttps: false,
    );

    final request = LuciAuthProtocol.cgiExecRequest(
      session: session,
      command: '/bin/ping',
      arguments: const ['-c', '1', 'openwrt.org'],
    );

    expect(request.fields['command'], '/bin/ping -c 1 openwrt.org');
  });

  test('CGI executor escapes whitespace and backslashes in arguments', () {
    const session = LuciSession(
      token: 'token',
      cookieName: 'sysauth_https',
      useHttps: true,
    );

    final request = LuciAuthProtocol.cgiExecRequest(
      session: session,
      command: '/usr/bin/example command',
      arguments: const [r'a\b', 'two words'],
    );

    expect(
      request.fields['command'],
      r'/usr/bin/example\ command a\\b two\ words',
    );
  });
}
