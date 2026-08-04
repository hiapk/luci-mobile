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
    required this.cookieName,
    required this.actualUseHttps,
    required this.status,
  });

  bool get requiresOtp => status == LuciLoginStatus.otpRequired;
}

Uri _buildUrl(String ipAddress, bool useHttps, String path) {
  final scheme = useHttps ? 'https' : 'http';
  // Handle cases where ipAddress might already include a port
  String host = ipAddress;
  // Don't add scheme if the address already has one (shouldn't happen with our parser)
  if (host.startsWith('http://') || host.startsWith('https://')) {
    return Uri.parse('$host$path');
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
      final response = await client.post(
        uri.toString(),
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: true,
          validateStatus: (code) =>
              code != null && ((code >= 200 && code < 400) || code == 403),
        ),
      );

      // Check if we were redirected to HTTPS (only relevant for initial HTTP attempts)
      if (checkRedirect && !useHttps) {
        final finalUrl = response.realUri;
        if (finalUrl.scheme == 'https') {
          Logger.info('Detected HTTP to HTTPS redirect: $uri -> $finalUrl');
          // If we got a successful login after redirect, extract the token
          if (response.statusCode == 302 || response.statusCode == 200) {
            final cookie = LuciAuthProtocol.parseAuthCookie(
              response.headers.map['set-cookie'],
            );
            if (cookie != null) {
              _lastCookieName = cookie.name;
              return 'HTTPS_REDIRECT:${cookie.value}';
            }
          }
          // No token found, trigger HTTPS retry
          return null;
        }
      }

      if (response.statusCode == 302 || response.statusCode == 200) {
        // Parse Set-Cookie headers to find sysauth cookie
        final cookie = LuciAuthProtocol.parseAuthCookie(
          response.headers.map['set-cookie'],
        );
        if (cookie != null) {
          _lastCookieName = cookie.name;
          _lastLoginStatus = LuciLoginStatus.success;
          return cookie.value;
        }
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
            final retryResponse = await retryClient.post(
              uri.toString(),
              data: params,
              options: Options(
                contentType: Headers.formUrlEncodedContentType,
                followRedirects: true,
                validateStatus: (code) =>
                    code != null &&
                    ((code >= 200 && code < 400) || code == 403),
              ),
            );

            if (retryResponse.statusCode == 302 ||
                retryResponse.statusCode == 200) {
              final cookie = LuciAuthProtocol.parseAuthCookie(
                retryResponse.headers.map['set-cookie'],
              );
              if (cookie != null) {
                _lastCookieName = cookie.name;
                _lastLoginStatus = LuciLoginStatus.success;
                return cookie.value;
              }
            }
            _lastLoginStatus = LuciAuthProtocol.classifyLoginResponse(
              statusCode: retryResponse.statusCode ?? 0,
              headers: retryResponse.headers.map,
              body: retryResponse.data?.toString() ?? '',
            );
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
        options: Options(
          headers: request.headers,
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
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('RPC 返回了无效的 JSON 数据');
        }
        if (decoded['error'] != null) {
          throw Exception('RPC error: ${decoded['error']['message']}');
        }
        // Return in LuCI RPC format: [status, data]
        final result = decoded['result'];
        if (result is List && result.isNotEmpty) {
          // Result is already in [status, data] format
          return result;
        } else {
          // Wrap single result in format: [0, data]
          return [0, result];
        }
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
        final interfaces = WirelessInterfacePolicy.apInterfaceNames(
          wirelessData,
        );
        final entries = await Future.wait(
          interfaces.map((ifname) async {
            final stations = await fetchAssociatedStationsWithContext(
              ipAddress: ipAddress,
              sysauth: sysauth,
              useHttps: useHttps,
              interface: ifname,
              context: context?.mounted == true ? context : null,
            );
            return MapEntry(ifname, stations.toSet());
          }),
        );
        return Map.fromEntries(
          entries.where((entry) => entry.value.isNotEmpty),
        );
      }
      return {};
    } catch (e, stack) {
      Logger.exception('Failed to fetch all associated stations', e, stack);
      return {};
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
          return resultsList
              .map(
                (entry) => (entry as Map<String, dynamic>)['mac']?.toString(),
              )
              .where((mac) => mac != null)
              .cast<String>()
              .toList();
        }
      }
      return [];
    } catch (e, stack) {
      Logger.exception('Failed to fetch associated stations', e, stack);
      return [];
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
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'set',
      params: {'config': config, 'section': section, 'values': values},
      context: context,
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
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'commit',
      params: {'config': config},
      context: context,
    );
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'system',
      method: 'exec',
      params: {'command': command},
      context: context,
    );
  }
}
