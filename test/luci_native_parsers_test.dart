import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/luci_native_parsers.dart';

void main() {
  group('Docker JSON lines parser', () {
    test('parses valid records and skips command noise', () {
      const output = '''
warning: daemon response delayed
{"ID":"abc123","Names":"web","State":"running"}
{"ID":"def456","Names":"worker","State":"exited"}
''';

      expect(parseJsonLines(output), [
        {'ID': 'abc123', 'Names': 'web', 'State': 'running'},
        {'ID': 'def456', 'Names': 'worker', 'State': 'exited'},
      ]);
    });
  });

  group('package control parser', () {
    test('parses installed state and folded descriptions', () {
      const output = '''
Package: luci-base
Version: 1.2.3
Status: install user installed
Installed-Size: 4096
Description: LuCI base package
 with a continued description

Package: luci-app-test
Version: 2.0.0
Size: 2048
Description: Test application

''';

      final packages = parsePackageControlRecords(output);

      expect(packages, hasLength(2));
      expect(packages[0].name, 'luci-base');
      expect(packages[0].installed, isTrue);
      expect(packages[0].installedSize, 4096);
      expect(
        packages[0].description,
        'LuCI base package\nwith a continued description',
      );
      expect(packages[1].installed, isFalse);
      expect(packages[1].size, 2048);
    });
  });

  group('mount usage parser', () {
    test('derives used bytes from size and available bytes', () {
      expect(mountUsedBytes(const {'size': 1000, 'avail': 350}), 650);
    });

    test('prefers an explicit used value when present', () {
      expect(
        mountUsedBytes(const {'size': 1000, 'avail': 350, 'used': 700}),
        700,
      );
    });
  });
}
