import 'dart:math' as math;

enum OpenClashMode {
  rule('rule', '规则'),
  global('global', '全局'),
  direct('direct', '直连');

  final String apiValue;
  final String label;

  const OpenClashMode(this.apiValue, this.label);

  static OpenClashMode fromApiValue(Object? value) {
    return OpenClashMode.values.firstWhere(
      (mode) => mode.apiValue == value?.toString().toLowerCase(),
      orElse: () => OpenClashMode.rule,
    );
  }
}

int _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : 0;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value == 1 || value == '1' || value == 'true') return true;
  if (value == 0 || value == '0' || value == 'false') return false;
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((entry) => entry?.toString() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

List<dynamic> _listValue(Object? value) {
  return value is List ? value : const [];
}

class OpenClashOverview {
  final bool running;
  final String version;
  final OpenClashMode mode;
  final int uploadTotal;
  final int downloadTotal;
  final int connectionCount;
  final int memoryBytes;
  final int timestamp;

  const OpenClashOverview({
    required this.running,
    required this.version,
    required this.mode,
    required this.uploadTotal,
    required this.downloadTotal,
    required this.connectionCount,
    required this.memoryBytes,
    required this.timestamp,
  });

  factory OpenClashOverview.fromJson(Map<String, dynamic> json) {
    return OpenClashOverview(
      running: _boolValue(json['running']),
      version: json['version']?.toString() ?? '',
      mode: OpenClashMode.fromApiValue(json['mode']),
      uploadTotal: _nonNegativeInt(json['uploadTotal']),
      downloadTotal: _nonNegativeInt(json['downloadTotal']),
      connectionCount: _nonNegativeInt(json['connections']),
      memoryBytes: _nonNegativeInt(json['memoryBytes']),
      timestamp: _nonNegativeInt(json['timestamp']),
    );
  }
}

class OpenClashProxyGroup {
  final String name;
  final String type;
  final String current;
  final List<String> members;

  const OpenClashProxyGroup({
    required this.name,
    required this.type,
    required this.current,
    required this.members,
  });

  factory OpenClashProxyGroup.fromJson(Map<String, dynamic> json) {
    return OpenClashProxyGroup(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      current: json['now']?.toString() ?? '',
      members: _stringList(json['all']),
    );
  }
}

class OpenClashProxyNode {
  final String name;
  final String type;
  final int? delay;
  final bool alive;
  final bool udp;
  final bool xudp;
  final bool tfo;
  final List<OpenClashDelayHistoryEntry> history;

  const OpenClashProxyNode({
    required this.name,
    required this.type,
    required this.delay,
    required this.alive,
    required this.udp,
    required this.xudp,
    required this.tfo,
    required this.history,
  });

  factory OpenClashProxyNode.fromJson(Map<String, dynamic> json) {
    final rawDelay = _nonNegativeInt(json['delay']);
    return OpenClashProxyNode(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      delay: rawDelay > 0 ? rawDelay : null,
      alive: _boolValue(json['alive'], fallback: rawDelay > 0),
      udp: _boolValue(json['udp']),
      xudp: _boolValue(json['xudp']),
      tfo: _boolValue(json['tfo']),
      history: _listValue(json['history'])
          .whereType<Map>()
          .map(
            (entry) => OpenClashDelayHistoryEntry.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class OpenClashDelayHistoryEntry {
  final String time;
  final int delay;

  const OpenClashDelayHistoryEntry({required this.time, required this.delay});

  factory OpenClashDelayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return OpenClashDelayHistoryEntry(
      time: json['time']?.toString() ?? '',
      delay: _nonNegativeInt(json['delay']),
    );
  }
}

class OpenClashNodeHealth {
  final int score;
  final DateTime? lastTestTime;

  const OpenClashNodeHealth({required this.score, this.lastTestTime});

  static OpenClashNodeHealth? fromHistory(
    List<OpenClashDelayHistoryEntry> history,
  ) {
    if (history.isEmpty) return null;
    final latencies = history
        .map((entry) => entry.delay)
        .where((delay) => delay > 0)
        .toList(growable: false);
    final latencyScore = _latencyScore(latencies);
    final stabilityScore = _stabilityScore(latencies);
    final successRateScore = (latencies.length / history.length * 100).round();
    final timestamps = history
        .map((entry) => DateTime.tryParse(entry.time)?.toUtc())
        .whereType<DateTime>();
    DateTime? lastTestTime;
    for (final timestamp in timestamps) {
      if (lastTestTime == null || timestamp.isAfter(lastTestTime)) {
        lastTestTime = timestamp;
      }
    }
    return OpenClashNodeHealth(
      score:
          (latencyScore * 0.5 + stabilityScore * 0.3 + successRateScore * 0.2)
              .round(),
      lastTestTime: lastTestTime,
    );
  }

  static int _latencyScore(List<int> latencies) {
    if (latencies.isEmpty) return 0;
    final average =
        latencies.reduce((left, right) => left + right) / latencies.length;
    if (average <= 50) return 100;
    if (average >= 5000) return 0;
    return (100 *
            (1 -
                (math.log(average) - math.log(50)) /
                    (math.log(5000) - math.log(50))))
        .round();
  }

  static int _stabilityScore(List<int> latencies) {
    if (latencies.isEmpty) return 0;
    if (latencies.length == 1) return 50;
    final average =
        latencies.reduce((left, right) => left + right) / latencies.length;
    final variance =
        latencies
            .map((latency) => math.pow(latency - average, 2))
            .reduce((left, right) => left + right) /
        latencies.length;
    final coefficientOfVariation = math.sqrt(variance) / average;
    if (coefficientOfVariation <= 0.1) return 100;
    if (coefficientOfVariation >= 0.5) return 0;
    return (100 * (1 - (coefficientOfVariation - 0.1) / 0.4)).round();
  }
}

class OpenClashProxyProvider {
  final String name;
  final String vehicleType;
  final String updatedAt;
  final List<String> nodeNames;

  const OpenClashProxyProvider({
    required this.name,
    required this.vehicleType,
    required this.updatedAt,
    required this.nodeNames,
  });

  factory OpenClashProxyProvider.fromJson(Map<String, dynamic> json) {
    return OpenClashProxyProvider(
      name: json['name']?.toString() ?? '',
      vehicleType: json['vehicleType']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      nodeNames: _stringList(json['proxies']),
    );
  }
}

class OpenClashProxySnapshot {
  final List<OpenClashProxyGroup> groups;
  final Map<String, OpenClashProxyNode> nodes;
  final List<OpenClashProxyProvider> providers;

  const OpenClashProxySnapshot({
    required this.groups,
    required this.nodes,
    required this.providers,
  });

  factory OpenClashProxySnapshot.fromJson(Map<String, dynamic> json) {
    final groups = _listValue(json['groups'])
        .whereType<Map>()
        .map(
          (entry) => OpenClashProxyGroup.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((group) => group.name.isNotEmpty)
        .toList(growable: false);
    final nodeList = _listValue(json['nodes'])
        .whereType<Map>()
        .map(
          (entry) => OpenClashProxyNode.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((node) => node.name.isNotEmpty);
    final providers = _listValue(json['providers'])
        .whereType<Map>()
        .map(
          (entry) => OpenClashProxyProvider.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((provider) => provider.name.isNotEmpty)
        .toList(growable: false);

    return OpenClashProxySnapshot(
      groups: groups,
      nodes: {for (final node in nodeList) node.name: node},
      providers: providers,
    );
  }

  @override
  String toString() =>
      'OpenClashProxySnapshot(groups: ${groups.length}, '
      'nodes: ${nodes.length}, providers: ${providers.length})';
}

class OpenClashIpInfo {
  final String ip;
  final String country;
  final String city;
  final String asn;
  final String organization;

  const OpenClashIpInfo({
    required this.ip,
    required this.country,
    required this.city,
    required this.asn,
    required this.organization,
  });

  factory OpenClashIpInfo.fromIpSbJson(Map<String, dynamic> json) {
    return OpenClashIpInfo(
      ip: json['ip']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      asn: json['asn']?.toString() ?? '',
      organization: json['asn_organization']?.toString() ?? '',
    );
  }
}

class OpenClashLatencyResult {
  final String name;
  final Uri target;
  final int? delay;

  const OpenClashLatencyResult({
    required this.name,
    required this.target,
    required this.delay,
  });
}
