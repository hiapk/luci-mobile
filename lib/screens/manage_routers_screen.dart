import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/utils/url_parser.dart';
import 'package:luci_mobile/services/totp_service.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

class ManageRoutersScreen extends ConsumerStatefulWidget {
  const ManageRoutersScreen({super.key});

  @override
  ConsumerState<ManageRoutersScreen> createState() =>
      _ManageRoutersScreenState();
}

class _ManageRoutersScreenState extends ConsumerState<ManageRoutersScreen> {
  String? _switchingRouterId;

  String _truncateAddress(String address) =>
      address.length > 42 ? '${address.substring(0, 39)}…' : address;

  Future<String?> _promptForOtp() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final otp = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要两步验证码'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: '6 位动态验证码',
              border: OutlineInputBorder(),
              counterText: '',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            validator: (value) =>
                RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                ? null
                : '请输入 6 位数字验证码',
            onFieldSubmitted: (value) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('验证'),
          ),
        ],
      ),
    );
    controller.dispose();
    return otp;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final List<model.Router> routers = appState.routers;
    final String? selectedId = appState.selectedRouter?.id;
    return Scaffold(
      appBar: const LuciAppBar(title: '路由器', showBack: true),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => appState.loadRouters(),
              child: routers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Center(
                          child: Text(
                            '尚未添加路由器。',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      children: [
                        ...List.generate(routers.length, (index) {
                          final model.Router router = routers[index];
                          final bool isSelected = router.id == selectedId;
                          final bool isSwitching =
                              router.id == _switchingRouterId;
                          String routerTitle;
                          if (isSelected && appState.dashboardData != null) {
                            final boardInfo =
                                appState.dashboardData?['boardInfo']
                                    as Map<String, dynamic>?;
                            final hostname = boardInfo?['hostname']?.toString();
                            routerTitle =
                                (hostname != null && hostname.isNotEmpty)
                                ? hostname
                                : (router.lastKnownHostname ??
                                      router.ipAddress);
                          } else if (router.lastKnownHostname != null &&
                              router.lastKnownHostname!.isNotEmpty) {
                            routerTitle = router.lastKnownHostname!;
                          } else {
                            routerTitle = router.ipAddress;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: _UnifiedRouterCard(
                              routerTitle: routerTitle,
                              subtitle: router.hasFallback
                                  ? '● ${_truncateAddress(router.activeAddress)}\n'
                                        '○ ${_truncateAddress(router.inactiveAddress!)}'
                                  : '${router.ipAddress} (${router.username})',
                              isSelected: isSelected,
                              isSwitching: isSwitching,
                              onTap: () async {
                                if (!isSelected && !isSwitching) {
                                  setState(() {
                                    _switchingRouterId = router.id;
                                  });

                                  try {
                                    await appState.selectRouter(
                                      router.id,
                                      context: context,
                                    );
                                    if (!context.mounted) return;
                                    if (appState.requiresOtp) {
                                      final otp = await _promptForOtp();
                                      if (otp == null || !context.mounted) {
                                        return;
                                      }
                                      final success = await appState.login(
                                        router.activeAddress,
                                        router.username,
                                        router.password,
                                        router.activeUseHttps,
                                        otp: otp,
                                        fromRouter: true,
                                        alternateAddress:
                                            router.inactiveAddress,
                                        alternateUseHttps:
                                            router.inactiveUseHttps,
                                        activeAddressIndex:
                                            router.activeAddressIndex,
                                        context: context,
                                      );
                                      if (!context.mounted) return;
                                      if (!success) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              appState.errorMessage ??
                                                  '验证码验证失败。',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                    } else if (!appState.isAuthenticated) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            appState.errorMessage ?? '路由器连接失败。',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    // Fetch dashboard data before navigating
                                    await appState.fetchDashboardData();
                                    if (!context.mounted) return;
                                    // Pop all the way back to MainScreen
                                    Navigator.of(
                                      context,
                                    ).popUntil((route) => route.isFirst);
                                    // Set Dashboard tab as active
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          ref
                                              .read(appStateProvider)
                                              .requestTab(0);
                                        });
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _switchingRouterId = null;
                                      });
                                    }
                                  }
                                }
                              },
                              onRemoveFallback: router.hasFallback
                                  ? () async {
                                      await appState.updateRouter(
                                        router.copyWith(clearAlternate: true),
                                      );
                                      if (isSelected && context.mounted) {
                                        await appState.selectRouter(
                                          router.id,
                                          context: context,
                                        );
                                      }
                                    }
                                  : null,
                              onDelete: () async {
                                String routerLabel;
                                if (isSelected &&
                                    appState.dashboardData != null) {
                                  final boardInfo =
                                      appState.dashboardData?['boardInfo']
                                          as Map<String, dynamic>?;
                                  final hostname = boardInfo?['hostname']
                                      ?.toString();
                                  routerLabel =
                                      (hostname != null && hostname.isNotEmpty)
                                      ? hostname
                                      : router.ipAddress;
                                } else {
                                  routerLabel = router.ipAddress;
                                }
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('移除路由器'),
                                    content: Text('确定要移除“$routerLabel”吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('移除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (!context.mounted) return;
                                if (confirm == true) {
                                  await appState.removeRouter(router.id);
                                  if (!context.mounted) return;
                                  if (appState.routers.isEmpty) {
                                    unawaited(
                                      Navigator.of(
                                        context,
                                      ).pushNamedAndRemoveUntil(
                                        '/login',
                                        (route) => false,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('添加路由器'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                elevation: 2,
                              ),
                              onPressed: () async {
                                final ipController = TextEditingController();
                                final alternateController =
                                    TextEditingController();
                                final userController = TextEditingController(
                                  text: 'root',
                                );
                                final passController = TextEditingController();
                                final otpController = TextEditingController();
                                final totpSecretController =
                                    TextEditingController();
                                final formKey = GlobalKey<FormState>();
                                bool obscureText = true;
                                bool totpSecretVisible = false;
                                bool enrollFaceIdTotp = false;
                                bool isConnecting = false;
                                String? errorMessage;
                                await showDialog<Map<String, dynamic>>(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                      builder: (context, setState) {
                                        return AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surface
                                              .withValues(alpha: 0.95),
                                          shadowColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.10),
                                          insetPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 60,
                                              ), // Make dialog larger
                                          content: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 400,
                                              minWidth: 320,
                                              minHeight: 380,
                                            ),
                                            child: Form(
                                              key: formKey,
                                              child: SingleChildScrollView(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 32,
                                                      ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      TextFormField(
                                                        controller:
                                                            ipController,
                                                        decoration: const InputDecoration(
                                                          labelText: '路由器地址',
                                                          border:
                                                              OutlineInputBorder(),
                                                          prefixIcon: Icon(
                                                            Icons
                                                                .router_outlined,
                                                          ),
                                                          helperText:
                                                              '例如 192.168.1.1、router.local:8080 或完整网址',
                                                        ),
                                                        validator: (value) {
                                                          if (value == null ||
                                                              value.isEmpty) {
                                                            return '请输入路由器地址';
                                                          }
                                                          final parsed =
                                                              UrlParser.parse(
                                                                value,
                                                              );
                                                          if (!parsed.isValid) {
                                                            return parsed
                                                                    .error ??
                                                                '地址格式不正确';
                                                          }
                                                          return null;
                                                        },
                                                        autofillHints: const [
                                                          AutofillHints.url,
                                                          AutofillHints
                                                              .username,
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      TextFormField(
                                                        controller:
                                                            alternateController,
                                                        decoration: InputDecoration(
                                                          labelText: context
                                                              .l10n
                                                              .fallbackAddress,
                                                          border:
                                                              const OutlineInputBorder(),
                                                          prefixIcon:
                                                              const Icon(
                                                                Icons
                                                                    .swap_horiz,
                                                              ),
                                                          helperText: context
                                                              .l10n
                                                              .fallbackCredentialsHelp,
                                                          helperMaxLines: 2,
                                                        ),
                                                        validator: (value) {
                                                          if (value == null ||
                                                              value
                                                                  .trim()
                                                                  .isEmpty) {
                                                            return null;
                                                          }
                                                          final parsed =
                                                              UrlParser.parse(
                                                                value,
                                                              );
                                                          if (!parsed.isValid) {
                                                            return context
                                                                .l10n
                                                                .invalidAddressFormat;
                                                          }
                                                          final primary =
                                                              UrlParser.parse(
                                                                ipController
                                                                    .text,
                                                              );
                                                          if (primary.isValid &&
                                                              parsed.hostWithPort ==
                                                                  primary
                                                                      .hostWithPort) {
                                                            return context
                                                                .l10n
                                                                .mustDifferFromPrimaryAddress;
                                                          }
                                                          return null;
                                                        },
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      TextFormField(
                                                        controller:
                                                            userController,
                                                        decoration: const InputDecoration(
                                                          labelText: '用户名',
                                                          border:
                                                              OutlineInputBorder(),
                                                          prefixIcon: Icon(
                                                            Icons
                                                                .person_outline,
                                                          ),
                                                          helperText:
                                                              '默认通常为 root',
                                                        ),
                                                        validator: (v) =>
                                                            v == null ||
                                                                v.isEmpty
                                                            ? '必填'
                                                            : null,
                                                        autofillHints: const [
                                                          AutofillHints
                                                              .username,
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      TextFormField(
                                                        controller:
                                                            passController,
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
                                                              obscureText
                                                                  ? Icons
                                                                        .visibility_outlined
                                                                  : Icons
                                                                        .visibility_off_outlined,
                                                            ),
                                                            onPressed: () => setState(
                                                              () => obscureText =
                                                                  !obscureText,
                                                            ),
                                                            tooltip: obscureText
                                                                ? '隐藏密码'
                                                                : '显示密码',
                                                          ),
                                                        ),
                                                        obscureText:
                                                            obscureText,
                                                        autofillHints: const [
                                                          AutofillHints
                                                              .password,
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      if (appState
                                                          .supportsFaceIdTotp)
                                                        SwitchListTile.adaptive(
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                          secondary: const Icon(
                                                            Icons.face_outlined,
                                                          ),
                                                          title: const Text(
                                                            '使用 Face ID 自动验证',
                                                          ),
                                                          subtitle: const Text(
                                                            '密钥仅保存在当前设备',
                                                          ),
                                                          value:
                                                              enrollFaceIdTotp,
                                                          onChanged: (value) {
                                                            setState(() {
                                                              enrollFaceIdTotp =
                                                                  value;
                                                              if (value) {
                                                                otpController
                                                                    .clear();
                                                              } else {
                                                                totpSecretController
                                                                    .clear();
                                                              }
                                                            });
                                                          },
                                                        ),
                                                      if (enrollFaceIdTotp)
                                                        TextFormField(
                                                          controller:
                                                              totpSecretController,
                                                          obscureText:
                                                              !totpSecretVisible,
                                                          autocorrect: false,
                                                          enableSuggestions:
                                                              false,
                                                          decoration: InputDecoration(
                                                            labelText:
                                                                'TOTP 密钥或 otpauth://',
                                                            border:
                                                                const OutlineInputBorder(),
                                                            prefixIcon: const Icon(
                                                              Icons
                                                                  .key_outlined,
                                                            ),
                                                            suffixIcon: IconButton(
                                                              onPressed: () => setState(
                                                                () => totpSecretVisible =
                                                                    !totpSecretVisible,
                                                              ),
                                                              icon: Icon(
                                                                totpSecretVisible
                                                                    ? Icons
                                                                          .visibility_outlined
                                                                    : Icons
                                                                          .visibility_off_outlined,
                                                              ),
                                                              tooltip:
                                                                  totpSecretVisible
                                                                  ? '隐藏密钥'
                                                                  : '显示密钥',
                                                            ),
                                                          ),
                                                          validator: (value) {
                                                            try {
                                                              TotpService()
                                                                  .normalizeSecret(
                                                                    value ?? '',
                                                                  );
                                                              return null;
                                                            } on FormatException catch (
                                                              error
                                                            ) {
                                                              return error
                                                                  .message
                                                                  .toString();
                                                            }
                                                          },
                                                        )
                                                      else
                                                        TextFormField(
                                                          controller:
                                                              otpController,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          maxLength: 6,
                                                          autofillHints: const [
                                                            AutofillHints
                                                                .oneTimeCode,
                                                          ],
                                                          decoration: const InputDecoration(
                                                            labelText:
                                                                '两步验证码（可选）',
                                                            helperText:
                                                                '输入验证器中的 6 位动态码',
                                                            border:
                                                                OutlineInputBorder(),
                                                            prefixIcon: Icon(
                                                              Icons
                                                                  .pin_outlined,
                                                            ),
                                                            counterText: '',
                                                          ),
                                                          validator: (value) {
                                                            final otp =
                                                                value?.trim() ??
                                                                '';
                                                            if (otp.isNotEmpty &&
                                                                !RegExp(
                                                                  r'^\d{6}$',
                                                                ).hasMatch(
                                                                  otp,
                                                                )) {
                                                              return '请输入 6 位数字验证码';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      if (errorMessage !=
                                                          null) ...[
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                10,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
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
                                                                Icons
                                                                    .error_outline,
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onErrorContainer,
                                                              ),
                                                              const SizedBox(
                                                                width: 12,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  errorMessage!,
                                                                  style: Theme.of(context)
                                                                      .textTheme
                                                                      .bodyMedium
                                                                      ?.copyWith(
                                                                        color: Theme.of(
                                                                          context,
                                                                        ).colorScheme.onErrorContainer,
                                                                      ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                      const SizedBox(
                                                        height: 28,
                                                      ),
                                                      SizedBox(
                                                        width: double.infinity,
                                                        child: ElevatedButton(
                                                          onPressed:
                                                              isConnecting
                                                              ? null
                                                              : () async {
                                                                  if (formKey
                                                                      .currentState!
                                                                      .validate()) {
                                                                    final input =
                                                                        ipController
                                                                            .text
                                                                            .trim();
                                                                    final user =
                                                                        userController
                                                                            .text
                                                                            .trim();
                                                                    final pass =
                                                                        passController
                                                                            .text;
                                                                    final otp =
                                                                        enrollFaceIdTotp
                                                                        ? null
                                                                        : otpController
                                                                              .text;
                                                                    final totpSecret =
                                                                        enrollFaceIdTotp
                                                                        ? totpSecretController
                                                                              .text
                                                                        : null;

                                                                    // Parse the input to extract host, port, and protocol
                                                                    final parsedUrl =
                                                                        UrlParser.parse(
                                                                          input,
                                                                        );

                                                                    if (!parsedUrl
                                                                        .isValid) {
                                                                      setState(() {
                                                                        errorMessage =
                                                                            parsedUrl.error ??
                                                                            '地址格式不正确';
                                                                      });
                                                                      return;
                                                                    }

                                                                    String?
                                                                    alternateAddress;
                                                                    bool?
                                                                    alternateUseHttps;
                                                                    final alternateInput =
                                                                        alternateController
                                                                            .text
                                                                            .trim();
                                                                    if (alternateInput
                                                                        .isNotEmpty) {
                                                                      final parsedAlternate =
                                                                          UrlParser.parse(
                                                                            alternateInput,
                                                                          );
                                                                      if (!parsedAlternate
                                                                          .isValid) {
                                                                        setState(() {
                                                                          errorMessage =
                                                                              parsedAlternate.error ??
                                                                              context.l10n.invalidAddressFormat;
                                                                        });
                                                                        return;
                                                                      }
                                                                      alternateAddress =
                                                                          parsedAlternate
                                                                              .hostWithPort;
                                                                      alternateUseHttps =
                                                                          parsedAlternate
                                                                              .useHttps;
                                                                    }

                                                                    final hostWithPort =
                                                                        parsedUrl
                                                                            .hostWithPort;
                                                                    final useHttps =
                                                                        parsedUrl
                                                                            .useHttps;
                                                                    final id =
                                                                        '$hostWithPort-$user';

                                                                    if (routers.any(
                                                                      (r) =>
                                                                          r.id ==
                                                                          id,
                                                                    )) {
                                                                      setState(() {
                                                                        errorMessage =
                                                                            '该路由器已存在。';
                                                                      });
                                                                      return;
                                                                    }

                                                                    // Show connecting state
                                                                    setState(() {
                                                                      errorMessage =
                                                                          null;
                                                                      isConnecting =
                                                                          true;
                                                                    });

                                                                    // Always fetch hostname from router after login
                                                                    try {
                                                                      // Attempt login with the new router's credentials
                                                                      final loginSuccess = await appState.login(
                                                                        hostWithPort,
                                                                        user,
                                                                        pass,
                                                                        useHttps,
                                                                        otp:
                                                                            otp,
                                                                        totpSecret:
                                                                            totpSecret,
                                                                        fromRouter:
                                                                            false,
                                                                        alternateAddress:
                                                                            alternateAddress,
                                                                        alternateUseHttps:
                                                                            alternateUseHttps,
                                                                        context:
                                                                            context,
                                                                      );
                                                                      if (!loginSuccess) {
                                                                        setState(() {
                                                                          errorMessage =
                                                                              appState.errorMessage ??
                                                                              '连接失败：凭据无效或路由器不可达。';
                                                                          isConnecting =
                                                                              false;
                                                                        });
                                                                        return;
                                                                      }
                                                                      // Do NOT addRouter here; login already adds it if needed
                                                                      if (!context
                                                                          .mounted) {
                                                                        return;
                                                                      }
                                                                      Navigator.pop(
                                                                        context,
                                                                      );
                                                                    } catch (
                                                                      e
                                                                    ) {
                                                                      setState(() {
                                                                        errorMessage =
                                                                            '连接失败：${e.toString()}';
                                                                        isConnecting =
                                                                            false;
                                                                      });
                                                                    } finally {
                                                                      if (mounted) {
                                                                        setState(() {
                                                                          _switchingRouterId =
                                                                              null;
                                                                        });
                                                                      }
                                                                    }
                                                                  }
                                                                },
                                                          style: ElevatedButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 18,
                                                                ),
                                                            textStyle:
                                                                const TextStyle(
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    14,
                                                                  ),
                                                            ),
                                                            elevation: 4,
                                                            backgroundColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            foregroundColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onPrimary,
                                                          ),
                                                          child: isConnecting
                                                              ? Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    SizedBox(
                                                                      width: 22,
                                                                      height:
                                                                          22,
                                                                      child: CircularProgressIndicator(
                                                                        strokeWidth:
                                                                            3,
                                                                        valueColor: AlwaysStoppedAnimation<Color>(
                                                                          Theme.of(
                                                                            context,
                                                                          ).colorScheme.onPrimary,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 12,
                                                                    ),
                                                                    const Text(
                                                                      '正在连接…',
                                                                    ),
                                                                  ],
                                                                )
                                                              : Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: const [
                                                                    Icon(
                                                                      Icons.add,
                                                                    ),
                                                                    SizedBox(
                                                                      width: 12,
                                                                    ),
                                                                    Text('添加'),
                                                                  ],
                                                                ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                                ipController.dispose();
                                alternateController.dispose();
                                userController.dispose();
                                passController.dispose();
                                otpController.dispose();
                                totpSecretController.dispose();
                                if (!context.mounted) return;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedRouterCard extends StatelessWidget {
  final String routerTitle;
  final String subtitle;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveFallback;
  final VoidCallback? onDelete;

  const _UnifiedRouterCard({
    required this.routerTitle,
    required this.subtitle,
    required this.isSelected,
    required this.isSwitching,
    this.onTap,
    this.onRemoveFallback,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: isSelected ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.router,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                  size: 22,
                  semanticLabel: '路由器图标',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routerTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected && !isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Chip(
                    label: const Text('当前'),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                    ),
                    backgroundColor: colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              if (isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              if (onRemoveFallback != null)
                IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: context.l10n.removeFallbackAddress,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(
                          dialogContext.l10n.removeFallbackAddressTitle,
                        ),
                        content: Text(
                          dialogContext.l10n.removeFallbackAddressConfirmation,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(dialogContext.l10n.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(dialogContext.l10n.remove),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      onRemoveFallback!();
                    }
                  },
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '移除',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
