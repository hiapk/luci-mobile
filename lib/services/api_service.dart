import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:luci_mobile/services/client_list_policy.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import '../utils/http_client_manager.dart';
import '../utils/logger.dart';

class LoginResult {
  final String? token;
  final String? cookieName;
  final bool actualUseHttps;
  final LuciLoginStatus status;

  const LoginResult({
    required this.token,
    this.cookieName,
    required this.actualUseHttps,
    this.status = LuciLoginStatus.rejected,
  });

  bool get requiresOtp => status == LuciLoginStatus.otpRequired;
}

class RpcException implements Exception {
  final int? status;
  final String object;
  final String method;
  final String? detail;

  const RpcException({
    required this.object,
    required this.method,
    this.status,
    this.detail,
  });

  @override
  String toString() {
    final call = '$object.$method';
    final unavailable =
        status == 3 ||
        status == 4 ||
        status == 8 ||
        detail?.toLowerCase().contains('not found') == true ||
        detail?.toLowerCase().contains('not supported') == true;
    if (unavailable && object == 'luci-rpc') {
      return 'Router RPC support is missing: $call is unavailable. Install '
          'rpcd-mod-luci, restart rpcd, then reconnect.';
    }
    if (unavailable && object == 'iwinfo') {
      return 'Wireless client support is missing: $call is unavailable. '
          'Install rpcd-mod-iwinfo, restart rpcd, then refresh.';
    }
    if (status == 6 ||
        detail?.toLowerCase().contains('access denied') == true) {
      return 'This account does not have permission for $call. Sign in with '
          'an administrator account or grant the required RPC access.';
    }

    final reason = switch (status) {
      1 => 'invalid command',
      2 => 'invalid argument',
      3 => 'method not found',
      4 => 'object not found',
      5 => 'no data',
      7 => 'timed out',
      8 => 'not supported',
      9 => 'unknown error',
      10 => 'connection failed',
      _ => detail ?? 'unknown error',
    };
    return 'Router RPC call $call failed: ${detail ?? reason}.';
  }
}

/// Validates the ubus `[status, data]` envelope while preserving it for
/// existing callers.
dynamic validateRpcResult(
  dynamic result, {
  required String object,
  required String method,
}) {
  if (result is! List ||
      result.isEmpty ||
      result.length > 2 ||
      result.first is! int) {
    throw RpcException(
      object: object,
      method: method,
      detail: 'invalid response',
    );
  }

  final status = result.first as int;
  if (status != 0) {
    throw RpcException(
      object: object,
      method: method,
      status: status,
      detail: result.length > 1 ? result[1]?.toString() : null,
    );
  }
  return result;
}

bool? rpcAccessAllowed(dynamic result) {
  if (result is List &&
      result.length == 2 &&
      result[0] is int &&
      result[0] == 0) {
    final data = result[1];
    if (data is Map && data['access'] is bool) return data['access'] as bool;
  }
  return null;
}

String userFacingApiError(Object error) {
  if (error is RpcException) return error.toString();
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'The router rejected this session. Reconnect and check the '
          'account\'s RPC permissions.';
    }
    if (status != null) return 'The router returned HTTP $status.';
    return 'Could not connect to the router. Check its address and your '
        'network connection, then try again.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

Uri _buildUrl(String ipAddress, bool useHttps, String path) {
  final scheme = useHttps ? 'https' : 'http';
  // Handle cases where ipAddress might already include a scheme
  String host = ipAddress;
  if (host.startsWith('http://') || host.startsWith('https://')) {
    return Uri.parse('$host$path');
  }
  // Bracket bare IPv6 literals (2+ colons) - string interpolation into
  // Uri.parse produces an invalid authority otherwise.
  if (!host.startsWith('[') && ':'.allMatches(host).length > 1) {
    host = '[$host]';
  }
  return Uri.parse('$scheme://$host$path');
}

class RealApiService implements IApiService {
  final HttpClientManager _httpClientManager = HttpClientManager();
  final Map<String, LuciSession> _sessions = {};
  LuciLoginStatus _lastLoginStatus = LuciLoginStatus.rejected;
  String? _lastCookieName;

  String _routerKey(String ipAddress, bool useHttps) =>
      '${useHttps ? 'https' : 'http'}://$ipAddress';

  void _rememberSession(
    String ipAddress,
    bool useHttps,
    String token,
    String? cookieName,
  ) {
    final session = LuciSession(
      token: token,
      cookieName: cookieName ?? (useHttps ? 'sysauth_https' : 'sysauth_http'),
      useHttps: useHttps,
    );
    _sessions[_routerKey(ipAddress, useHttps)] = session;
  }

  void restoreSession(String ipAddress, bool useHttps, LuciSession session) {
    _sessions[_routerKey(ipAddress, useHttps)] = session;
  }

  void forgetSession(String ipAddress, bool useHttps) {
    _sessions.remove(_routerKey(ipAddress, useHttps));
  }

  List<dynamic> _requireRpcSuccess(dynamic result, String operation) {
    if (result is List && result.isNotEmpty && result[0] == 0) return result;
    final detail = result is List && result.length > 1 ? result[1] : result;
    throw Exception('$operation failed: $detail');
  }

  Dio _createHttpClient(
    bool useHttps,
    String hostWithPort, {
    BuildContext? context,
  }) {
    return _httpClientManager.getClient(
      hostWithPort,
      useHttps,
      context: context,
    );
  }

  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    String? otp,
    BuildContext? context,
  }) async {
    final result = await loginWithProtocolDetection(
      ipAddress,
      username,
      password,
      useHttps,
      otp: otp,
      context: context,
    );
    if (result.token == null) {
      throw Exception('Login failed');
    }
    return result.token!;
  }

  /// Login with automatic HTTPS redirect detection
  /// Returns both the auth token and the actual protocol used
  Future<LoginResult> loginWithProtocolDetection(
    String ipAddress,
    String username,
    String password,
    bool initialUseHttps, {
    String? otp,
    BuildContext? context,
  }) async {
    _lastLoginStatus = LuciLoginStatus.rejected;
    _lastCookieName = null;
    // First try with the initial protocol
    var result = await _login(
      ipAddress,
      username,
      password,
      initialUseHttps,
      otp: otp,
      context: context,
      checkRedirect: true,
    );

    // Check if we got a redirect marker
    if (result != null && result.startsWith('HTTPS_REDIRECT:')) {
      final token = result.substring('HTTPS_REDIRECT:'.length);
      Logger.info('Login successful via HTTP to HTTPS redirect');
      _rememberSession(ipAddress, true, token, _lastCookieName);
      return LoginResult(
        token: token,
        cookieName: _lastCookieName,
        actualUseHttps: true,
        status: LuciLoginStatus.success,
      );
    }

    if (result != null) {
      _rememberSession(ipAddress, initialUseHttps, result, _lastCookieName);
      return LoginResult(
        token: result,
        cookieName: _lastCookieName,
        actualUseHttps: initialUseHttps,
        status: LuciLoginStatus.success,
      );
    }

    if (_lastLoginStatus == LuciLoginStatus.otpRequired) {
      return LoginResult(
        token: null,
        cookieName: null,
        actualUseHttps: initialUseHttps,
        status: _lastLoginStatus,
      );
    }

    // If login failed and we were using HTTP, try HTTPS in case of redirect
    if (!initialUseHttps) {
      Logger.info('HTTP login failed or redirected, attempting HTTPS');
      final safeContext = context?.mounted == true ? context : null;
      result = await _login(
        ipAddress,
        username,
        password,
        true, // Try with HTTPS
        otp: otp,
        context: safeContext, // ignore: use_build_context_synchronously
        checkRedirect: false,
      );

      if (result != null) {
        Logger.info('Login successful with HTTPS after redirect detection');
        _rememberSession(ipAddress, true, result, _lastCookieName);
        return LoginResult(
          token: result,
          cookieName: _lastCookieName,
          actualUseHttps: true,
          status: LuciLoginStatus.success,
        );
      }
    }

    return LoginResult(
      token: null,
      cookieName: null,
      actualUseHttps: initialUseHttps,
      status: _lastLoginStatus,
    );
  }

  /// POSTs the login form. Returns the raw response so callers can inspect
  /// redirect targets; any status accepted by [Options.validateStatus]
  /// (2xx-3xx) may carry the session cookie.
  Future<Response<dynamic>> _sendLogin(
    Dio client,
    Uri uri,
    Map<String, String> params,
  ) {
    return client.post(
      uri.toString(),
      data: params,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: true,
        validateStatus: (code) =>
            code != null && ((code >= 200 && code < 400) || code == 403),
      ),
    );
  }

  /// POSTs the login form and extracts the session token from the
  /// `sysauth` cookie, if present.
  Future<String?> _postLogin(
    Dio client,
    Uri uri,
    Map<String, String> params,
  ) async {
    final response = await _sendLogin(client, uri, params);
    final cookie = LuciAuthProtocol.parseAuthCookie(
      response.headers.map['set-cookie'],
    );
    if (cookie != null) {
      _lastCookieName = cookie.name;
      _lastLoginStatus = LuciLoginStatus.success;
      return cookie.value;
    }
    _lastLoginStatus = LuciAuthProtocol.classifyLoginResponse(
      statusCode: response.statusCode ?? 0,
      headers: response.headers.map,
      body: response.data?.toString() ?? '',
    );
    return null;
  }

  Future<String?> _login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    String? otp,
    BuildContext? context,
    bool checkRedirect = false,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    final uri = _buildUrl(ipAddress, useHttps, '/cgi-bin/luci/');
    final params = LuciAuthProtocol.loginFields(
      username: username,
      password: password,
      otp: otp,
    );

    try {
      // Normal POST request - Dio will follow redirects by default
      final response = await _sendLogin(client, uri, params);

      // Check if we were redirected to HTTPS (only relevant for initial HTTP attempts)
      if (checkRedirect && !useHttps) {
        final finalUrl = response.realUri;
        if (finalUrl.scheme == 'https') {
          Logger.info('Detected HTTP to HTTPS redirect: $uri -> $finalUrl');
          final cookie = LuciAuthProtocol.parseAuthCookie(
            response.headers.map['set-cookie'],
          );
          if (cookie != null) {
            _lastCookieName = cookie.name;
            _lastLoginStatus = LuciLoginStatus.success;
            return 'HTTPS_REDIRECT:${cookie.value}';
          }
          // No token found, trigger HTTPS retry
          return null;
        }
      }

      final cookie = LuciAuthProtocol.parseAuthCookie(
        response.headers.map['set-cookie'],
      );
      if (cookie != null) {
        _lastCookieName = cookie.name;
        _lastLoginStatus = LuciLoginStatus.success;
        return cookie.value;
      }
      _lastLoginStatus = LuciAuthProtocol.classifyLoginResponse(
        statusCode: response.statusCode ?? 0,
        headers: response.headers.map,
        body: response.data?.toString() ?? '',
      );
      return null;
    } on DioException catch (e, stack) {
      Logger.exception('Login failed', e, stack);

      final isCertError =
          e.error is HandshakeException ||
          e.message?.contains('CERTIFICATE_VERIFY_FAILED') == true;

      if (!useHttps && checkRedirect && isCertError) {
        Logger.info(
          'Detected HTTPS certificate issue during redirect; retrying with HTTPS',
        );
        final retryContext = context != null && context.mounted
            ? context
            : null;
        try {
          return await _login(
            ipAddress,
            username,
            password,
            true,
            otp: otp,
            context: retryContext, // ignore: use_build_context_synchronously
            checkRedirect: false,
          );
        } on DioException catch (httpsError, httpsStack) {
          Logger.exception(
            'HTTPS retry after redirect failed',
            httpsError,
            httpsStack,
          );
        }
      }

      if (useHttps && context != null && context.mounted && isCertError) {
        // Try to prompt for certificate acceptance
        final accepted = await _httpClientManager
            .promptForCertificateAcceptance(
              context: context,
              hostWithPort: ipAddress,
              useHttps: useHttps,
            );

        if (accepted && context.mounted) {
          // Create a new client and retry the login
          final retryClient = _createHttpClient(
            useHttps,
            ipAddress,
            context: context,
          );
          try {
            return await _postLogin(retryClient, uri, params);
          } on DioException catch (retryError, retryStack) {
            Logger.exception('Login retry failed', retryError, retryStack);
          }
        }
      }

      if (isCertError) {
        _lastLoginStatus = LuciLoginStatus.connectionError;
        return null;
      }

      _lastLoginStatus = LuciLoginStatus.connectionError;
      rethrow;
    }
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }

  // Simplified call method for reviewer mode
  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    // Use default values for ipAddress, sysauth, and useHttps
    // This is primarily for mock/testing scenarios
    return await call(
      'localhost', // Default IP address
      '', // Default sysauth (empty for mock scenarios)
      false, // Default to HTTP
      object: object,
      method: method,
      params: params,
    );
  }

  @override
  Future<String> execDirect(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> arguments = const [],
    BuildContext? context,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    final session =
        _sessions[_routerKey(ipAddress, useHttps)] ??
        LuciSession(
          token: sysauth,
          cookieName: useHttps ? 'sysauth_https' : 'sysauth_http',
          useHttps: useHttps,
        );
    final request = LuciAuthProtocol.cgiExecRequest(
      session: session,
      command: command,
      arguments: arguments,
    );
    final response = await client.postUri<dynamic>(
      _buildUrl(ipAddress, useHttps, request.path),
      data: request.fields,
      options: Options(
        headers: request.headers,
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (code) => code != null && code < 500,
      ),
    );
    if (response.statusCode == 403) {
      throw const LuciSessionExpiredException('LuCI 拒绝执行该命令。');
    }
    if (response.statusCode != 200) {
      throw Exception('LuCI 命令执行失败（HTTP ${response.statusCode}）。');
    }
    return response.data?.toString() ?? '';
  }

  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) {
    return _callWithTransport(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }

  Future<dynamic> _callWithTransport(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    final routerKey = _routerKey(ipAddress, useHttps);
    final session =
        _sessions[routerKey] ??
        LuciSession(
          token: sysauth,
          cookieName: useHttps ? 'sysauth_https' : 'sysauth_http',
          useHttps: useHttps,
        );
    Future<Response<dynamic>> send() {
      final request = LuciAuthProtocol.rpcRequest(
        session: session,
        object: object,
        method: method,
        params: params,
      );
      final url = _buildUrl(ipAddress, useHttps, request.path);
      return client.post(
        url.toString(),
        data: jsonEncode(request.body),
        cancelToken: cancelToken,
        options: Options(
          headers: request.headers,
          receiveTimeout: receiveTimeout,
          validateStatus: (code) => code == 200 || code == 403 || code == 404,
        ),
      );
    }

    try {
      final response = await send();

      if (response.statusCode == 200) {
        final decoded = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (decoded is! Map) {
          throw RpcException(
            object: object,
            method: method,
            detail: 'invalid response',
          );
        }
        if (decoded['error'] != null) {
          final error = decoded['error'];
          throw RpcException(
            object: object,
            method: method,
            detail: error is Map ? error['message']?.toString() : '$error',
          );
        }
        return validateRpcResult(
          decoded['result'],
          object: object,
          method: method,
        );
      } else if (response.statusCode == 403) {
        throw const LuciSessionExpiredException();
      } else {
        throw Exception('RPC 调用失败：HTTP ${response.statusCode}');
      }
    } on DioException catch (e, stack) {
      Logger.exception('API call failed', e, stack);
      rethrow;
    }
  }

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return await rebootWithContext(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
  }

  Future<bool> rebootWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'reboot',
        context: context,
      );
      // Handle LuCI RPC format: [status, data] - successful reboot returns [0, ...]
      if (result is List && result.isNotEmpty && result[0] == 0) {
        Logger.info('Router reboot initiated successfully');
        return true;
      }
      Logger.warning('Router reboot call returned unexpected result: $result');
      return false;
    } catch (e, stack) {
      Logger.exception('Router reboot failed', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async {
    // This method is mainly used by the mock service
    // For real implementation, individual interface queries via fetchAssociatedStationsWithContext should be used
    // The app_state.dart should call fetchAllAssociatedWirelessMacsWithContext instead
    throw UnimplementedError(
      'Use fetchAllAssociatedWirelessMacsWithContext for real implementation',
    );
  }

  /// Fetches all associated wireless MAC addresses from all wireless interfaces for real API
  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    const invalidResponse = RpcException(
      object: 'luci-rpc',
      method: 'getWirelessDevices',
      detail: 'invalid response',
    );
    try {
      // First, get wireless device information to find all wireless interfaces
      final wirelessResult = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        context: context,
      );

      if (wirelessResult is List &&
          wirelessResult.length > 1 &&
          wirelessResult[0] == 0) {
        final wirelessData = wirelessResult[1];
        if (wirelessData is! Map) throw invalidResponse;
        for (final radioData in wirelessData.values) {
          if (radioData is! Map) throw invalidResponse;
        }
        final interfaces = WirelessInterfacePolicy.apInterfaceNames(
          wirelessData,
        );
        final result = <String, Set<String>>{};
        Object? firstError;
        StackTrace? firstStack;
        var succeeded = 0;
        for (final ifname in interfaces) {
          try {
            final stations = await fetchAssociatedStationsWithContext(
              ipAddress: ipAddress,
              sysauth: sysauth,
              useHttps: useHttps,
              interface: ifname,
              context: context?.mounted == true ? context : null,
            );
            succeeded++;
            if (stations.isNotEmpty) result[ifname] = stations.toSet();
          } catch (error, stack) {
            firstError ??= error;
            firstStack ??= stack;
          }
        }
        if (interfaces.isNotEmpty && succeeded == 0 && firstError != null) {
          Error.throwWithStackTrace(firstError, firstStack!);
        }
        return result;
      }
      throw invalidResponse;
    } catch (e, stack) {
      Logger.exception('Failed to fetch all associated stations', e, stack);
      rethrow;
    }
  }

  /// Fetches associated stations (wireless clients) for a given wireless interface (e.g., wlan0)
  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    const invalidResponse = RpcException(
      object: 'iwinfo',
      method: 'assoclist',
      detail: 'invalid response',
    );
    try {
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'assoclist',
        params: {'device': interface},
        context: context,
      );
      // Handle LuCI RPC format: [status, data]
      if (result is List && result.length > 1 && result[0] == 0) {
        final data = result[1];
        if (data is Map && data['results'] is List) {
          final resultsList = data['results'] as List;
          final macs = <String>[];
          for (final entry in resultsList) {
            if (entry is! Map<String, dynamic>) throw invalidResponse;
            final mac = entry['mac'];
            if (mac != null) macs.add(mac.toString());
          }
          return macs;
        }
      }
      throw invalidResponse;
    } catch (e, stack) {
      Logger.exception('Failed to fetch associated stations', e, stack);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    return await fetchWireGuardPeersWithContext(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      interface: interface,
      context: context,
    );
  }

  /// Fetches WireGuard peer information for a given interface
  /// If interface is empty, returns data for all WireGuard interfaces
  Future<Map<String, dynamic>?> fetchWireGuardPeersWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    try {
      // Use the correct luci.wireguard.getWgInstances method
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci.wireguard',
        method: 'getWgInstances',
        params: {},
        context: context,
      );

      // Handle LuCI RPC format: [status, data]
      if (result is List && result.length > 1 && result[0] == 0) {
        final data = result[1] as Map<String, dynamic>?;
        if (data != null) {
          return _parseWireGuardFromInstances(data, interface);
        }
      }

      return null;
    } catch (e, stack) {
      Logger.exception('Failed to fetch WireGuard peers', e, stack);
      return null;
    }
  }

  Map<String, dynamic>? _parseWireGuardFromInstances(
    Map<String, dynamic> data,
    String targetInterface,
  ) {
    final wireguardData = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        // Look for peers in the interface data
        final peers = <String, dynamic>{};

        // The structure might have peers in different formats
        if (value['peers'] is List) {
          final peersList = value['peers'] as List;
          for (final peer in peersList) {
            if (peer is Map<String, dynamic>) {
              final publicKey = peer['public_key'] as String?;
              if (publicKey != null) {
                peers[publicKey] = {
                  'public_key': publicKey,
                  'endpoint': peer['endpoint'] ?? 'N/A',
                  'last_handshake':
                      int.tryParse(
                        peer['latest_handshake']?.toString() ?? '0',
                      ) ??
                      0,
                };
              }
            }
          }
        } else if (value['peers'] is Map<String, dynamic>) {
          final peersMap = value['peers'] as Map<String, dynamic>;
          peersMap.forEach((peerKey, peerData) {
            if (peerData is Map<String, dynamic>) {
              peers[peerKey] = {
                'public_key': peerKey,
                'endpoint': peerData['endpoint'] ?? 'N/A',
                'last_handshake':
                    int.tryParse(
                      peerData['latest_handshake']?.toString() ?? '0',
                    ) ??
                    0,
              };
            }
          });
        }

        if (peers.isNotEmpty) {
          wireguardData[key] = {'interface': key, 'peers': peers};
        }
      }
    });

    if (targetInterface.isEmpty) {
      return wireguardData;
    } else {
      return wireguardData[targetInterface];
    }
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    return _requireRpcSuccess(
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {'config': config, 'section': section, 'values': values},
        context: context,
      ),
      'uci.set',
    );
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    return _requireRpcSuccess(
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': config},
        context: context,
      ),
      'uci.commit',
    );
  }

  /// Executes a command on the router via the rpcd `file.exec` ubus method.
  ///
  /// Note: rpcd's `system` object has no `exec` method - command execution
  /// lives in the `file` object (rpcd-mod-file), which LuCI admin sessions
  /// are ACL-granted to use.
  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    final result = _requireRpcSuccess(
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': command, 'params': params},
        context: context,
      ),
      'file.exec',
    );
    final data = result.length > 1 ? result[1] : null;
    if (data is Map && data['code'] is num && data['code'] != 0) {
      throw Exception(
        'file.exec failed: ${data['stderr'] ?? 'exit ${data['code']}'}',
      );
    }
    return result;
  }

  CancelToken? _scanCancelToken;

  @override
  void cancelScan() {
    _scanCancelToken?.cancel('Scan cancelled by user');
    _scanCancelToken = null;
  }

  @override
  Future<List<Map<String, dynamic>>> scanWirelessNetworks({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String device,
    BuildContext? context,
  }) async {
    cancelScan();
    final scanToken = CancelToken();
    _scanCancelToken = scanToken;

    Logger.info('WiFi scan starting on device: $device');

    try {
      final result = await _callWithTransport(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'scan',
        params: {'device': device},
        context: context,
        receiveTimeout: const Duration(seconds: 120),
        cancelToken: scanToken,
      );

      Logger.info('WiFi scan raw result type: ${result.runtimeType}');

      if (result is List) {
        final statusCode = result.isNotEmpty ? result[0] : null;
        if (statusCode != null && statusCode != 0) {
          const ubusErrors = {
            1: 'Invalid command',
            2: 'Invalid argument',
            3: 'Method not found',
            4: 'Not found',
            5: 'No data',
            6: 'Permission denied',
            7: 'Request timed out',
          };
          final errMsg = ubusErrors[statusCode] ?? 'Unknown error';
          throw Exception(
            'iwinfo scan failed: $errMsg (code $statusCode) on device "$device"',
          );
        }

        if (result.length < 2 || result[1] == null) return [];

        final data = result[1];
        if (data is Map) {
          if (data['results'] is List) {
            return (data['results'] as List)
                .whereType<Map<String, dynamic>>()
                .toList();
          }
          for (final value in data.values) {
            if (value is List && value.isNotEmpty && value.first is Map) {
              return value.whereType<Map<String, dynamic>>().toList();
            }
          }
          Logger.warning(
            'WiFi scan: response is Map but no results. Keys: ${data.keys.toList()}',
          );
          return [];
        }

        if (data is List) {
          return data.whereType<Map<String, dynamic>>().toList();
        }

        Logger.warning('WiFi scan: unexpected data type: ${data.runtimeType}');
        return [];
      }

      Logger.warning('WiFi scan: result is not List: ${result.runtimeType}');
      return [];
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return [];
      if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Scan timed out on "$device". The radio may be busy.');
      }
      Logger.exception('WiFi scan DioException', e, e.stackTrace);
      rethrow;
    } finally {
      if (identical(_scanCancelToken, scanToken)) {
        _scanCancelToken = null;
      }
    }
  }

  @override
  Future<dynamic> uciAdd(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String type,
    required Map<String, dynamic> values,
    String? name,
    BuildContext? context,
  }) async {
    return _requireRpcSuccess(
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'add',
        params: {
          'config': config,
          'type': type,
          'values': values,
          'name': ?name,
        },
        context: context,
      ),
      'uci.add',
    );
  }

  @override
  Future<dynamic> uciDelete(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    String? option,
    BuildContext? context,
  }) async {
    return _requireRpcSuccess(
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'delete',
        params: {'config': config, 'section': section, 'option': ?option},
        context: context,
      ),
      'uci.delete',
    );
  }

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    return _requireRpcSuccess(
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': config},
        context: context,
      ),
      'uci.get',
    );
  }
}
