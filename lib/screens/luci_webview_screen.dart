import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/state/app_state.dart';
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
  bool _canGoBack = false;
  bool _canGoForward = false;
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
            if (!mounted) return;
            setState(() {
              _loadError = null;
              _progress = 0;
            });
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _progress = 100);
            unawaited(_updateNavigationState());
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
    try {
      await _setSessionCookie();
      await _controller.loadRequest(widget.targetUri);
    } catch (error) {
      if (mounted) setState(() => _loadError = error.toString());
    }
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

  Future<void> _updateNavigationState() async {
    final states = await Future.wait([
      _controller.canGoBack(),
      _controller.canGoForward(),
    ]);
    if (!mounted) return;
    setState(() {
      _canGoBack = states[0];
      _canGoForward = states[1];
    });
  }

  Future<void> _renewSession() async {
    if (_handlingSessionExpiry || !mounted) return;
    _handlingSessionExpiry = true;

    final appState = ref.read(appStateProvider);
    var success = await appState.login(
      widget.router.ipAddress,
      widget.router.username,
      widget.router.password,
      widget.router.useHttps,
      fromRouter: true,
      context: context,
    );
    if (!mounted) return;
    if (success && appState.sysauth != null) {
      await _resumeWithCurrentSession(appState);
      return;
    }
    if (!appState.requiresOtp) {
      await _showLoginError(appState.errorMessage ?? '重新登录失败，请重试。');
      _handlingSessionExpiry = false;
      return;
    }

    while (mounted) {
      final otp = await _askForOtp();
      if (!mounted) return;
      if (otp == null) {
        Navigator.of(context).pop();
        return;
      }

      success = await appState.login(
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
        await _resumeWithCurrentSession(appState);
        return;
      }

      await _showLoginError(appState.errorMessage ?? '重新登录失败，请重试。');
    }
  }

  Future<void> _resumeWithCurrentSession(AppState appState) async {
    _token = appState.sysauth!;
    _cookieName =
        appState.authCookieName ??
        (widget.router.useHttps ? 'sysauth_https' : 'sysauth_http');
    await _setSessionCookie();
    await _controller.loadRequest(widget.targetUri);
    _handlingSessionExpiry = false;
  }

  Future<String?> _askForOtp() async {
    final controller = TextEditingController();
    try {
      return await showCupertinoDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => CupertinoAlertDialog(
            title: const Text('会话已过期'),
            content: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: CupertinoTextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                placeholder: '6 位两步验证码',
                textAlign: TextAlign.center,
                onChanged: (_) => setDialogState(() {}),
                onSubmitted: (value) {
                  if (value.length == 6) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
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

  Future<void> _showLoginError(String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('登录失败'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternally() async {
    final currentUrl = await _controller.currentUrl();
    final uri = currentUrl == null ? null : Uri.tryParse(currentUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final separator = CupertinoColors.separator.resolveFrom(context);
    final toolbarBackground = CupertinoColors.systemBackground.resolveFrom(
      context,
    );
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          children: [
            if (_progress > 0 && _progress < 100)
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _progress / 100,
                  child: const ColoredBox(
                    color: CupertinoColors.activeBlue,
                    child: SizedBox(height: 2),
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loadError != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: CupertinoColors.systemBackground.resolveFrom(
                          context,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_circle,
                                  size: 44,
                                  color: CupertinoColors.systemRed,
                                ),
                                const SizedBox(height: 14),
                                Text(_loadError!, textAlign: TextAlign.center),
                                const SizedBox(height: 18),
                                CupertinoButton.filled(
                                  onPressed: _loadTarget,
                                  child: const Text('重新加载'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: toolbarBackground,
                border: Border(top: BorderSide(color: separator, width: 0.5)),
              ),
              child: SizedBox(
                height: 46,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _WebToolbarButton(
                      label: '关闭',
                      icon: CupertinoIcons.xmark,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    _WebToolbarButton(
                      label: '后退',
                      icon: CupertinoIcons.chevron_back,
                      onPressed: _canGoBack ? _controller.goBack : null,
                    ),
                    _WebToolbarButton(
                      label: '前进',
                      icon: CupertinoIcons.chevron_forward,
                      onPressed: _canGoForward ? _controller.goForward : null,
                    ),
                    _WebToolbarButton(
                      label: '刷新',
                      icon: CupertinoIcons.refresh,
                      onPressed: _controller.reload,
                    ),
                    if (_progress < 100)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: CupertinoActivityIndicator(radius: 9),
                      )
                    else
                      _WebToolbarButton(
                        label: '在浏览器中打开',
                        icon: CupertinoIcons.arrow_up_right_square,
                        onPressed: _openExternally,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebToolbarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _WebToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      child: CupertinoButton(
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: SizedBox(width: 48, height: 44, child: Icon(icon, size: 22)),
      ),
    );
  }
}
