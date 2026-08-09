import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/auth_service.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/totp_service.dart';

const _rfcSecret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

class _FakeApiService extends RealApiService {
  _FakeApiService({this.acceptOtp = true});

  final bool acceptOtp;
  final List<String?> submittedOtps = [];
  int forgottenSessions = 0;

  @override
  Future<LoginResult> loginWithProtocolDetection(
    String ipAddress,
    String username,
    String password,
    bool initialUseHttps, {
    String? otp,
    BuildContext? context,
  }) async {
    submittedOtps.add(otp);
    if (otp == null || otp.isEmpty) {
      return LoginResult(
        token: null,
        cookieName: null,
        actualUseHttps: initialUseHttps,
        status: LuciLoginStatus.otpRequired,
      );
    }
    return LoginResult(
      token: acceptOtp && otp == '287082' ? 'session-token' : null,
      cookieName: acceptOtp && otp == '287082' ? 'sysauth_https' : null,
      actualUseHttps: initialUseHttps,
      status: acceptOtp && otp == '287082'
          ? LuciLoginStatus.success
          : LuciLoginStatus.otpRequired,
    );
  }

  @override
  void forgetSession(String ipAddress, bool useHttps) {
    forgottenSessions += 1;
  }
}

class _FakeSecureStorageService extends SecureStorageService {
  _FakeSecureStorageService({
    this.configured = true,
    this.secret = _rfcSecret,
    this.readError,
  });

  bool configured;
  String? secret;
  final Object? readError;
  int secretReads = 0;
  String? savedSecret;

  @override
  bool get supportsFaceIdTotp => true;

  @override
  Future<LuciSession?> getLuciSession({
    required String ipAddress,
    required bool useHttps,
  }) async => null;

  @override
  Future<bool> hasTotpSecret({
    required String ipAddress,
    required String username,
  }) async => configured;

  @override
  Future<String?> readTotpSecret({
    required String ipAddress,
    required String username,
  }) async {
    secretReads += 1;
    if (readError != null) throw readError!;
    return secret;
  }

  @override
  Future<void> saveTotpSecret({
    required String ipAddress,
    required String username,
    required String secret,
  }) async {
    savedSecret = secret;
    configured = true;
  }

  @override
  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {}

  @override
  Future<void> saveLuciSession({
    required String ipAddress,
    required bool useHttps,
    required String token,
    required String cookieName,
  }) async {}
}

TotpService _fixedTotpService() => TotpService(
  now: () => DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
  delay: (_) async {},
);

void main() {
  test(
    'an expired session unlocks the saved secret only after OTP challenge',
    () async {
      final api = _FakeApiService();
      final storage = _FakeSecureStorageService();
      final auth = RealAuthService(
        api,
        secureStorageService: storage,
        totpService: _fixedTotpService(),
      );

      final success = await auth.tryAutoLogin(
        'router.local',
        'root',
        'password',
        true,
      );

      expect(success, isTrue);
      expect(api.submittedOtps, [null, '287082']);
      expect(storage.secretReads, 1);
      expect(auth.isAuthenticated, isTrue);
    },
  );

  test('does not request Face ID when no secret is configured', () async {
    final api = _FakeApiService();
    final storage = _FakeSecureStorageService(configured: false);
    final auth = RealAuthService(
      api,
      secureStorageService: storage,
      totpService: _fixedTotpService(),
    );

    final success = await auth.tryAutoLogin(
      'router.local',
      'root',
      'password',
      true,
    );

    expect(success, isFalse);
    expect(api.submittedOtps, [null]);
    expect(storage.secretReads, 0);
    expect(auth.requiresOtp, isTrue);
  });

  test('manual OTP never unlocks the saved Face ID secret', () async {
    final api = _FakeApiService();
    final storage = _FakeSecureStorageService();
    final auth = RealAuthService(
      api,
      secureStorageService: storage,
      totpService: _fixedTotpService(),
    );

    await auth.login('router.local', 'root', 'password', true, otp: '000000');

    expect(api.submittedOtps, ['000000']);
    expect(storage.secretReads, 0);
    expect(auth.isAuthenticated, isFalse);
  });

  test('Face ID cancellation falls back to manual OTP', () async {
    final api = _FakeApiService();
    final storage = _FakeSecureStorageService(
      readError: Exception('authentication cancelled'),
    );
    final auth = RealAuthService(
      api,
      secureStorageService: storage,
      totpService: _fixedTotpService(),
    );

    final success = await auth.tryAutoLogin(
      'router.local',
      'root',
      'password',
      true,
    );

    expect(success, isFalse);
    expect(api.submittedOtps, [null]);
    expect(storage.secretReads, 1);
    expect(auth.requiresOtp, isTrue);
  });

  test('a stale enrollment marker falls back to manual OTP', () async {
    final api = _FakeApiService();
    final storage = _FakeSecureStorageService(secret: null);
    final auth = RealAuthService(
      api,
      secureStorageService: storage,
      totpService: _fixedTotpService(),
    );

    final success = await auth.tryAutoLogin(
      'router.local',
      'root',
      'password',
      true,
    );

    expect(success, isFalse);
    expect(api.submittedOtps, [null]);
    expect(storage.secretReads, 1);
    expect(auth.requiresOtp, isTrue);
  });

  test(
    'enrollment saves the normalized secret only after a valid login',
    () async {
      final api = _FakeApiService();
      final storage = _FakeSecureStorageService(configured: false);
      final auth = RealAuthService(
        api,
        secureStorageService: storage,
        totpService: _fixedTotpService(),
      );

      await auth.login(
        'router.local',
        'root',
        'password',
        true,
        totpSecret: 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(api.submittedOtps, ['287082']);
      expect(storage.savedSecret, _rfcSecret);
    },
  );

  test('does not save a secret rejected by the router', () async {
    final api = _FakeApiService(acceptOtp: false);
    final storage = _FakeSecureStorageService(configured: false);
    final auth = RealAuthService(
      api,
      secureStorageService: storage,
      totpService: _fixedTotpService(),
    );

    await auth.login(
      'router.local',
      'root',
      'password',
      true,
      totpSecret: _rfcSecret,
    );

    expect(auth.isAuthenticated, isFalse);
    expect(storage.savedSecret, isNull);
  });
}
