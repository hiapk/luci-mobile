import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/screens/luci_standard_native_screens.dart';

void main() {
  testWidgets('native navigation bar stays dark after scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.dark,
        home: NativeRouterScaffold(
          title: '应用过滤',
          onRefresh: () {},
          child: ListView.builder(
            itemCount: 30,
            itemBuilder: (context, index) =>
                SizedBox(height: 56, child: Text('设备 $index')),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final navigationBarFinder = find.byType(CupertinoNavigationBar);
    final navigationBar = tester.widget<CupertinoNavigationBar>(
      navigationBarFinder,
    );
    final navigationBarContext = tester.element(navigationBarFinder);
    final effectiveNavigationBarColor =
        CupertinoDynamicColor.maybeResolve(
          navigationBar.backgroundColor,
          navigationBarContext,
        ) ??
        CupertinoTheme.of(navigationBarContext).barBackgroundColor;
    final pageScaffold = tester.widget<CupertinoPageScaffold>(
      find.byType(CupertinoPageScaffold),
    );

    expect(effectiveNavigationBarColor, pageScaffold.backgroundColor);
  });
}
