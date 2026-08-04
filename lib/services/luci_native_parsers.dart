import 'dart:convert';

List<Map<String, dynamic>> parseJsonLines(String output) {
  final records = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(output)) {
    final value = line.trim();
    if (!value.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        records.add(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on FormatException {
      // Command warnings may be interleaved with JSON line output.
    }
  }
  return records;
}

num mountUsedBytes(Map<dynamic, dynamic> mount) {
  final explicit = num.tryParse(mount['used']?.toString() ?? '');
  if (explicit != null) return explicit;
  final size = num.tryParse(mount['size']?.toString() ?? '') ?? 0;
  final available =
      num.tryParse((mount['avail'] ?? mount['free'])?.toString() ?? '') ?? 0;
  return (size - available).clamp(0, size);
}

class RouterPackageInfo {
  final String name;
  final String version;
  final String description;
  final bool installed;
  final bool essential;
  final int? size;
  final int? installedSize;
  final List<String> depends;

  const RouterPackageInfo({
    required this.name,
    required this.version,
    required this.description,
    required this.installed,
    required this.essential,
    required this.size,
    required this.installedSize,
    required this.depends,
  });
}

List<RouterPackageInfo> parsePackageControlRecords(String output) {
  final packages = <RouterPackageInfo>[];
  final fields = <String, String>{};
  String? currentKey;

  void finishRecord() {
    final name = fields['package']?.trim() ?? '';
    if (name.isNotEmpty) {
      final status = (fields['status'] ?? '').split(RegExp(r'\s+'));
      packages.add(
        RouterPackageInfo(
          name: name,
          version: fields['version']?.trim() ?? '',
          description: fields['description']?.trim() ?? '',
          installed: status.contains('installed'),
          essential: fields['essential']?.trim().toLowerCase() == 'yes',
          size: int.tryParse(fields['size']?.trim() ?? ''),
          installedSize: int.tryParse(fields['installed-size']?.trim() ?? ''),
          depends: (fields['depends'] ?? '')
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
        ),
      );
    }
    fields.clear();
    currentKey = null;
  }

  for (final line in const LineSplitter().convert('$output\n')) {
    if (line.trim().isEmpty) {
      finishRecord();
      continue;
    }
    if ((line.startsWith(' ') || line.startsWith('\t')) && currentKey != null) {
      final previous = fields[currentKey!] ?? '';
      fields[currentKey!] = '$previous\n${line.trim()}';
      continue;
    }
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    currentKey = line.substring(0, separator).trim().toLowerCase();
    fields[currentKey!] = line.substring(separator + 1).trim();
  }
  return packages;
}
