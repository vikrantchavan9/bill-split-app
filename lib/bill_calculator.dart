import 'models.dart';

/// All values are integer paise. Any remainder is assigned in stable people order.
class BillCalculator {
  static List<ItemAllocation> equalSplit(
    int totalPaise,
    List<String> personIds,
  ) {
    if (personIds.isEmpty || totalPaise < 0) return [];
    final base = totalPaise ~/ personIds.length;
    final remainder = totalPaise % personIds.length;
    return [
      for (var i = 0; i < personIds.length; i++)
        ItemAllocation(
          personId: personIds[i],
          amountPaise: base + (i < remainder ? 1 : 0),
        ),
    ];
  }

  static List<ItemAllocation> quantitySplit(
    int unitPricePaise,
    Map<String, int> quantities,
  ) => [
    for (final entry in quantities.entries.where((e) => e.value > 0))
      ItemAllocation(
        personId: entry.key,
        quantity: entry.value,
        amountPaise: entry.value * unitPricePaise,
      ),
  ];

  static List<ItemAllocation> proportionalSplit(
    int totalPaise,
    Map<String, int> weights,
  ) {
    final eligible = weights.entries.where((e) => e.value > 0).toList();
    final weightTotal = eligible.fold<int>(0, (sum, e) => sum + e.value);
    if (weightTotal == 0) return [];
    var allocated = 0;
    final result = <ItemAllocation>[];
    for (var i = 0; i < eligible.length; i++) {
      final entry = eligible[i];
      final amount = i == eligible.length - 1
          ? totalPaise - allocated
          : (totalPaise * entry.value) ~/ weightTotal;
      allocated += amount;
      result.add(ItemAllocation(personId: entry.key, amountPaise: amount));
    }
    return result;
  }

  static int allocatedTotal(Bill bill) => bill.items.fold(
    0,
    (sum, item) =>
        sum + item.allocations.fold<int>(0, (s, a) => s + a.amountPaise),
  );
  static int itemTotal(Bill bill) =>
      bill.items.fold(0, (sum, item) => sum + item.totalPaise);

  static Map<String, int> personTotals(Bill bill) {
    final result = {for (final person in bill.people) person.id: 0};
    for (final item in bill.items) {
      for (final allocation in item.allocations) {
        if (result.containsKey(allocation.personId)) {
          result[allocation.personId] =
              result[allocation.personId]! + allocation.amountPaise;
        }
      }
    }
    return result;
  }

  static Map<String, int> paidTotals(Bill bill) {
    final result = {for (final person in bill.people) person.id: 0};
    for (final payment in bill.payments) {
      if (result.containsKey(payment.personId)) {
        result[payment.personId] =
            result[payment.personId]! + payment.amountPaise;
      }
    }
    return result;
  }

  static int itemShare(BillItem item, String personId) => item.allocations
      .where((a) => a.personId == personId)
      .fold(0, (sum, a) => sum + a.amountPaise);
}
