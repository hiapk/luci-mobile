import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Actions use the dependency-compatible Flutter version', () {
    const expectedVersion = '3.47.1';
    const workflowPaths = [
      '.github/workflows/ci.yml',
      '.github/workflows/ios-ipa.yml',
      '.github/workflows/release.yml',
    ];
    final versionPattern = RegExp(r'''flutter-version:\s*['"]?([^'"\s]+)''');

    for (final path in workflowPaths) {
      final contents = File(path).readAsStringSync();
      final versions = versionPattern
          .allMatches(contents)
          .map((match) => match.group(1))
          .whereType<String>()
          .toSet();

      expect(versions, isNotEmpty, reason: '$path must pin Flutter');
      expect(
        versions,
        {expectedVersion},
        reason:
            '$path must use Flutter $expectedVersion so pub get can resolve '
            'the current dependency SDK constraints',
      );
    }
  });
}
