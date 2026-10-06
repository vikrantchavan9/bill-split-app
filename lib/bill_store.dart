import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class BillStore {
  static const _key = 'splitbill.current.v1';
  Future<Bill?> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      return Bill.decode(p.getString(_key));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Bill bill) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, bill.encode());
  }
}
