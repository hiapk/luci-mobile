import 'dart:async';
import 'dart:convert';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:luci_mobile/models/openclash.dart';

typedef OpenClashLatencyProbe = Future<int?> Function(Uri target);

enum OpenClashIpInfoErrorKind { timeout, httpStatus, invalidResponse, network }

class OpenClashIpInfoException implements Exception {
  final OpenClashIpInfoErrorKind kind;
  final String message;

  const OpenClashIpInfoException(this.kind, this.message);

  @override
  String toString() => message;
}

http.Client _createIpInfoClient() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoClient.defaultSessionConfiguration();
  }
  return http.Client();
}

class OpenClashNetworkService {
  static const defaultIpInfoTimeout = Duration(seconds: 10);
  static final Uri _ipSbEndpoint = Uri.parse('https://api.ip.sb/geoip');
  static final List<(String, Uri)> _latencyTargets = [
    ('Google', Uri.parse('https://www.google.com/generate_204')),
    ('Cloudflare', Uri.parse('https://cp.cloudflare.com/generate_204')),
    ('GitHub', Uri.parse('https://github.com')),
  ];

  final Dio _dio;
  final http.Client _ipInfoClient;
  final Duration _ipInfoTimeout;
  final bool _ownsIpInfoClient;
  final OpenClashLatencyProbe? _latencyProbe;

  OpenClashNetworkService({
    Dio? dio,
    http.Client? ipInfoClient,
    Duration ipInfoTimeout = defaultIpInfoTimeout,
    OpenClashLatencyProbe? latencyProbe,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 5),
             ),
           ),
       _ipInfoClient = ipInfoClient ?? _createIpInfoClient(),
       _ipInfoTimeout = ipInfoTimeout,
       _ownsIpInfoClient = ipInfoClient == null,
       _latencyProbe = latencyProbe;

  Future<OpenClashIpInfo> fetchIpInfo() async {
    try {
      final response = await _ipInfoClient
          .get(_ipSbEndpoint, headers: const {'Accept': 'application/json'})
          .timeout(_ipInfoTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OpenClashIpInfoException(
          OpenClashIpInfoErrorKind.httpStatus,
          'IP.SB 请求失败（HTTP ${response.statusCode}）。',
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) {
        throw const OpenClashIpInfoException(
          OpenClashIpInfoErrorKind.invalidResponse,
          'IP.SB 返回了无效数据。',
        );
      }
      final info = OpenClashIpInfo.fromIpSbJson(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (info.ip.isEmpty) {
        throw const OpenClashIpInfoException(
          OpenClashIpInfoErrorKind.invalidResponse,
          'IP.SB 未返回 IP 地址。',
        );
      }
      return info;
    } on TimeoutException {
      throw OpenClashIpInfoException(
        OpenClashIpInfoErrorKind.timeout,
        'IP.SB 请求超时（${_ipInfoTimeout.inSeconds} 秒）。',
      );
    } on OpenClashIpInfoException {
      rethrow;
    } on FormatException {
      throw const OpenClashIpInfoException(
        OpenClashIpInfoErrorKind.invalidResponse,
        'IP.SB 返回了无法解析的数据。',
      );
    } on http.ClientException catch (error) {
      throw OpenClashIpInfoException(
        OpenClashIpInfoErrorKind.network,
        'IP.SB 网络连接失败：${error.message}',
      );
    } catch (error) {
      throw OpenClashIpInfoException(
        OpenClashIpInfoErrorKind.network,
        'IP.SB 请求失败：$error',
      );
    }
  }

  void dispose() {
    if (_ownsIpInfoClient) _ipInfoClient.close();
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
