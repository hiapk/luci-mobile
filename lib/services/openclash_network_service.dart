import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:luci_mobile/models/openclash.dart';

typedef OpenClashLatencyProbe = Future<int?> Function(Uri target);

class OpenClashNetworkService {
  static final Uri _ipSbEndpoint = Uri.parse('https://api.ip.sb/geoip');
  static final List<(String, Uri)> _latencyTargets = [
    ('Google', Uri.parse('https://www.google.com/generate_204')),
    ('Cloudflare', Uri.parse('https://cp.cloudflare.com/generate_204')),
    ('GitHub', Uri.parse('https://github.com')),
  ];

  final Dio _dio;
  final OpenClashLatencyProbe? _latencyProbe;

  OpenClashNetworkService({Dio? dio, OpenClashLatencyProbe? latencyProbe})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
            ),
          ),
      _latencyProbe = latencyProbe;

  Future<OpenClashIpInfo> fetchIpInfo() async {
    final response = await _dio.getUri<dynamic>(
      _ipSbEndpoint,
      options: Options(
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );
    dynamic data = response.data;
    if (data is String) data = jsonDecode(data);
    if (data is! Map) throw const FormatException('IP.SB 返回了无效数据。');
    final info = OpenClashIpInfo.fromIpSbJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (info.ip.isEmpty) throw const FormatException('IP.SB 未返回 IP 地址。');
    return info;
  }

  Future<List<OpenClashLatencyResult>> testLatencies() {
    return Future.wait(
      _latencyTargets.map((target) async {
        final delay = await (_latencyProbe ?? _measureLatency)(target.$2);
        return OpenClashLatencyResult(
          name: target.$1,
          target: target.$2,
          delay: delay,
        );
      }),
    );
  }

  Future<int?> _measureLatency(Uri target) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _dio.headUri<dynamic>(
        target,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null,
        ),
      );
      return stopwatch.elapsedMilliseconds;
    } on DioException {
      return null;
    } finally {
      stopwatch.stop();
    }
  }
}
