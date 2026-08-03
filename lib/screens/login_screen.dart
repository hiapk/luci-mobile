import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/url_parser.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _usernameController = TextEditingController(text: 'root');
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isCheckingAutoLogin = true;
  bool _passwordVisible = false;
  late AnimationController _logoAnimController;
  late AnimationController _progressAnimController;
  bool _isActivatingReviewerMode = false;
  @override
  void initState() {
    super.initState();
    _checkReviewerModeAndAutoLogin();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progressAnimController = AnimationController(
      vsync: this,
      duration: AppConfig.reviewerModeActivationDuration,
    );
    _logoAnimController.forward();
  }

  Future<void> _checkReviewerModeAndAutoLogin() async {
    // Check if reviewer mode is enabled
    final secureStorage = SecureStorageService();
    final reviewerModeEnabled = await secureStorage.readValue(
      AppConfig.reviewerModeKey,
    );

    if (reviewerModeEnabled == 'true' && mounted) {
      // Navigate directly to main screen in reviewer mode
      unawaited(Navigator.of(context).pushReplacementNamed('/'));
    } else {
      // Try auto login
      unawaited(_tryAutoLogin());
    }
  }

  void _startReviewerModeActivation() {
    setState(() {
      _isActivatingReviewerMode = true;
    });

    // Start progress animation
    _progressAnimController.forward();

    // Start a timer to check if the user has held for 5 seconds
    Future.delayed(AppConfig.reviewerModeActivationDuration, () {
      if (_isActivatingReviewerMode && mounted) {
        _showReviewerModeDialog();
      }
    });
  }

  void _cancelReviewerModeActivation() {
    setState(() {
      _isActivatingReviewerMode = false;
    });
    // Reset progress animation
    _progressAnimController.reset();
  }

  void _showReviewerModeDialog() {
    _confirmationController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('启用演示模式？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('演示模式会跳过身份验证，并使用模拟数据展示应用功能。'),
              const SizedBox(height: 16),
              const Text(
                '请输入“REVIEWER”确认：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmationController,
                decoration: const InputDecoration(
                  hintText: '输入 REVIEWER',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _confirmationController.text == 'REVIEWER'
                  ? () {
                      Navigator.of(context).pop();
                      _activateReviewerMode();
                    }
                  : null,
              child: const Text('启用'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activateReviewerMode() async {
    final appState = ref.read(appStateProvider);
    await appState.setReviewerMode(true);

    if (mounted) {
      unawaited(Navigator.of(context).pushReplacementNamed('/'));
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _confirmationController.dispose();
    _logoAnimController.dispose();
    _progressAnimController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final appState = ref.read(appStateProvider);
    final success = await appState.tryAutoLogin(context: context);
    if (success && mounted) {
      unawaited(Navigator.of(context).pushReplacementNamed('/'));
    } else {
      final credentials = await SecureStorageService().getCredentials();
      if (!mounted) return;
      final address = credentials['ipAddress'];
      final username = credentials['username'];
      final password = credentials['password'];
      final useHttps = credentials['useHttps'] == 'true';
      if (address != null) {
        _ipController.text = '${useHttps ? 'https' : 'http'}://$address';
      }
      if (username != null) _usernameController.text = username;
      if (password != null) _passwordController.text = password;
      if (mounted) {
        setState(() {
          _isCheckingAutoLogin = false;
        });
      }
    }
  }

  Future<void> _connect() async {
    if (_formKey.currentState!.validate()) {
      final appState = ref.read(appStateProvider);
      final input = _ipController.text.trim();
      final user = _usernameController.text;
      final pass = _passwordController.text;
      final otp = _otpController.text;

      // Parse the input to extract host, port, and protocol
      final parsedUrl = UrlParser.parse(input);

      if (!parsedUrl.isValid) {
        // Show error message
        appState.setError(parsedUrl.error ?? '地址格式不正确');
        return;
      }

      // Use the parsed values
      final success = await appState.login(
        parsedUrl.hostWithPort,
        user,
        pass,
        parsedUrl.useHttps,
        otp: otp,
        fromRouter: false,
        context: context,
      );

      if (success && mounted) {
        unawaited(Navigator.of(context).pushReplacementNamed('/'));
      }
    }
  }

  Future<void> _openGitHubIssues() async {
    final url = AppConfig.githubIssuesUrl;
    final success = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('无法打开 GitHub 问题页面'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAutoLogin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Modern gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.18),
                  colorScheme.primaryContainer.withValues(alpha: 0.22),
                  colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        GestureDetector(
                          onLongPress: () {
                            _startReviewerModeActivation();
                          },
                          onLongPressUp: () {
                            _cancelReviewerModeActivation();
                          },
                          child: Column(
                            children: [
                              Column(
                                children: [
                                  Text(
                                    'LuCI 路由助手',
                                    style: textTheme.headlineLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '连接并管理 OpenWrt 路由器',
                                    style: textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '快速、安全、开源',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _isActivatingReviewerMode
                                    ? Padding(
                                        key: const ValueKey('progress'),
                                        padding: const EdgeInsets.only(top: 24),
                                        child: AnimatedBuilder(
                                          animation: _progressAnimController,
                                          builder: (context, child) {
                                            return Column(
                                              children: [
                                                Text(
                                                  '长按以启用演示模式…',
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            colorScheme.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                      ),
                                                ),
                                                const SizedBox(height: 12),
                                                Container(
                                                  width: 280,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    color: colorScheme
                                                        .surfaceContainerHighest
                                                        .withValues(alpha: 0.4),
                                                    border: Border.all(
                                                      color: colorScheme.outline
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: LinearProgressIndicator(
                                                      value:
                                                          _progressAnimController
                                                              .value,
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(
                                                            colorScheme.primary
                                                                .withValues(
                                                                  alpha: 0.9,
                                                                ),
                                                          ),
                                                      minHeight: 6,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      )
                                    : const SizedBox(
                                        key: ValueKey('empty'),
                                        height: 0,
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Glassmorphism card
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Card(
                              elevation: 8,
                              color: colorScheme.surface.withValues(
                                alpha: 0.85,
                              ),
                              shadowColor: colorScheme.primary.withValues(
                                alpha: 0.10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: colorScheme.outline.withValues(
                                    alpha: 0.10,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18.0,
                                  vertical: 16.0,
                                ),
                                child: Form(
                                  key: _formKey,
                                  child: Builder(
                                    builder: (context) {
                                      final appState = ref.watch(
                                        appStateProvider,
                                      );
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Tooltip(
                                            message: '输入路由器 IP、主机名或完整网址',
                                            child: TextFormField(
                                              controller: _ipController,
                                              autofocus: true,
                                              autofillHints: const [
                                                AutofillHints.url,
                                                AutofillHints.username,
                                              ],
                                              decoration: const InputDecoration(
                                                labelText: '路由器地址',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(
                                                  Icons.router_outlined,
                                                ),
                                                helperText:
                                                    '例如 192.168.1.1、router.local:8080 或完整网址',
                                              ),
                                              textInputAction:
                                                  TextInputAction.next,
                                              validator: (value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return '请输入路由器地址';
                                                }
                                                final parsed = UrlParser.parse(
                                                  value,
                                                );
                                                if (!parsed.isValid) {
                                                  return parsed.error ??
                                                      '地址格式不正确';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Tooltip(
                                            message: '输入路由器管理用户名',
                                            child: TextFormField(
                                              controller: _usernameController,
                                              autofillHints: const [
                                                AutofillHints.username,
                                              ],
                                              decoration: const InputDecoration(
                                                labelText: '用户名',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(
                                                  Icons.person_outline,
                                                ),
                                                helperText: '默认通常为 root',
                                              ),
                                              textInputAction:
                                                  TextInputAction.next,
                                              validator: (value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return '请输入用户名';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Tooltip(
                                            message: '输入路由器管理密码',
                                            child: TextFormField(
                                              controller: _passwordController,
                                              obscureText: !_passwordVisible,
                                              autofillHints: const [
                                                AutofillHints.password,
                                              ],
                                              decoration: InputDecoration(
                                                labelText: '密码',
                                                border:
                                                    const OutlineInputBorder(),
                                                prefixIcon: const Icon(
                                                  Icons.lock_outline,
                                                ),
                                                helperText: '路由器管理密码',
                                                suffixIcon: IconButton(
                                                  icon: Icon(
                                                    _passwordVisible
                                                        ? Icons
                                                              .visibility_outlined
                                                        : Icons
                                                              .visibility_off_outlined,
                                                  ),
                                                  onPressed: () => setState(
                                                    () => _passwordVisible =
                                                        !_passwordVisible,
                                                  ),
                                                  tooltip: _passwordVisible
                                                      ? '隐藏密码'
                                                      : '显示密码',
                                                ),
                                              ),
                                              textInputAction:
                                                  TextInputAction.next,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          TextFormField(
                                            controller: _otpController,
                                            keyboardType: TextInputType.number,
                                            maxLength: 6,
                                            autofillHints: const [
                                              AutofillHints.oneTimeCode,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: '两步验证码（可选）',
                                              helperText:
                                                  '启用 2FA 时输入验证器中的 6 位动态码',
                                              border: OutlineInputBorder(),
                                              prefixIcon: Icon(
                                                Icons.pin_outlined,
                                              ),
                                              counterText: '',
                                            ),
                                            textInputAction:
                                                TextInputAction.done,
                                            onFieldSubmitted: (_) => _connect(),
                                            validator: (value) {
                                              final otp = value?.trim() ?? '';
                                              if (otp.isNotEmpty &&
                                                  !RegExp(
                                                    r'^\d{6}$',
                                                  ).hasMatch(otp)) {
                                                return '请输入 6 位数字验证码';
                                              }
                                              return null;
                                            },
                                          ),
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            child: appState.errorMessage != null
                                                ? Padding(
                                                    key: const ValueKey(
                                                      'error',
                                                    ),
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 12.0,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme
                                                            .errorContainer
                                                            .withValues(
                                                              alpha: 1,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.error_outline,
                                                            color: colorScheme
                                                                .onErrorContainer,
                                                          ),
                                                          const SizedBox(
                                                            width: 12,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              appState
                                                                  .errorMessage!,
                                                              style: textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                    color: colorScheme
                                                                        .onErrorContainer,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                          const SizedBox(height: 16),
                                          TweenAnimationBuilder<double>(
                                            duration: const Duration(
                                              milliseconds: 100,
                                            ),
                                            tween: Tween<double>(
                                              begin: 1,
                                              end: appState.isLoading
                                                  ? 0.98
                                                  : 1,
                                            ),
                                            builder: (context, scale, child) {
                                              return Transform.scale(
                                                scale: scale,
                                                child: child,
                                              );
                                            },
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: appState.isLoading
                                                    ? null
                                                    : _connect,
                                                style: ElevatedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 18,
                                                      ),
                                                  textStyle: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  elevation: 4,
                                                  backgroundColor:
                                                      colorScheme.primary,
                                                  foregroundColor:
                                                      colorScheme.onPrimary,
                                                ),
                                                child: appState.isLoading
                                                    ? const SizedBox(
                                                        height: 26,
                                                        width: 26,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 3,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: const [
                                                          Icon(Icons.login),
                                                          SizedBox(width: 12),
                                                          Text('连接'),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Tooltip(
                          message: '打开 GitHub 问题页面获取支持',
                          child: TextButton(
                            onPressed: _openGitHubIssues,
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                            ),
                            child: const Text('需要帮助？'),
                          ),
                        ),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const SizedBox.shrink();
                            }
                            final info = snapshot.data!;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Version ${info.version}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
