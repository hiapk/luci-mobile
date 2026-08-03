const String luciAnonymousSession = '00000000000000000000000000000000';

enum LuciLoginStatus { success, otpRequired, rejected, connectionError }

enum LuciRpcEndpoint { protected, legacy }

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
    required LuciRpcEndpoint endpoint,
    required String object,
    required String method,
    Map<String, dynamic>? params,
  }) {
    final protected = endpoint == LuciRpcEndpoint.protected;
    return LuciRpcRequest(
      path: protected
          ? '/cgi-bin/luci/admin/ubus2fa'
          : '/cgi-bin/luci/admin/ubus',
      headers: {
        'Content-Type': 'application/json',
        'Cookie': '${session.cookieName}=${session.token}',
      },
      body: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'call',
        'params': [
          protected ? luciAnonymousSession : session.token,
          object,
          method,
          params ?? <String, dynamic>{},
        ],
      },
    );
  }

  static bool shouldFallbackToLegacy(
    LuciRpcEndpoint endpoint,
    int? statusCode,
  ) {
    return endpoint == LuciRpcEndpoint.protected && statusCode == 404;
  }
}
