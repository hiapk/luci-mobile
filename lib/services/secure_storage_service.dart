import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import '../utils/logger.dart';
import 'package:luci_mobile/config/app_config.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const String _routersKey = 'routers';
  static const String _selectedRouterKey = 'selectedRouterId';
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

  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {
    try {
      await _storage.write(key: 'ipAddress', value: ipAddress);
      await _storage.write(key: 'username', value: username);
      await _storage.write(key: 'password', value: password);
      await _storage.write(key: 'useHttps', value: useHttps.toString());
    } catch (e, stack) {
      Logger.exception('Failed to save credentials', e, stack);
      rethrow;
    }
  }

  Future<Map<String, String?>> getCredentials() async {
    try {
      final ipAddress = await _storage.read(key: 'ipAddress');
      final username = await _storage.read(key: 'username');
      final password = await _storage.read(key: 'password');
      final useHttps = await _storage.read(key: 'useHttps');
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

  Future<void> clearCredentials() async {
    try {
      // Clear all credentials but preserve reviewer mode flag
      final reviewerMode = await _storage.read(key: AppConfig.reviewerModeKey);
      final totpIdentities = await _getTotpIdentityIndex();
      for (final identity in totpIdentities) {
        await _deleteTotpIdentity(identity);
      }
      await _storage.deleteAll();
      // Restore reviewer mode flag if it was set
      if (reviewerMode != null) {
        await _storage.write(
          key: AppConfig.reviewerModeKey,
          value: reviewerMode,
        );
      }
    } catch (e, stack) {
      Logger.exception('Failed to clear credentials', e, stack);
      // Don't rethrow as this is often called during cleanup
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
