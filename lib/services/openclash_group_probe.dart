typedef OpenClashGroupProbe = Future<Map<String, dynamic>> Function(
  String group,
);

Future<Map<String, Map<String, dynamic>>> testOpenClashGroupsSequentially(
  Iterable<String> groups,
  OpenClashGroupProbe probe,
) async {
  final results = <String, Map<String, dynamic>>{};
  for (final group in groups) {
    results[group] = await probe(group);
  }
  return results;
}
