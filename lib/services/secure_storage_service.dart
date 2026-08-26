import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import '../utils/logger.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const String _routersKey = 'routers';
  static const String _selectedRouterKey = 'selectedRouterId';
  static const String _clientAliasesKey = 'clientAliases';
  static const String _luciSessionPrefix = 'luciSession:';
  static const String _totpSecretPrefix = 'luciTotpSecret:';
  static const String _totpMarkerPrefix = 'luciTotpConfigured:';
  static const String _totpIndexKey = 'luciTotpIdentityIndex';
  static const IOSOptions _totpSecretOptions = IOSOptions(
    accountName: 'app.hiapk.lucimobile2fa.totp',
    accessibility: KeychainAccessibility.passcode,
    synchronizable: false,
    useSecureEnclave: true,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    label: 'LuCI Face ID 动态码',
  );
  static const IOSOptions _deviceOnlyOptions = IOSOptions(
    accountName: 'app.hiapk.lucimobile2fa.totp-metadata',
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  bool get supportsFaceIdTotp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  String _luciSessionKey(String ipAddress, bool useHttps) {
    final identity = '${useHttps ? 'https' : 'http'}://$ipAddress';
    return '$_luciSessionPrefix${base64Url.encode(utf8.encode(identity))}';
  }

  String _totpIdentity(String ipAddress, String username) {
    final identity = '$ipAddress|$username';
    return base64Url.encode(utf8.encode(identity));
  }

  String _totpSecretKey(String identity) => '$_totpSecretPrefix$identity';

  String _totpMarkerKey(String identity) => '$_totpMarkerPrefix$identity';

  Future<Set<String>> _getTotpIdentityIndex() async {
    final encoded = await _storage.read(
      key: _totpIndexKey,
      iOptions: _deviceOnlyOptions,
    );
    if (encoded == null || encoded.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .where((identity) => identity.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveTotpIdentityIndex(Set<String> identities) async {
    if (identities.isEmpty) {
      await _storage.delete(key: _totpIndexKey, iOptions: _deviceOnlyOptions);
      return;
    }
    final sorted = identities.toList()..sort();
    await _storage.write(
      key: _totpIndexKey,
      value: jsonEncode(sorted),
      iOptions: _deviceOnlyOptions,
    );
  }

  Future<bool> hasTotpSecret({
    required String ipAddress,
    required String username,
  }) async {
    if (!supportsFaceIdTotp) return false;
    final identity = _totpIdentity(ipAddress, username);
    return await _storage.read(
          key: _totpMarkerKey(identity),
          iOptions: _deviceOnlyOptions,
        ) ==
        '1';
  }

  Future<String?> readTotpSecret({
    required String ipAddress,
    required String username,
  }) async {
    if (!supportsFaceIdTotp) return null;
    final identity = _totpIdentity(ipAddress, username);
    return _storage.read(
      key: _totpSecretKey(identity),
      iOptions: _totpSecretOptions,
    );
  }

  Future<void> saveTotpSecret({
    required String ipAddress,
    required String username,
    required String secret,
  }) async {
    if (!supportsFaceIdTotp) {
      throw UnsupportedError('Face ID 动态码仅支持 iOS。');
    }
    final identity = _totpIdentity(ipAddress, username);
    await _storage.write(
      key: _totpSecretKey(identity),
      value: secret,
      iOptions: _totpSecretOptions,
    );
    try {
      await _storage.write(
        key: _totpMarkerKey(identity),
        value: '1',
        iOptions: _deviceOnlyOptions,
      );
      final identities = await _getTotpIdentityIndex();
      identities.add(identity);
      await _saveTotpIdentityIndex(identities);
    } catch (_) {
      await _storage.delete(
        key: _totpSecretKey(identity),
        iOptions: _totpSecretOptions,
      );
      rethrow;
    }
  }

  Future<void> deleteTotpSecret({
    required String ipAddress,
    required String username,
  }) async {
    final identity = _totpIdentity(ipAddress, username);
    await _deleteTotpIdentity(identity);
    final identities = await _getTotpIdentityIndex();
    identities.remove(identity);
    await _saveTotpIdentityIndex(identities);
  }

  Future<void> _deleteTotpIdentity(String identity) async {
    await _storage.delete(
      key: _totpSecretKey(identity),
      iOptions: _totpSecretOptions,
    );
    await _storage.delete(
      key: _totpMarkerKey(identity),
      iOptions: _deviceOnlyOptions,
    );
  }

  Future<void> saveLuciSession({
    required String ipAddress,
    required bool useHttps,
    required String token,
    required String cookieName,
  }) async {
    try {
      await _storage.write(
        key: _luciSessionKey(ipAddress, useHttps),
        value: jsonEncode({
          'version': 1,
          'token': token,
          'cookieName': cookieName,
          'useHttps': useHttps,
        }),
      );
    } catch (e, stack) {
      Logger.exception('Failed to save LuCI session', e, stack);
      rethrow;
    }
  }

  Future<LuciSession?> getLuciSession({
    required String ipAddress,
    required bool useHttps,
  }) async {
    try {
      final value = await _storage.read(
        key: _luciSessionKey(ipAddress, useHttps),
      );
      if (value == null || value.isEmpty) return null;
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final token = decoded['token']?.toString();
      final cookieName = decoded['cookieName']?.toString();
      if (token == null ||
          token.isEmpty ||
          cookieName == null ||
          cookieName.isEmpty ||
          decoded['useHttps'] != useHttps) {
        return null;
      }
      return LuciSession(
        token: token,
        cookieName: cookieName,
        useHttps: useHttps,
      );
    } catch (e, stack) {
      Logger.exception('Failed to read LuCI session', e, stack);
      return null;
    }
  }

  Future<void> deleteLuciSession({
    required String ipAddress,
    required bool useHttps,
  }) async {
    try {
      await _storage.delete(key: _luciSessionKey(ipAddress, useHttps));
    } catch (e, stack) {
      Logger.exception('Failed to delete LuCI session', e, stack);
    }
  }

  // Single source of truth for session credential keys: read, write and
  // clear paths all reference these constants so a new key cannot be added
  // to one path and omitted from logout cleanup.
  static const String _keyIpAddress = 'ipAddress';
  static const String _keyUsername = 'username';
  static const String _keyPassword = 'password';
  static const String _keyUseHttps = 'useHttps';

  static const List<String> _credentialKeys = [
    _keyIpAddress,
    _keyUsername,
    _keyPassword,
    _keyUseHttps,
  ];

  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {
    try {
      await _storage.write(key: _keyIpAddress, value: ipAddress);
      await _storage.write(key: _keyUsername, value: username);
      await _storage.write(key: _keyPassword, value: password);
      await _storage.write(key: _keyUseHttps, value: useHttps.toString());
    } catch (e, stack) {
      Logger.exception('Failed to save credentials', e, stack);
      rethrow;
    }
  }

  Future<Map<String, String?>> getCredentials() async {
    try {
      final ipAddress = await _storage.read(key: _keyIpAddress);
      final username = await _storage.read(key: _keyUsername);
      final password = await _storage.read(key: _keyPassword);
      final useHttps = await _storage.read(key: _keyUseHttps);
      return {
        'ipAddress': ipAddress,
        'username': username,
        'password': password,
        'useHttps': useHttps,
      };
    } catch (e, stack) {
      Logger.exception('Failed to get credentials', e, stack);
      return {
        'ipAddress': null,
        'username': null,
        'password': null,
        'useHttps': null,
      };
    }
  }

  /// Clears session credentials. Every key is attempted even if one delete
  /// fails; the first failure is rethrown afterwards so callers (logout)
  /// can observe that cleanup was incomplete.
  Future<void> clearCredentials() async {
    Object? firstFailure;
    StackTrace? firstTrace;
    for (final key in _credentialKeys) {
      try {
        await _storage.delete(key: key);
      } catch (error, stack) {
        firstFailure ??= error;
        firstTrace ??= stack;
        Logger.exception('Failed to clear credential key: $key', error, stack);
      }
    }
    if (firstFailure != null) {
      // Preserve the original trace of the first deletion failure.
      Error.throwWithStackTrace(firstFailure, firstTrace ?? StackTrace.current);
    }
  }

  Future<String?> readValue(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, stack) {
      Logger.exception('Failed to read value for key: $key', e, stack);
      return null;
    }
  }

  Future<void> writeValue(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e, stack) {
      Logger.exception('Failed to write value for key: $key', e, stack);
      rethrow;
    }
  }

  Future<void> deleteValue(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, stack) {
      Logger.exception('Failed to delete value for key: $key', e, stack);
      rethrow;
    }
  }

  static String normalizeClientMac(String macAddress) =>
      macAddress.trim().toUpperCase().replaceAll('-', ':');

  Future<Map<String, String>> getClientAliases() async {
    try {
      final encoded = await _storage.read(key: _clientAliasesKey);
      if (encoded == null || encoded.isEmpty) return {};
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return {};

      final aliases = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.value is! String) continue;
        final mac = normalizeClientMac(entry.key.toString());
        final alias = (entry.value as String).trim();
        if (mac.isNotEmpty && alias.isNotEmpty) aliases[mac] = alias;
      }
      return aliases;
    } catch (error, stack) {
      Logger.exception('Failed to get client aliases', error, stack);
      return {};
    }
  }

  Future<void> setClientAlias({
    required String macAddress,
    required String alias,
  }) async {
    final mac = normalizeClientMac(macAddress);
    if (mac.isEmpty) return;

    final aliases = await getClientAliases();
    final normalizedAlias = alias.trim();
    if (normalizedAlias.isEmpty) {
      aliases.remove(mac);
    } else {
      aliases[mac] = normalizedAlias;
    }

    if (aliases.isEmpty) {
      await _storage.delete(key: _clientAliasesKey);
    } else {
      await _storage.write(key: _clientAliasesKey, value: jsonEncode(aliases));
    }
  }

  Future<void> saveRouters(List<Router> routers) async {
    try {
      final jsonList = routers.map((r) => r.toJson()).toList();
      await _storage.write(key: _routersKey, value: jsonEncode(jsonList));
    } catch (e, stack) {
      Logger.exception('Failed to save routers', e, stack);
      rethrow;
    }
  }

  Future<List<Router>> getRouters() async {
    try {
      final jsonString = await _storage.read(key: _routersKey);
      if (jsonString == null || jsonString.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => Router.fromJson(e)).toList();
    } catch (e, stack) {
      Logger.exception('Failed to get routers', e, stack);
      return [];
    }
  }

  Future<void> deleteRouter(String id) async {
    try {
      final routers = await getRouters();
      final updated = routers.where((r) => r.id != id).toList();
      await saveRouters(updated);
    } catch (e, stack) {
      Logger.exception('Failed to delete router: $id', e, stack);
      rethrow;
    }
  }

  Future<void> updateRouter(Router router) async {
    try {
      final routers = await getRouters();
      final updated = [
        for (final r in routers)
          if (r.id == router.id) router else r,
      ];
      await saveRouters(updated);
    } catch (e, stack) {
      Logger.exception('Failed to update router: ${router.id}', e, stack);
      rethrow;
    }
  }

  Future<void> saveSelectedRouterId(String? id) async {
    try {
      if (id == null) {
        await _storage.delete(key: _selectedRouterKey);
      } else {
        await _storage.write(key: _selectedRouterKey, value: id);
      }
    } catch (e, stack) {
      Logger.exception('Failed to save selected router ID', e, stack);
      rethrow;
    }
  }

  Future<String?> getSelectedRouterId() async {
    try {
      return await _storage.read(key: _selectedRouterKey);
    } catch (e, stack) {
      Logger.exception('Failed to get selected router ID', e, stack);
      return null;
    }
  }
}
