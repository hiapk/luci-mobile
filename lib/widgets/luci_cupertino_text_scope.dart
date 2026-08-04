import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

class LuciCupertinoTextScope extends StatelessWidget {
  final Widget child;

  const LuciCupertinoTextScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final inheritedTheme = CupertinoTheme.of(context);
    final brightness = Theme.of(context).brightness;
    return CupertinoTheme(
      data: inheritedTheme.copyWith(brightness: brightness),
      child: Builder(
        builder: (scopeContext) {
          final style = CupertinoTheme.of(scopeContext).textTheme.textStyle
              .copyWith(
                color: CupertinoColors.label.resolveFrom(scopeContext),
                decoration: TextDecoration.none,
              );
          return DefaultTextStyle(style: style, child: child);
        },
      ),
    );
  }
}
