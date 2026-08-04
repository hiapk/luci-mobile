import 'package:flutter/cupertino.dart';

class NativeNavigationBar extends CupertinoNavigationBar {
  NativeNavigationBar({
    super.key,
    required BuildContext context,
    super.previousPageTitle,
    super.middle,
    super.trailing,
  }) : super(
         backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
           context,
         ),
         automaticBackgroundVisibility: false,
         enableBackgroundFilterBlur: false,
         brightness: CupertinoTheme.brightnessOf(context),
       );
}
