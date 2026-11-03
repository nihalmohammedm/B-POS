import 'package:BPOS/sync/menu_admin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next item code follows the highest number, keeping the padding', () {
    expect(MenuAdminApi.nextCode(['001', '002', '005']), '006');
    expect(MenuAdminApi.nextCode(['0099', '12']), '0100');
    expect(MenuAdminApi.nextCode(['A1', '', '007']), '008');
    expect(MenuAdminApi.nextCode([]), '001');
  });
}
