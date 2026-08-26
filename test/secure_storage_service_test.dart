import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearCredentials removes only active session credentials', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ipAddress': '192.168.1.1',
      'username': 'root',
      'password': 'secret',
      'useHttps': 'true',
      'routers': '[{"id":"router-1"}]',
      'themeMode': 'dark',
      'luciTotpIdentityIndex': '["router-1-root"]',
    });

    final service = SecureStorageService();
    await service.clearCredentials();

    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'ipAddress'), isNull);
    expect(await storage.read(key: 'username'), isNull);
    expect(await storage.read(key: 'password'), isNull);
    expect(await storage.read(key: 'useHttps'), isNull);
    expect(await storage.read(key: 'routers'), '[{"id":"router-1"}]');
    expect(await storage.read(key: 'themeMode'), 'dark');
    expect(
      await storage.read(key: 'luciTotpIdentityIndex'),
      '["router-1-root"]',
    );
  });
}
