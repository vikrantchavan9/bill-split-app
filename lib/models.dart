import 'dart:convert';

enum SplitType {
  everyone,
  everyoneExcept,
  specificMembers,
  quantity,
  custom,
  proportional,
}

class Person {
  Person(this.id, this.name);
  final String id;
  String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Person.fromJson(Map<String, dynamic> j) =>
      Person(j['id'] as String, j['name'] as String);
}

class ItemAllocation {
  ItemAllocation({
    required this.personId,
    required this.amountPaise,
    this.quantity = 0,
  });
  final String personId;
  final int amountPaise;
  final int quantity;
  Map<String, dynamic> toJson() => {
    'personId': personId,
    'amountPaise': amountPaise,
    'quantity': quantity,
  };
  factory ItemAllocation.fromJson(Map<String, dynamic> j) => ItemAllocation(
    personId: j['personId'] as String,
    amountPaise: j['amountPaise'] as int,
    quantity: (j['quantity'] as int?) ?? 0,
  );
}

class BillItem {
  BillItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPricePaise,
    required this.splitType,
    required this.allocations,
    this.isCharge = false,
  });
  final String id;
  String name;
  int quantity;
  int unitPricePaise;
  SplitType splitType;
  List<ItemAllocation> allocations;
  bool isCharge;
  int get totalPaise => quantity * unitPricePaise;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'unitPricePaise': unitPricePaise,
    'splitType': splitType.name,
    'allocations': allocations.map((e) => e.toJson()).toList(),
    'isCharge': isCharge,
  };
  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
    id: j['id'] as String,
    name: j['name'] as String,
    quantity: j['quantity'] as int,
    unitPricePaise: j['unitPricePaise'] as int,
    splitType: SplitType.values.firstWhere(
      (e) => e.name == j['splitType'],
      orElse: () => SplitType.everyone,
    ),
    allocations: (j['allocations'] as List)
        .map((e) => ItemAllocation.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    isCharge: (j['isCharge'] as bool?) ?? false,
  );
}

class Payment {
  Payment({
    required this.id,
    required this.personId,
    required this.amountPaise,
    required this.createdAt,
  });
  final String id, personId;
  final int amountPaise;
  final DateTime createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'personId': personId,
    'amountPaise': amountPaise,
    'createdAt': createdAt.toIso8601String(),
  };
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: j['id'] as String,
    personId: j['personId'] as String,
    amountPaise: j['amountPaise'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

class Bill {
  Bill({
    required this.id,
    required this.name,
    required this.receiptTotalPaise,
    required this.people,
    required this.items,
    required this.payments,
    required this.createdAt,
    required this.updatedAt,
    this.completed = false,
  });
  final String id;
  String name;
  int? receiptTotalPaise;
  final List<Person> people;
  final List<BillItem> items;
  final List<Payment> payments;
  final DateTime createdAt;
  DateTime updatedAt;
  bool completed;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'receiptTotalPaise': receiptTotalPaise,
    'people': people.map((e) => e.toJson()).toList(),
    'items': items.map((e) => e.toJson()).toList(),
    'payments': payments.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'completed': completed,
  };
  String encode() => jsonEncode(toJson());
  static Bill? decode(String? value) => value == null
      ? null
      : Bill.fromJson(Map<String, dynamic>.from(jsonDecode(value) as Map));
  factory Bill.fromJson(Map<String, dynamic> j) {
    final people = (j['people'] as List)
        .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final rawItems = (j['items'] ?? j['expenses'] ?? const []) as List;
    final items = rawItems.map((raw) {
      final map = Map<String, dynamic>.from(raw);
      if (!map.containsKey('unitPricePaise') && map.containsKey('amount')) {
        final amount = map['amount'] as int;
        final participantIds = List<String>.from(
          map['participantIds'] ?? const <String>[],
        );
        final splitName = map['splitType'] as String? ?? 'equal';
        List<ItemAllocation> allocations;
        if (splitName == 'custom') {
          final custom = Map<String, int>.from(
            map['customAmounts'] ?? const {},
          );
          allocations = custom.entries
              .map((e) => ItemAllocation(personId: e.key, amountPaise: e.value))
              .toList();
        } else {
          final ids = participantIds.isEmpty
              ? people.map((p) => p.id).toList()
              : participantIds;
          final base = ids.isEmpty ? 0 : amount ~/ ids.length;
          final remainder = ids.isEmpty ? 0 : amount % ids.length;
          allocations = [
            for (var i = 0; i < ids.length; i++)
              ItemAllocation(
                personId: ids[i],
                amountPaise: base + (i < remainder ? 1 : 0),
              ),
          ];
        }
        return BillItem(
          id: map['id'] as String,
          name: map['name'] as String,
          quantity: 1,
          unitPricePaise: amount,
          splitType: splitName == 'custom'
              ? SplitType.custom
              : SplitType.everyone,
          allocations: allocations,
        );
      }
      return BillItem.fromJson(map);
    }).toList();
    final payments = (j['payments'] as List? ?? const []).map((raw) {
      final map = Map<String, dynamic>.from(raw);
      if (map.containsKey('amount') && !map.containsKey('amountPaise')) {
        map['amountPaise'] = map['amount'];
      }
      return Payment.fromJson(map);
    }).toList();
    return Bill(
      id: j['id'] as String,
      name: j['name'] as String,
      receiptTotalPaise: j['receiptTotalPaise'] as int?,
      people: people,
      items: items,
      payments: payments,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt:
          DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      completed: (j['completed'] as bool?) ?? false,
    );
  }
}
