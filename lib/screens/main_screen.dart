import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/luci_menu_screen.dart';
import 'package:luci_mobile/screens/more_screen.dart';
import 'package:luci_mobile/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
    _currentInterfaceToScroll = widget.interfaceToScroll;
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle parameter changes (important for iOS navigation)
    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _currentInterfaceToScroll = widget.interfaceToScroll;
    }

    // Handle initial tab changes
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  List<Widget> get _widgetOptions => [
    const DashboardScreen(),
    const ClientsScreen(),
    InterfacesScreen(
      scrollToInterface: _currentInterfaceToScroll,
      onScrollComplete: _clearInterfaceToScroll,
    ),
    const LuciMenuScreen(),
    const MoreScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Clear interface scroll state when navigating away from Interfaces tab
    if (_selectedIndex != 2 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for requestedTab in AppState
    final appState = ref.watch(appStateProvider);
    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      // Store the values before the callback to avoid null reference issues
      final requestedTab = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = requestedTab;
          // Update interface to scroll if provided
          if (requestedInterface != null) {
            _currentInterfaceToScroll = requestedInterface;
          }
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          double getTabOpacity(int index) =>
              (isRebooting && index != 4) ? 0.5 : 1.0;
          Widget tabIcon(IconData icon, int index) =>
              Opacity(opacity: getTabOpacity(index), child: Icon(icon));
          return CupertinoTabBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              if (isRebooting && index != 4) return; // Only allow 'More' tab
              _onItemTapped(index);
            },
            activeColor: CupertinoColors.activeBlue,
            inactiveColor: CupertinoColors.inactiveGray,
            backgroundColor: CupertinoColors.systemBackground.resolveFrom(
              context,
            ),
            items: [
              BottomNavigationBarItem(
                activeIcon: tabIcon(CupertinoIcons.square_grid_2x2_fill, 0),
                icon: tabIcon(CupertinoIcons.square_grid_2x2, 0),
                label: '概览',
              ),
              BottomNavigationBarItem(
                activeIcon: tabIcon(CupertinoIcons.person_2_fill, 1),
                icon: tabIcon(CupertinoIcons.person_2, 1),
                label: '设备',
              ),
              BottomNavigationBarItem(
                activeIcon: tabIcon(CupertinoIcons.rectangle_3_offgrid_fill, 2),
                icon: tabIcon(CupertinoIcons.rectangle_3_offgrid, 2),
                label: '接口',
              ),
              BottomNavigationBarItem(
                activeIcon: tabIcon(CupertinoIcons.compass_fill, 3),
                icon: tabIcon(CupertinoIcons.compass, 3),
                label: 'LuCI',
              ),
              BottomNavigationBarItem(
                activeIcon: tabIcon(CupertinoIcons.ellipsis_circle_fill, 4),
                icon: tabIcon(CupertinoIcons.ellipsis_circle, 4),
                label: '更多',
              ),
            ],
          );
        },
      ),
    );
  }
}
