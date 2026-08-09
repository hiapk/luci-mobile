import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/totp_service.dart';

void main() {
  const rfcSecret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

  group('TOTP input', () {
    test('normalizes a Base32 secret without weakening validation', () {
      final service = TotpService();

      expect(
        service.normalizeSecret('gezd gnbv gy3t qojq gezd gnbv gy3t qojq===='),
        rfcSecret,
      );
      expect(
        () => service.normalizeSecret('not-a-base32-secret'),
        throwsFormatException,
      );
    });

    test('accepts only the LuCI-compatible otpauth parameters', () {
      final service = TotpService();

      expect(
        service.normalizeSecret(
          'otpauth://totp/OpenWrt:root?secret=$rfcSecret'
          '&algorithm=SHA1&digits=6&period=30',
        ),
        rfcSecret,
      );
      expect(
        () => service.normalizeSecret(
          'otpauth://totp/OpenWrt:root?secret=$rfcSecret&algorithm=SHA256',
        ),
        throwsFormatException,
      );
      expect(
        () => service.normalizeSecret(
          'otpauth://hotp/OpenWrt:root?secret=$rfcSecret&counter=1',
        ),
        throwsFormatException,
      );
    });
  });

  group('TOTP generation', () {
    test('matches the RFC 6238 SHA-1 vector reduced to six digits', () {
      final service = TotpService();

      expect(
        service.generateAt(
          rfcSecret,
          DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
        ),
        '287082',
      );
    });

    test(
      'waits for the next window when the current code is expiring',
      () async {
        var now = DateTime.fromMillisecondsSinceEpoch(29000, isUtc: true);
        final waits = <Duration>[];
        final service = TotpService(
          now: () => now,
          delay: (duration) async {
            waits.add(duration);
            now = now.add(duration);
          },
        );

        final code = await service.generateForLogin(rfcSecret);

        expect(waits, const [Duration(seconds: 2)]);
        expect(code, service.generateAt(rfcSecret, now));
        expect(
          code,
          isNot(
            service.generateAt(
              rfcSecret,
              DateTime.fromMillisecondsSinceEpoch(29000, isUtc: true),
            ),
          ),
        );
      },
    );
  });
}
