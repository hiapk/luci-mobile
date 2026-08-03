import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LuciWebViewScreen extends ConsumerStatefulWidget {
  final String title;
  final Uri targetUri;
  final model.Router router;
  final String cookieName;
  final String token;

  const LuciWebViewScreen({
    super.key,
    required this.title,
    required this.targetUri,
    required this.router,
    required this.cookieName,
    required this.token,
  });

  @override
  ConsumerState<LuciWebViewScreen> createState() => _LuciWebViewScreenState();
}

class _LuciWebViewScreenState extends ConsumerState<LuciWebViewScreen> {
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  late final WebViewController _controller;
  late String _cookieName;
  late String _token;
  int _progress = 0;
  String? _loadError;
  bool _handlingSessionExpiry = false;

  @override
  void initState() {
    super.initState();
    _cookieName = widget.cookieName;
    _token = widget.token;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loadError = null;
                _progress = 0;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _progress = 100);
            final uri = Uri.tryParse(url);
            if (uri != null && _isLoginPage(uri)) {
              unawaited(_renewSession());
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false && mounted) {
              setState(() => _loadError = error.description);
            }
          },
          onNavigationRequest: _handleNavigation,
        ),
      );
    unawaited(_loadTarget());
  }

  Future<void> _loadTarget() async {
    await _setSessionCookie();
    await _controller.loadRequest(widget.targetUri);
  }

  Future<void> _setSessionCookie() {
    return _cookieManager.setCookie(
      WebViewCookie(
        name: _cookieName,
        value: _token,
        domain: widget.targetUri.host,
        path: '/cgi-bin/luci',
      ),
    );
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (_isSameOrigin(uri, widget.targetUri)) {
      return NavigationDecision.navigate;
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
    return NavigationDecision.prevent;
  }

  bool _isSameOrigin(Uri a, Uri b) {
    int effectivePort(Uri uri) {
      if (uri.hasPort) return uri.port;
      return uri.scheme == 'https' ? 443 : 80;
    }

    return a.scheme == b.scheme &&
        a.host == b.host &&
        effectivePort(a) == effectivePort(b);
  }

  bool _isLoginPage(Uri uri) {
    return _isSameOrigin(uri, widget.targetUri) &&
        (uri.path == '/cgi-bin/luci' || uri.path == '/cgi-bin/luci/');
  }

  Future<void> _renewSession() async {
    if (_handlingSessionExpiry || !mounted) return;
    _handlingSessionExpiry = true;

    while (mounted) {
      final otp = await _askForOtp();
      if (!mounted) return;
      if (otp == null) {
        Navigator.of(context).pop();
        return;
      }

      final appState = ref.read(appStateProvider);
      final success = await appState.login(
        widget.router.ipAddress,
        widget.router.username,
        widget.router.password,
        widget.router.useHttps,
        otp: otp,
        fromRouter: true,
        context: context,
      );
      if (!mounted) return;
      if (success && appState.sysauth != null) {
        _token = appState.sysauth!;
        _cookieName =
            appState.authCookieName ??
            (widget.router.useHttps ? 'sysauth_https' : 'sysauth_http');
        await _setSessionCookie();
        await _controller.loadRequest(widget.targetUri);
        _handlingSessionExpiry = false;
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appState.errorMessage ?? '重新登录失败，请重试。')),
      );
    }
  }

  Future<String?> _askForOtp() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('会话已过期'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '两步验证码',
                hintText: '请输入 6 位验证码',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setDialogState(() {}),
              onSubmitted: (value) {
                if (value.length == 6) Navigator.of(dialogContext).pop(value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: controller.text.length == 6
                    ? () => Navigator.of(dialogContext).pop(controller.text)
                    : null,
                child: const Text('重新登录'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: '返回',
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => _controller.goForward(),
            icon: const Icon(Icons.arrow_forward_ios_rounded),
            tooltip: '前进',
          ),
          IconButton(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress / 100,
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loadError != null)
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 48),
                            const SizedBox(height: 16),
                            Text(_loadError!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _controller.reload(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
