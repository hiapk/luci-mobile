const String luciAnonymousSession = '00000000000000000000000000000000';

enum LuciLoginStatus { success, otpRequired, rejected, connectionError }

class LuciSessionExpiredException implements Exception {
  final String message;

  const LuciSessionExpiredException([this.message = 'LuCI 会话已过期，请重新登录。']);

  @override
  String toString() => message;
}

class LuciAuthCookie {
  final String name;
  final String value;

  const LuciAuthCookie({required this.name, required this.value});
}

class LuciSession {
  final String token;
  final String cookieName;
  final bool useHttps;

  const LuciSession({
    required this.token,
    required this.cookieName,
    required this.useHttps,
  });
}

class LuciRpcRequest {
  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic> body;

  const LuciRpcRequest({
    required this.path,
    required this.headers,
    required this.body,
  });
}

class LuciCgiExecRequest {
  final String path;
  final Map<String, String> headers;
  final Map<String, String> fields;

  const LuciCgiExecRequest({
    required this.path,
    required this.headers,
    required this.fields,
  });
}

class LuciAuthProtocol {
  static Map<String, String> loginFields({
    required String username,
    required String password,
    String? otp,
  }) {
    final fields = <String, String>{
      'luci_username': username,
      'luci_password': password,
    };
    final normalizedOtp = otp?.trim();
    if (normalizedOtp != null && normalizedOtp.isNotEmpty) {
      fields['luci_otp'] = normalizedOtp;
    }
    return fields;
  }

  static LuciAuthCookie? parseAuthCookie(List<String>? setCookieHeaders) {
    if (setCookieHeaders == null) return null;

    final pattern = RegExp(
      r'(?:^|;\s*)(sysauth(?:_https|_http)?)=([^;,\s]+)',
      caseSensitive: false,
    );
    for (final header in setCookieHeaders) {
      final match = pattern.firstMatch(header);
      if (match != null) {
        return LuciAuthCookie(name: match.group(1)!, value: match.group(2)!);
      }
    }
    return null;
  }

  static LuciLoginStatus classifyLoginResponse({
    required int statusCode,
    required Map<String, List<String>> headers,
    required String body,
  }) {
    final loginRequired = headers.entries.any(
      (entry) =>
          entry.key.toLowerCase() == 'x-luci-login-required' &&
          entry.value.any((value) => value.toLowerCase() == 'yes'),
    );
    if (statusCode == 403 &&
        loginRequired &&
        (body.contains('luci_otp') || body.contains('one-time-code'))) {
      return LuciLoginStatus.otpRequired;
    }
    return LuciLoginStatus.rejected;
  }

  static LuciRpcRequest rpcRequest({
    required LuciSession session,
    required String object,
    required String method,
    Map<String, dynamic>? params,
  }) {
    return LuciRpcRequest(
      path: '/cgi-bin/luci/admin/ubus2fa',
      headers: {
        'Content-Type': 'application/json',
        'Cookie': '${session.cookieName}=${session.token}',
      },
      body: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'call',
        'params': [
          luciAnonymousSession,
          object,
          method,
          params ?? <String, dynamic>{},
        ],
      },
    );
  }

  static LuciCgiExecRequest cgiExecRequest({
    required LuciSession session,
    required String command,
    List<String> arguments = const [],
  }) {
    String escape(String value) => value
        .replaceAll('\\', '\\\\')
        .replaceAllMapped(RegExp(r'\s'), (match) => '\\${match.group(0)}');

    final commandLine = <String>[
      escape(command),
      ...arguments.map(escape),
    ].join(' ');
    return LuciCgiExecRequest(
      path: '/cgi-bin/cgi-exec',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': '${session.cookieName}=${session.token}',
      },
      fields: {'sessionid': session.token, 'command': commandLine},
    );
  }
}
