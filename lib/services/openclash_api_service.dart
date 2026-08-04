import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:luci_mobile/models/openclash.dart';
import 'package:luci_mobile/services/luci_auth_protocol.dart';
import 'package:luci_mobile/services/openclash_api_protocol.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

class OpenClashApiException implements Exception {
  final String message;

  const OpenClashApiException(this.message);

  @override
  String toString() => message;
}

class OpenClashApiService {
  final HttpClientManager _httpClientManager;

  OpenClashApiService({HttpClientManager? httpClientManager})
    : _httpClientManager = httpClientManager ?? HttpClientManager();

  Uri _uri(String host, bool useHttps, String path) =>
      Uri.parse('${useHttps ? 'https' : 'http'}://$host$path');

  Future<Map<String, dynamic>> _send(
    String host,
    bool useHttps,
    OpenClashHttpRequest request, {
    BuildContext? context,
    Duration receiveTimeout = const Duration(seconds: 15),
  }) async {
    final client = _httpClientManager.getClient(
      host,
      useHttps,
      context: context,
    );
    final options = Options(
      headers: request.headers,
      contentType: request.headers['Content-Type'],
      followRedirects: false,
      receiveTimeout: receiveTimeout,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 600,
    );
    final uri = _uri(host, useHttps, request.path);
    final Response<dynamic> response;
    if (request.method == OpenClashHttpMethod.get) {
      response = await client.getUri<dynamic>(uri, options: options);
    } else {
      response = await client.postUri<dynamic>(
        uri,
        data: request.fields,
        options: options,
      );
    }

    final status = response.statusCode ?? 0;
    if (status == 302 || status == 401 || status == 403) {
      throw const LuciSessionExpiredException();
    }
    if (status == 404) {
      throw const OpenClashApiException('路由器尚未安装 LuCI Mobile Mihomo 模块。');
    }
    final decoded = _decodeMap(response.data);
    if (status < 200 || status >= 300) {
      throw OpenClashApiException(
        decoded['error']?.toString() ?? 'OpenClash 请求失败（HTTP $status）。',
      );
    }
    return decoded;
  }

  static Map<String, dynamic> _decodeMap(dynamic data) {
    dynamic decoded = data;
    if (data is String && data.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        throw const OpenClashApiException('路由器返回了无效数据。');
      }
    }
    if (decoded == null || decoded == '') return const {};
    if (decoded is! Map) {
      throw const OpenClashApiException('路由器返回了无效数据。');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<OpenClashOverview> fetchOverview({
    required String host,
    required bool useHttps,
    required LuciSession session,
    BuildContext? context,
  }) async {
    final json = await _send(
      host,
      useHttps,
      OpenClashApiProtocol.overview(session),
      context: context,
    );
    return OpenClashOverview.fromJson(json);
  }

  Future<OpenClashProxySnapshot> fetchProxies({
    required String host,
    required bool useHttps,
    required LuciSession session,
    BuildContext? context,
  }) async {
    final json = await _send(
      host,
      useHttps,
      OpenClashApiProtocol.proxies(session),
      context: context,
    );
    return OpenClashProxySnapshot.fromJson(json);
  }

  Future<void> selectProxy({
    required String host,
    required bool useHttps,
    required LuciSession session,
    required String group,
    required String proxy,
    BuildContext? context,
  }) async {
    await _send(
      host,
      useHttps,
      OpenClashApiProtocol.selectProxy(session, group: group, proxy: proxy),
      context: context,
    );
  }

  Future<Map<String, dynamic>> testDelay({
    required String host,
    required bool useHttps,
    required LuciSession session,
    required String kind,
    required String name,
    String? provider,
    BuildContext? context,
  }) {
    return _send(
      host,
      useHttps,
      OpenClashApiProtocol.testDelay(
        session,
        kind: kind,
        name: name,
        provider: provider,
      ),
      context: context,
      receiveTimeout: const Duration(seconds: 20),
    );
  }

  Future<OpenClashMode> switchMode({
    required String host,
    required bool useHttps,
    required LuciSession session,
    required OpenClashMode mode,
    BuildContext? context,
  }) async {
    final json = await _send(
      host,
      useHttps,
      OpenClashApiProtocol.switchMode(session, mode),
      context: context,
    );
    return OpenClashMode.fromApiValue(json['mode']);
  }
}
