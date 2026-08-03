class LuciMenuItem {
  final String key;
  final String title;
  final double order;
  final List<String> pathSegments;
  final List<LuciMenuItem> children;

  const LuciMenuItem({
    required this.key,
    required this.title,
    required this.order,
    required this.pathSegments,
    this.children = const [],
  });
}
