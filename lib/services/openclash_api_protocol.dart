import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';

enum OpenClashHttpMethod { get, post }

class OpenClashHttpRequest {
  final OpenClashHttpMethod method;
  final String path;
  final Map<String, String> headers;
  final Map<String, String> fields;

  const OpenClashHttpRequest({
    required this.method,
    required this.path,
    required this.headers,
    this.fields = const {},
  });
}

class OpenClashApiProtocol {
  static const String _root = '/cgi-bin/luci/admin/services/luci-mobile-mihomo';

  static Map<String, String> _headers(
    LuciSession session, {
    bool form = false,
  }) => {
    'Cookie': '${session.cookieName}=${session.token}',
    if (form) 'Content-Type': 'application/x-www-form-urlencoded',
  };

  static OpenClashHttpRequest overview(LuciSession session) =>
      OpenClashHttpRequest(
        method: OpenClashHttpMethod.get,
        path: '$_root/overview',
        headers: _headers(session),
      );

  static OpenClashHttpRequest proxies(LuciSession session) =>
      OpenClashHttpRequest(
        method: OpenClashHttpMethod.get,
        path: '$_root/proxies',
        headers: _headers(session),
      );

  static OpenClashHttpRequest selectProxy(
    LuciSession session, {
    required String group,
    required String proxy,
  }) => OpenClashHttpRequest(
    method: OpenClashHttpMethod.post,
    path: '$_root/proxies/select',
    headers: _headers(session, form: true),
    fields: {'sessionid': session.token, 'group': group, 'proxy': proxy},
  );

  static OpenClashHttpRequest testDelay(
    LuciSession session, {
    required String kind,
    required String name,
    String? provider,
  }) => OpenClashHttpRequest(
    method: OpenClashHttpMethod.post,
    path: '$_root/proxies/delay',
    headers: _headers(session, form: true),
    fields: {
      'sessionid': session.token,
      'kind': kind,
      'name': name,
      if (provider != null && provider.isNotEmpty) 'provider': provider,
    },
  );

  static OpenClashHttpRequest switchMode(
    LuciSession session,
    OpenClashMode mode,
  ) => OpenClashHttpRequest(
    method: OpenClashHttpMethod.post,
    path: '$_root/mode',
    headers: _headers(session, form: true),
    fields: {'sessionid': session.token, 'mode': mode.apiValue},
  );
}
