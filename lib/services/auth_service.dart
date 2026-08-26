import 'package:flutter/material.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import 'package:luci_mobile/services/totp_service.dart';

enum _SavedSessionResult { missing, valid, expired, unavailable }

class TotpEnrollmentException implements Exception {
  const TotpEnrollmentException();

  @override
  String toString() => 'Face ID 动态码保存失败，请使用手动验证码重试。';
}

class RealAuthService implements IAuthService {
  final SecureStorageService _secureStorageService;
  final TotpService _totpService;
  final IApiService _apiService;

  String? _sysauth;
  String? _cookieName;
  String? _ipAddress;
  bool _useHttps = false;
  bool _requiresOtp = false;

  RealAuthService(
    this._apiService, {
    SecureStorageService? secureStorageService,
    TotpService? totpService,
  }) : _secureStorageService = secureStorageService ?? SecureStorageService(),
       _totpService = totpService ?? TotpService();

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
    String? totpSecret,
    BuildContext? context,
  }) async {
    String? normalizedSecret;
    var effectiveOtp = otp;
    if (totpSecret != null && totpSecret.trim().isNotEmpty) {
      normalizedSecret = _totpService.normalizeSecret(totpSecret);
      effectiveOtp = await _totpService.generateForLogin(normalizedSecret);
    }
    if (context != null && !context.mounted) return;
    await _login(
      ipAddress,
      username,
      password,
      useHttps,
      otp: effectiveOtp,
      totpSecretToSave: normalizedSecret,
      allowStoredTotp: effectiveOtp == null || effectiveOtp.trim().isEmpty,
      context: context,
    );
  }

  Future<bool> _login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    String? otp,
    String? totpSecretToSave,
    bool allowStoredTotp = true,
    BuildContext? context,
  }) async {
    _sysauth = null;
    _cookieName = null;
    _requiresOtp = false;
    try {
      // Check if the API service is RealApiService to use protocol detection
      if (_apiService is RealApiService) {
        final realApiService = _apiService;
        var loginResult = await realApiService.loginWithProtocolDetection(
          ip,
          user,
          pass,
          useHttps,
          otp: otp,
          context: context,
        );

        if (loginResult.token == null &&
            loginResult.requiresOtp &&
            allowStoredTotp &&
            (otp == null || otp.trim().isEmpty)) {
          _requiresOtp = true;
          final storedOtp = await _readStoredTotpCode(
            ipAddress: ip,
            username: user,
          );
          if (storedOtp != null) {
            if (context != null && !context.mounted) return false;
            loginResult = await realApiService.loginWithProtocolDetection(
              ip,
              user,
              pass,
              loginResult.actualUseHttps,
              otp: storedOtp,
              context: context,
            );
          }
        }

        if (loginResult.token != null) {
          if (totpSecretToSave != null) {
            try {
              await _secureStorageService.saveTotpSecret(
                ipAddress: ip,
                username: user,
                secret: totpSecretToSave,
              );
            } catch (e, stack) {
              realApiService.forgetSession(ip, loginResult.actualUseHttps);
              _requiresOtp = true;
              Logger.exception('Failed to enroll Face ID TOTP', e, stack);
              throw const TotpEnrollmentException();
            }
          }
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
    } on TotpEnrollmentException {
      rethrow;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _readStoredTotpCode({
    required String ipAddress,
    required String username,
  }) async {
    final configured = await _secureStorageService.hasTotpSecret(
      ipAddress: ipAddress,
      username: username,
    );
    if (!configured) return null;
    final secret = await _secureStorageService.readTotpSecret(
      ipAddress: ipAddress,
      username: username,
    );
    if (secret == null || secret.isEmpty) return null;
    return _totpService.generateForLogin(secret);
  }

  @override
  Future<FallbackLoginResult> loginWithFallback({
    required String activeAddress,
    required bool activeHttps,
    required int activeIndex,
    String? fallbackAddress,
    bool? fallbackHttps,
    required String username,
    required String password,
    String? otp,
    String? totpSecret,
    BuildContext? context,
  }) async {
    String? normalizedSecret;
    var effectiveOtp = otp;
    if (totpSecret != null && totpSecret.trim().isNotEmpty) {
      normalizedSecret = _totpService.normalizeSecret(totpSecret);
      effectiveOtp = await _totpService.generateForLogin(normalizedSecret);
    }
    final allowStoredTotp = effectiveOtp == null || effectiveOtp.trim().isEmpty;

    Future<bool> tryAddress(String address, bool useHttps) async {
      if (effectiveOtp == null && normalizedSecret == null) {
        final savedSession = await _restoreSavedSession(address, useHttps);
        if (savedSession == _SavedSessionResult.valid) return true;
        if (savedSession == _SavedSessionResult.unavailable) return false;
      }
      return _login(
        address,
        username,
        password,
        useHttps,
        otp: effectiveOtp,
        totpSecretToSave: normalizedSecret,
        allowStoredTotp: allowStoredTotp,
        context: context?.mounted == true ? context : null,
      );
    }

    // Try the active address first, including any restorable LuCI session.
    final activeOk = await tryAddress(activeAddress, activeHttps);
    if (activeOk) {
      return FallbackLoginResult(success: true, usedAddressIndex: activeIndex);
    }

    // Try the fallback address if available
    if (fallbackAddress != null &&
        fallbackAddress.isNotEmpty &&
        fallbackHttps != null) {
      final fallbackIndex = activeIndex == 0 ? 1 : 0;
      final fallbackOk = await tryAddress(fallbackAddress, fallbackHttps);
      if (fallbackOk) {
        return FallbackLoginResult(
          success: true,
          usedAddressIndex: fallbackIndex,
        );
      }
    }

    return FallbackLoginResult(success: false, usedAddressIndex: activeIndex);
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
