import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/screens/luci_menu_screen.dart';
import 'package:luci_mobile/screens/luci_standard_native_screens.dart';

Future<void> pumpDarkPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.dark,
        home: page,
      ),
    ),
  );
}

Future<void> pumpLightPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        themeMode: ThemeMode.light,
        home: page,
      ),
    ),
  );
}

void expectNavigationBarMatchesPage(WidgetTester tester) {
  final navigationBarFinder = find.byWidgetPredicate(
    (widget) => widget is CupertinoNavigationBar,
  );
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
  expect(navigationBar.automaticBackgroundVisibility, isFalse);
  expect(
    navigationBar.brightness,
    CupertinoTheme.brightnessOf(navigationBarContext),
  );
}

void main() {
  testWidgets('native navigation bar stays dark after scrolling', (
    tester,
  ) async {
    await pumpDarkPage(
      tester,
      NativeRouterScaffold(
        title: '应用过滤',
        onRefresh: () {},
        child: ListView.builder(
          itemCount: 30,
          itemBuilder: (context, index) =>
              SizedBox(height: 56, child: Text('设备 $index')),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expectNavigationBarMatchesPage(tester);
  });

  testWidgets('LuCI menu navigation bar uses the dark page background', (
    tester,
  ) async {
    await pumpDarkPage(tester, const LuciMenuScreen());

    expectNavigationBarMatchesPage(tester);
  });

  testWidgets('native navigation bar follows the light page background', (
    tester,
  ) async {
    await pumpLightPage(
      tester,
      NativeRouterScaffold(
        title: '系统设置',
        onRefresh: () {},
        child: const SizedBox.expand(),
      ),
    );

    expectNavigationBarMatchesPage(tester);
  });

  test('all screens use the shared native navigation bar', () {
    final offenders = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file.readAsStringSync().contains('CupertinoNavigationBar('),
        )
        .map((file) => file.path)
        .toList();

    expect(offenders, isEmpty);
  });
}
