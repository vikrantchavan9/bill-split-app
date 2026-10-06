import 'package:flutter_test/flutter_test.dart';
import 'package:bill_splitter/bill_calculator.dart';
import 'package:bill_splitter/models.dart';

void main() {
  test('equal allocation distributes remainder paise exactly', () {
    final allocations = BillCalculator.equalSplit(10000, ['a', 'b', 'c']);
    expect(allocations.map((a) => a.amountPaise).toList(), [3334, 3333, 3333]);
    expect(allocations.fold<int>(0, (sum, a) => sum + a.amountPaise), 10000);
  });

  test('quantity allocation uses the exact item count', () {
    final allocations = BillCalculator.quantitySplit(5000, {
      'avantika': 2,
      'wamshi': 1,
      'tanbeer': 1,
      'johney': 1,
    });
    expect(allocations.fold<int>(0, (sum, a) => sum + a.quantity), 5);
    expect(allocations.fold<int>(0, (sum, a) => sum + a.amountPaise), 25000);
    expect(allocations.first.amountPaise, 10000);
  });

  test('proportional allocation adds up without floating point drift', () {
    final allocations = BillCalculator.proportionalSplit(20000, {
      'vikrant': 100000,
      'tanbeer': 50000,
      'rahul': 50000,
    });
    expect(
      {for (final a in allocations) a.personId: a.amountPaise},
      {'vikrant': 10000, 'tanbeer': 5000, 'rahul': 5000},
    );
    expect(allocations.fold<int>(0, (sum, a) => sum + a.amountPaise), 20000);
  });

  test('example receipt allocates ₹3,603 to the correct people', () {
    final names = [
      'Vikrant',
      'Avantika',
      'Wamshi',
      'Tanbeer',
      'Johney',
      ...List.generate(7, (i) => 'Person ${i + 6}'),
    ];
    final people = [
      for (var i = 0; i < names.length; i++) Person('p$i', names[i]),
    ];
    final items = <BillItem>[];
    final ids = people.map((p) => p.id).toList();

    void add(
      String id,
      String name,
      int amount,
      List<String> participants, {
      bool quantity = false,
      Map<String, int>? quantities,
      int unit = 0,
    }) {
      final allocations = quantity
          ? BillCalculator.quantitySplit(unit, quantities!)
          : BillCalculator.equalSplit(amount, participants);
      items.add(
        BillItem(
          id: id,
          name: name,
          quantity: quantity
              ? quantities!.values.fold<int>(0, (s, q) => s + q)
              : 1,
          unitPricePaise: quantity ? unit : amount,
          splitType: quantity ? SplitType.quantity : SplitType.everyone,
          allocations: allocations,
        ),
      );
    }

    add(
      'bir',
      'Chicken Dum Biryani',
      184900,
      ids.where((id) => id != 'p1').toList(),
    );
    add('starter', 'Chicken 65 Rbb Starter', 120000, ids);
    add('solo', 'Chicken 65 Solo Bucket', 26900, ['p1']);
    add(
      'coke',
      'Diet Coke',
      25000,
      const [],
      quantity: true,
      quantities: {'p1': 2, 'p2': 1, 'p3': 1, 'p4': 1},
      unit: 5000,
    );
    add('egg', 'Boiled Egg', 1500, ['p3']);
    add('water', 'Water Bottle', 2000, ids);

    final now = DateTime(2026, 10, 6);
    final bill = Bill(
      id: 'bill',
      name: 'Office Celebration',
      receiptTotalPaise: 360300,
      people: people,
      items: items,
      payments: [],
      createdAt: now,
      updatedAt: now,
    );
    expect(BillCalculator.allocatedTotal(bill), 360300);
    expect(BillCalculator.itemTotal(bill), 360300);
    expect(BillCalculator.itemShare(items[2], 'p1'), 26900);
    expect(BillCalculator.itemShare(items[3], 'p1'), 10000);
    expect(BillCalculator.itemShare(items[4], 'p3'), 1500);
    expect(BillCalculator.itemShare(items[0], 'p1'), 0);
  });

  test('custom allocation and payments remain derived from item rows', () {
    final people = [Person('a', 'A'), Person('b', 'B')];
    final now = DateTime(2026, 10, 6);
    final bill = Bill(
      id: 'bill',
      name: 'Dinner',
      receiptTotalPaise: 84900,
      people: people,
      items: [
        BillItem(
          id: 'dish',
          name: 'Dish',
          quantity: 1,
          unitPricePaise: 84900,
          splitType: SplitType.custom,
          allocations: [
            ItemAllocation(personId: 'a', amountPaise: 50000),
            ItemAllocation(personId: 'b', amountPaise: 34900),
          ],
        ),
      ],
      payments: [
        Payment(id: 'pay', personId: 'a', amountPaise: 20000, createdAt: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final owed = BillCalculator.personTotals(bill);
    final paid = BillCalculator.paidTotals(bill);
    expect(owed, {'a': 50000, 'b': 34900});
    expect(owed['a']! - paid['a']!, 30000);
    expect(BillCalculator.allocatedTotal(bill), bill.receiptTotalPaise);
  });
}
