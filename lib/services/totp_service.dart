import 'package:otp/otp.dart';

typedef TotpClock = DateTime Function();
typedef TotpDelay = Future<void> Function(Duration duration);

class TotpService {
  TotpService({TotpClock? now, TotpDelay? delay})
    : _now = now ?? DateTime.now,
      _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  static const int digits = 6;
  static const int periodSeconds = 30;
  static const int minimumSecretCharacters = 16;
  static const int boundaryGuardSeconds = 3;

  final TotpClock _now;
  final TotpDelay _delay;

  String normalizeSecret(String input) {
    var candidate = input.trim();
    if (candidate.toLowerCase().startsWith('otpauth://')) {
      final uri = Uri.tryParse(candidate);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'otpauth' ||
          uri.host.toLowerCase() != 'totp') {
        throw const FormatException('仅支持 TOTP 类型的 otpauth 地址。');
      }

      final algorithm = (uri.queryParameters['algorithm'] ?? 'SHA1')
          .toUpperCase();
      final parsedDigits = int.tryParse(uri.queryParameters['digits'] ?? '6');
      final parsedPeriod = int.tryParse(uri.queryParameters['period'] ?? '30');
      if (algorithm != 'SHA1' ||
          parsedDigits != digits ||
          parsedPeriod != periodSeconds) {
        throw const FormatException('该动态码参数与当前 LuCI 2FA 配置不兼容。');
      }
      candidate = uri.queryParameters['secret'] ?? '';
    }

    final normalized = candidate
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'=+$'), '')
        .toUpperCase();
    if (normalized.length < minimumSecretCharacters ||
        !RegExp(r'^[A-Z2-7]+$').hasMatch(normalized)) {
      throw const FormatException('请输入有效的 Base32 TOTP 密钥。');
    }
    return normalized;
  }

  String generateAt(String secret, DateTime timestamp) {
    final normalized = normalizeSecret(secret);
    return OTP.generateTOTPCodeString(
      normalized,
      timestamp.millisecondsSinceEpoch,
      length: digits,
      interval: periodSeconds,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }

  int remainingSecondsAt(DateTime timestamp) {
    final elapsed = timestamp.millisecondsSinceEpoch ~/ 1000;
    return periodSeconds - (elapsed % periodSeconds);
  }

  Future<String> generateForLogin(String secret) async {
    final normalized = normalizeSecret(secret);
    var timestamp = _now();
    final remaining = remainingSecondsAt(timestamp);
    if (remaining <= boundaryGuardSeconds) {
      await _delay(Duration(seconds: remaining + 1));
      timestamp = _now();
    }
    return generateAt(normalized, timestamp);
  }
}
