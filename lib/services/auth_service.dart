import 'package:flutter/material.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';

enum _SavedSessionResult { missing, valid, expired, unavailable }

class RealAuthService implements IAuthService {
  final SecureStorageService _secureStorageService = SecureStorageService();
  final IApiService _apiService;

  String? _sysauth;
  String? _cookieName;
  String? _ipAddress;
  bool _useHttps = false;
  bool _requiresOtp = false;

  RealAuthService(this._apiService);

  @override
  String? get sysauth => _sysauth;
  @override
  String? get cookieName => _cookieName;
  @override
  String? get ipAddress => _ipAddress;
  @override
  bool get useHttps => _useHttps;
  @override
  bool get isAuthenticated => _sysauth != null;
  @override
  bool get requiresOtp => _requiresOtp;

  @override
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    String? otp,
    BuildContext? context,
  }) async {
    await _login(
      ipAddress,
      username,
      password,
      useHttps,
      otp: otp,
      context: context,
    );
  }

  Future<bool> _login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    String? otp,
    BuildContext? context,
  }) async {
    _sysauth = null;
    _cookieName = null;
    _requiresOtp = false;
    try {
      // Check if the API service is RealApiService to use protocol detection
      if (_apiService is RealApiService) {
        final realApiService = _apiService;
        final loginResult = await realApiService.loginWithProtocolDetection(
          ip,
          user,
          pass,
          useHttps,
          otp: otp,
          context: context,
        );

        if (loginResult.token != null) {
          _requiresOtp = false;
          _sysauth = loginResult.token;
          _cookieName =
              loginResult.cookieName ??
              (loginResult.actualUseHttps ? 'sysauth_https' : 'sysauth_http');
          _ipAddress = ip;
          _useHttps = loginResult.actualUseHttps; // Use the detected protocol

          await _secureStorageService.saveCredentials(
            ipAddress: ip,
            username: user,
            password: pass,
            useHttps: loginResult.actualUseHttps, // Save the detected protocol
          );
          await _secureStorageService.saveLuciSession(
            ipAddress: ip,
            useHttps: loginResult.actualUseHttps,
            token: _sysauth!,
            cookieName: _cookieName!,
          );

          if (loginResult.actualUseHttps != useHttps) {
            Logger.info(
              'Protocol changed from ${useHttps ? "HTTPS" : "HTTP"} to ${loginResult.actualUseHttps ? "HTTPS" : "HTTP"} due to redirect',
            );
          }

          return true;
        }
        _requiresOtp = loginResult.requiresOtp;
        return false;
      } else {
        // Fallback for mock service
        final token = await _apiService.login(
          ip,
          user,
          pass,
          useHttps,
          otp: otp,
          context: context,
        );
        _sysauth = token;
        _cookieName = useHttps ? 'sysauth_https' : 'sysauth_http';
        _ipAddress = ip;
        _useHttps = useHttps;

        await _secureStorageService.saveCredentials(
          ipAddress: ip,
          username: user,
          password: pass,
          useHttps: useHttps,
        );

        return true;
      }
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    BuildContext? context,
  }) async {
    _sysauth = null;
    _cookieName = null;
    _ipAddress = null;
    _useHttps = false;
    _requiresOtp = false;

    String? ip = ipAddress;
    String? user = username;
    String? pass = password;
    bool? https = useHttps;
    if (ip == null || user == null || pass == null || https == null) {
      final credentials = await _secureStorageService.getCredentials();
      ip = credentials['ipAddress'];
      user = credentials['username'];
      pass = credentials['password'];
      https = credentials['useHttps'] == null
          ? null
          : credentials['useHttps'] == 'true';
    }

    if (ip == null || user == null || pass == null || https == null) {
      return false;
    }

    final savedSession = await _restoreSavedSession(ip, https);
    if (savedSession == _SavedSessionResult.valid) return true;
    if (savedSession == _SavedSessionResult.unavailable) return false;
    if (context != null && !context.mounted) return false;

    return _login(ip, user, pass, https, context: context);
  }

  Future<_SavedSessionResult> _restoreSavedSession(
    String ip,
    bool useHttps,
  ) async {
    final session = await _secureStorageService.getLuciSession(
      ipAddress: ip,
      useHttps: useHttps,
    );
    if (session == null) return _SavedSessionResult.missing;
    final apiService = _apiService;
    if (apiService is! RealApiService) return _SavedSessionResult.missing;

    apiService.restoreSession(ip, useHttps, session);
    try {
      final result = await apiService.call(
        ip,
        session.token,
        useHttps,
        object: 'system',
        method: 'board',
        params: const {},
      );
      if (result is List && result.isNotEmpty && result.first == 0) {
        _sysauth = session.token;
        _cookieName = session.cookieName;
        _ipAddress = ip;
        _useHttps = useHttps;
        _requiresOtp = false;
        Logger.info('Restored authenticated LuCI session for $ip');
        return _SavedSessionResult.valid;
      }
      await _deleteSavedSession(ip, useHttps, apiService);
      return _SavedSessionResult.expired;
    } on LuciSessionExpiredException {
      await _deleteSavedSession(ip, useHttps, apiService);
      return _SavedSessionResult.expired;
    } catch (e, stack) {
      apiService.forgetSession(ip, useHttps);
      Logger.exception('Failed to validate saved LuCI session', e, stack);
      return _SavedSessionResult.unavailable;
    }
  }

  Future<void> _deleteSavedSession(
    String ip,
    bool useHttps,
    RealApiService apiService,
  ) async {
    apiService.forgetSession(ip, useHttps);
    await _secureStorageService.deleteLuciSession(
      ipAddress: ip,
      useHttps: useHttps,
    );
  }

  @override
  Future<void> logout() async {
    _sysauth = null;
    _cookieName = null;
    _ipAddress = null;
    _useHttps = false;
    _requiresOtp = false;
    await _secureStorageService.clearCredentials();
  }

  @override
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (ipAddress.isEmpty) return false;

    try {
      final result = await _apiService.call(
        ipAddress,
        '',
        useHttps,
        object: 'system',
        method: 'board',
        params: {},
        context: context,
      );
      return result != null;
    } catch (e) {
      return false;
    }
  }
}
