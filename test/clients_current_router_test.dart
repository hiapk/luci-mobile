import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/client_list_policy.dart';

void main() {
  test('devices page is scoped to the selected router', () {
    expect(ClientListPolicy.scope, ClientListScope.selectedRouter);
  });
}
