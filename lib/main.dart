import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'bill_calculator.dart';
import 'bill_store.dart';
import 'models.dart';

void main() => runApp(const SplitBillApp());

class SplitBillApp extends StatelessWidget {
  const SplitBillApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SplitBill',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const HomeScreen(),
  );
  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff6458d8),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xff111218)
          : const Color(0xfff7f7fb),
      appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? const Color(0xff24252e)
            : const Color(0xfff0f0f6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 14,
        ),
      ),
    );
  }
}

String makeId() =>
    DateTime.now().microsecondsSinceEpoch.toString() + UniqueKey().toString();
int? parsePaise(String input) {
  final m = RegExp(r'^\s*(-?)(\d+)(?:\.(\d*))?\s*$')
      .firstMatch(input.replaceAll(',', ''));
  if (m == null) return null;
  final d = m.group(3) ?? '';
  var cents =
      int.parse(m.group(2)!) * 100 + int.parse(('${d}00').substring(0, 2));
  if (d.length > 2 && int.parse(d[2]) >= 5) cents++;
  return m.group(1) == '-' ? -cents : cents;
}

String inr(int paise, {bool decimals = false}) {
  final n = paise.abs() ~/ 100;
  final s = n.toString();
  final grouped = s.length <= 3
      ? s
      : '${_groupIndian(s.substring(0, s.length - 3))},${s.substring(s.length - 3)}';
  final cents = paise.abs() % 100;
  return '${paise < 0 ? '-' : ''}₹$grouped${decimals || cents != 0 ? '.${cents.toString().padLeft(2, '0')}' : ''}';
}

String _groupIndian(String digits) {
  final parts = <String>[];
  while (digits.length > 2) {
    parts.insert(0, digits.substring(digits.length - 2));
    digits = digits.substring(0, digits.length - 2);
  }
  parts.insert(0, digits);
  return parts.join(',');
}

String splitLabel(SplitType type) => switch (type) {
  SplitType.everyone => 'Everyone',
  SplitType.everyoneExcept => 'Everyone except',
  SplitType.specificMembers => 'Specific people',
  SplitType.quantity => 'By quantity',
  SplitType.custom => 'Custom amounts',
  SplitType.proportional => 'By consumption',
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = BillStore();
  Bill? _bill;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await _store.load();
    if (!mounted) return;
    setState(() {
      _bill = b;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final b = _bill;
    if (b == null) return;
    b.updatedAt = DateTime.now();
    await _store.save(b);
    if (mounted) setState(() {});
  }

  Future<void> _newBill() async {
    if (_bill != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new bill?'),
          content: const Text(
            'The current bill will be replaced on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep current bill'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<Bill>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewBillSheet(),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _bill = result);
      await _save();
    }
  }

  Future<void> _editItem([BillItem? existing, bool charge = false]) async {
    final b = _bill;
    if (b == null) return;
    if (b.completed) {
      _message('Reopen this bill before editing its items.');
      return;
    }
    if (b.people.length < 2) {
      _message('Add at least two people before adding items.');
      return;
    }
    final item = await Navigator.push<BillItem>(
      context,
      MaterialPageRoute(
        builder: (_) => ItemEditor(
          bill: b,
          existing: existing,
          isCharge: existing?.isCharge ?? charge,
        ),
      ),
    );
    if (item == null) return;
    if (existing == null) {
      b.items.add(item);
    } else {
      final i = b.items.indexWhere((x) => x.id == existing.id);
      if (i >= 0) b.items[i] = item;
    }
    await _save();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final b = _bill;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (b == null) return Scaffold(appBar: _appBar(null), body: _welcome());
    final totals = BillCalculator.personTotals(b),
        paid = BillCalculator.paidTotals(b);
    final allocated = BillCalculator.allocatedTotal(b),
        itemTotal = BillCalculator.itemTotal(b);
    final receiptDiff = b.receiptTotalPaise == null
        ? null
        : b.receiptTotalPaise! - allocated;
    final totalOwed = allocated,
        totalPaid = b.payments.fold<int>(0, (s, p) => s + p.amountPaise);
    return Scaffold(
      appBar: _appBar(b),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
          children: [
            _billCard(b, itemTotal, allocated, receiptDiff),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    'PEOPLE',
                    '${b.people.length}',
                    Icons.groups_2_outlined,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _metric(
                    'ITEMS',
                    '${b.items.length}',
                    Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _metric(
                    'REMAINING',
                    inr((totalOwed - totalPaid).clamp(0, totalOwed).toInt()),
                    Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Items',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: _managePeople,
                  icon: const Icon(Icons.people_outline),
                  label: const Text('People'),
                ),
              ],
            ),
            if (b.items.isEmpty)
              _emptySection(
                'Add your first item',
                'Add a dish or charge, then choose who had it.',
              )
            else
              ...b.items.map((item) => _itemTile(b, item)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Who owes what?',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _openSettlement,
                  child: const Text('Settlement'),
                ),
              ],
            ),
            ...b.people.map(
              (p) => _personTile(b, p, totals[p.id] ?? 0, paid[p.id] ?? 0),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openSettlement,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Bill summary & share'),
            ),
            if (b.completed)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _emptySection(
                  'Bill completed',
                  'You can still review and update this bill.',
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: b.completed
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editItem(),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
    );
  }

  AppBar _appBar(Bill? b) => AppBar(
    title: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.call_split_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        const Text('SplitBill', style: TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
    actions: [
      if (b != null)
        IconButton(
          tooltip: 'New bill',
          onPressed: _newBill,
          icon: const Icon(Icons.add_circle_outline),
        ),
      if (b != null)
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'people') await _managePeople();
            if (v == 'receipt') await _setReceipt();
            if (v == 'rename') await _rename();
            if (v == 'summary') await _openSettlement();
            if (v == 'charge') await _editItem(null, true);
            if (v == 'finish') {
              if (b.completed) {
                b.completed = false;
                await _save();
              } else {
                final allocated = BillCalculator.allocatedTotal(b),
                    itemsTotal = BillCalculator.itemTotal(b);
                if (allocated != itemsTotal) {
                  _message(
                    'Finish is disabled until every item amount is fully allocated.',
                  );
                } else if (b.receiptTotalPaise != null &&
                    allocated != b.receiptTotalPaise) {
                  _message(
                    'Finish is disabled until allocated total matches the receipt.',
                  );
                } else {
                  b.completed = true;
                  await _save();
                }
              }
            }
            if (v == 'new') await _newBill();
            if (v == 'clear') await _clearBill();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'people', child: Text('Manage people')),
            const PopupMenuItem(value: 'receipt', child: Text('Receipt total')),
            const PopupMenuItem(value: 'charge', child: Text('Add a charge')),
            const PopupMenuItem(value: 'rename', child: Text('Rename bill')),
            const PopupMenuItem(value: 'summary', child: Text('Bill summary')),
            PopupMenuItem(
              value: 'finish',
              child: Text(b.completed ? 'Reopen bill' : 'Finish bill'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'new', child: Text('New bill')),
            const PopupMenuItem(
              value: 'clear',
              child: Text('Clear current bill'),
            ),
          ],
        ),
    ],
  );

  Widget _welcome() => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Tell us who ate what.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'We’ll calculate everyone’s exact share.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _newBill,
            icon: const Icon(Icons.add),
            label: const Text('New bill'),
          ),
        ],
      ),
    ),
  );

  Widget _billCard(Bill b, int itemTotal, int allocated, int? diff) {
    final allocationDiff = itemTotal - allocated;
    final matched = (diff == null || diff == 0) && allocationDiff == 0;
    final color = matched ? Colors.green : Theme.of(context).colorScheme.error;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit receipt total',
                  onPressed: _setReceipt,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Text(
              '${b.people.length} people',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 17),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.receiptTotalPaise == null
                            ? 'ITEM TOTAL'
                            : 'RECEIPT TOTAL',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        inr(b.receiptTotalPaise ?? itemTotal),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ALLOCATED',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      inr(allocated),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  matched ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: color,
                  size: 19,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    allocationDiff != 0
                        ? allocationDiff > 0
                              ? '${inr(allocationDiff)} of item value not allocated'
                              : '${inr(-allocationDiff)} over allocated to people'
                        : diff == null
                        ? 'Enter receipt total to verify allocation'
                        : diff == 0
                        ? 'Matched'
                        : diff > 0
                        ? '${inr(diff)} unallocated'
                        : '${inr(-diff)} over allocated',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(letterSpacing: .5),
          ),
          const SizedBox(height: 2),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _emptySection(String title, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _itemTile(Bill bill, BillItem item) {
    final allocations = item.allocations
        .where((a) => a.amountPaise > 0)
        .toList();
    final names = allocations
        .map((a) {
          for (final person in bill.people) {
            if (person.id == a.personId) return person.name;
          }
          return null;
        })
        .whereType<String>()
        .toList();
    final subtitle = item.splitType == SplitType.everyone
        ? 'Everyone'
        : item.splitType == SplitType.quantity
        ? '${allocations.length} people · ${item.quantity} units'
        : item.splitType == SplitType.proportional
        ? 'Proportional charge'
        : names.length <= 2
        ? names.join(', ')
        : '${names.length} people';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _itemDetails(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.isCharge
                      ? Colors.orange.withValues(alpha: .15)
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  item.isCharge
                      ? Icons.percent_rounded
                      : Icons.restaurant_outlined,
                  color: item.isCharge
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                inr(item.totalPaise),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _personTile(Bill b, Person p, int total, int paid) {
    final remaining = (total - paid).clamp(0, total).toInt();
    final status = remaining == 0
        ? 'Paid'
        : paid > 0
        ? 'Partially paid'
        : 'Unpaid';
    final tint = remaining == 0
        ? Colors.green
        : paid > 0
        ? Colors.orange
        : Theme.of(context).colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _personDetails(p),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
        ),
        title: Text(
          p.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          status,
          style: TextStyle(
            color: tint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              inr(total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (paid > 0 && remaining > 0)
              Text(
                'Left ${inr(remaining)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _managePeople() async {
    final b = _bill;
    if (b == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeopleScreen(bill: b, onChanged: _save),
      ),
    );
  }

  Future<void> _setReceipt() async {
    final b = _bill!;
    final value = await _showTextInputDialog(
      context: context,
      title: 'Receipt total',
      initialValue: b.receiptTotalPaise == null
          ? ''
          : (b.receiptTotalPaise! / 100).toStringAsFixed(2),
      hintText: 'Optional',
      numeric: true,
    );
    if (value == null) return;
    if (!mounted) return;
    final raw = value.trim();
    final amount = raw.isEmpty ? null : parsePaise(raw);
    if (raw.isNotEmpty && (amount == null || amount < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid receipt amount.')),
      );
      return;
    }
    b.receiptTotalPaise = amount;
    await _save();
  }

  Future<void> _rename() async {
    final b = _bill!;
    final value = await _showTextInputDialog(
      context: context,
      title: 'Rename bill',
      initialValue: b.name,
      labelText: 'Name',
    );
    if (value != null && value.trim().isNotEmpty) {
      b.name = value.trim();
      await _save();
    }
  }

  Future<void> _clearBill() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear current bill?'),
        content: const Text(
          'People, items and payments will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('splitbill.current.v1');
      setState(() => _bill = null);
    }
  }

  Future<void> _itemDetails(BillItem item) async {
    final b = _bill!;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: Theme.of(ctx).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${item.quantity} × ${inr(item.unitPricePaise)} = ${inr(item.totalPaise)} · ${splitLabel(item.splitType)}',
              ),
              const SizedBox(height: 12),
              ...item.allocations.map((a) {
                Person? p;
                for (final candidate in b.people) {
                  if (candidate.id == a.personId) {
                    p = candidate;
                    break;
                  }
                }
                if (p == null) return const SizedBox.shrink();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  trailing: Text(
                    '${a.quantity > 0 ? '${a.quantity} × ' : ''}${inr(a.amountPaise)}',
                  ),
                );
              }),
              const Divider(),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'edit') await _editItem(item);
    if (action == 'delete' && mounted) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete item?'),
          content: Text(
            '${item.name} will be removed and all person totals recalculated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes == true) {
        b.items.removeWhere((x) => x.id == item.id);
        await _save();
      }
    }
  }

  Future<void> _personDetails(Person person) async {
    final b = _bill!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonDetailScreen(bill: b, person: person, onChanged: _save),
      ),
    );
  }

  Future<void> _openSettlement() async {
    final b = _bill;
    if (b != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SettlementScreen(bill: b)),
      );
    }
  }
}

class ItemEditor extends StatefulWidget {
  const ItemEditor({
    super.key,
    required this.bill,
    this.existing,
    this.isCharge = false,
  });
  final Bill bill;
  final BillItem? existing;
  final bool isCharge;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

Future<String?> _showTextInputDialog({
  required BuildContext context,
  required String title,
  String? initialValue,
  String? labelText,
  String? hintText,
  bool numeric = false,
  bool capitalizeWords = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextInputDialog(
    title: title,
    initialValue: initialValue,
    labelText: labelText,
    hintText: hintText,
    numeric: numeric,
    capitalizeWords: capitalizeWords,
  ),
);

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    this.initialValue,
    this.labelText,
    this.hintText,
    this.numeric = false,
    this.capitalizeWords = false,
  });

  final String title;
  final String? initialValue;
  final String? labelText;
  final String? hintText;
  final bool numeric;
  final bool capitalizeWords;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: widget.capitalizeWords
          ? TextCapitalization.words
          : TextCapitalization.none,
      keyboardType: widget.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: widget.numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixText: widget.numeric ? '₹' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _NewBillSheet extends StatefulWidget {
  const _NewBillSheet();

  @override
  State<_NewBillSheet> createState() => _NewBillSheetState();
}

class _NewBillSheetState extends State<_NewBillSheet> {
  final _name = TextEditingController();
  final _receipt = TextEditingController();
  final _people = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  final _removedPeople = <TextEditingController>[];

  @override
  void dispose() {
    _name.dispose();
    _receipt.dispose();
    for (final controller in [..._people, ..._removedPeople]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _createBill() {
    final clean = _people
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (_name.text.trim().isEmpty || clean.length < 2) {
      _message('Add a bill name and at least two people.');
      return;
    }
    final seen = <String>{};
    if (clean.any((value) => !seen.add(value.toLowerCase()))) {
      _message('Person names must be unique.');
      return;
    }
    final amount = _receipt.text.trim().isEmpty
        ? null
        : parsePaise(_receipt.text);
    if (_receipt.text.trim().isNotEmpty && (amount == null || amount < 0)) {
      _message('Enter a valid receipt total.');
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      Bill(
        id: makeId(),
        name: _name.text.trim(),
        receiptTotalPaise: amount,
        people: clean.map((value) => Person(makeId(), value)).toList(),
        items: [],
        payments: [],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Start a bill',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Bill name',
              hintText: 'Office celebration',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _receipt,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Receipt total (optional)',
              prefixText: '₹',
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'People',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text('${_people.length}'),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(_people.length, (index) {
            final controller = _people[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey(controller),
                      controller: controller,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Person ${index + 1}',
                      ),
                    ),
                  ),
                  if (_people.length > 2)
                    IconButton(
                      onPressed: () => setState(() {
                        _removedPeople.add(_people.removeAt(index));
                      }),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => setState(() {
              _people.add(TextEditingController());
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add person'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _createBill,
              child: const Text('Create bill'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ItemEditorState extends State<ItemEditor> {
  late final TextEditingController _name, _quantity, _unitPrice, _total;
  late SplitType _mode;
  late Set<String> _selected;
  late Map<String, int> _quantities;
  late Map<String, TextEditingController> _custom;
  bool _directTotal = false;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _quantity = TextEditingController(text: '${e?.quantity ?? 1}');
    _unitPrice = TextEditingController(
      text: ((e?.unitPricePaise ?? 0) / 100).toStringAsFixed(
        (e?.unitPricePaise ?? 0) % 100 == 0 ? 0 : 2,
      ),
    );
    _total = TextEditingController(
      text: e == null
          ? ''
          : (e.totalPaise / 100).toStringAsFixed(
              e.totalPaise % 100 == 0 ? 0 : 2,
            ),
    );
    _mode = e?.splitType ?? SplitType.everyone;
    final storedPeople =
        e?.allocations.map((a) => a.personId).toSet() ??
        widget.bill.people.map((p) => p.id).toSet();
    _selected = _mode == SplitType.everyoneExcept
        ? widget.bill.people.map((p) => p.id).toSet().difference(storedPeople)
        : storedPeople;
    _quantities = {
      for (final p in widget.bill.people)
        p.id:
            e?.allocations
                .where((a) => a.personId == p.id)
                .fold<int>(0, (s, a) => s + a.quantity) ??
            0,
    };
    _custom = {
      for (final p in widget.bill.people)
        p.id: TextEditingController(
          text:
              ((e?.allocations
                              .where((a) => a.personId == p.id)
                              .fold<int>(0, (s, a) => s + a.amountPaise) ??
                          0) /
                      100)
                  .toStringAsFixed(2),
        ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _total.dispose();
    for (final c in _custom.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _qty => int.tryParse(_quantity.text) ?? 0;
  int get _price => parsePaise(_unitPrice.text) ?? 0;
  int get _itemTotal =>
      _directTotal ? (parsePaise(_total.text) ?? 0) : _qty * _price;
  int get _quantityAssigned => _quantities.values.fold(0, (s, q) => s + q);
  int get _customSum => _selected.fold(
    0,
    (s, id) => s + (parsePaise(_custom[id]?.text ?? '') ?? 0),
  );
  List<Person> get _people => widget.bill.people;
  Map<String, int> get _consumptionWeights {
    final weights = <String, int>{};
    for (final item in widget.bill.items.where(
      (item) => !item.isCharge && item.id != widget.existing?.id,
    )) {
      for (final allocation in item.allocations) {
        weights[allocation.personId] =
            (weights[allocation.personId] ?? 0) + allocation.amountPaise;
      }
    }
    return weights;
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _itemTotal - _customSum;
    final activePeople = _mode == SplitType.everyoneExcept
        ? _people.length - _selected.length
        : _selected.length;
    final canSave =
        _name.text.trim().isNotEmpty &&
        _itemTotal > 0 &&
        activePeople > 0 &&
        switch (_mode) {
          SplitType.quantity => _quantityAssigned == _qty && _qty > 0,
          SplitType.custom => remaining == 0,
          SplitType.proportional => _consumptionWeights.isNotEmpty,
          _ => true,
        };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isCharge
              ? 'Add charge'
              : widget.existing == null
              ? 'Add item'
              : 'Edit item',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: widget.isCharge ? 'Charge name' : 'Item name',
                      hintText: widget.isCharge
                          ? 'GST, service charge'
                          : 'Biryani, drinks',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _quantity,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) {
                            _directTotal = false;
                            setState(() {});
                          },
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _unitPrice,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          onChanged: (_) {
                            _directTotal = false;
                            setState(() {});
                          },
                          decoration: const InputDecoration(
                            labelText: 'Price each',
                            prefixText: '₹',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total  ${inr(_itemTotal)}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final value = await _showTextInputDialog(
                            context: context,
                            title: 'Enter total directly',
                            initialValue: _total.text,
                            numeric: true,
                          );
                          if (value != null && (parsePaise(value) ?? 0) > 0) {
                            _directTotal = true;
                            _total.text = value;
                            _quantity.text = '1';
                            _unitPrice.text = value;
                            setState(() {});
                          }
                        },
                        child: const Text('Enter total'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.isCharge
                        ? 'How should this charge be split?'
                        : 'Who consumed this?',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _modeChip(SplitType.everyone),
                      _modeChip(SplitType.everyoneExcept),
                      _modeChip(SplitType.specificMembers),
                      if (!widget.isCharge) _modeChip(SplitType.quantity),
                      _modeChip(SplitType.custom),
                      if (widget.isCharge) _modeChip(SplitType.proportional),
                    ],
                  ),
                  if (_mode == SplitType.everyone)
                    _summary(
                      '${_people.length} people · ${inr(_itemTotal ~/ (_people.isEmpty ? 1 : _people.length))} base share each',
                      Icons.groups_2_outlined,
                    ),
                  if (_mode == SplitType.everyoneExcept ||
                      _mode == SplitType.specificMembers ||
                      _mode == SplitType.custom) ...[
                    const SizedBox(height: 12),
                    if (_mode == SplitType.everyoneExcept)
                      Text(
                        'Select people to exclude',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ..._people.map((p) => _personSelectRow(p)),
                    if (_mode == SplitType.specificMembers)
                      _summary(
                        '${_selected.length} selected · ${inr(_itemTotal ~/ (_selected.isEmpty ? 1 : _selected.length))} base share each',
                        Icons.people_outline,
                      ),
                    if (_mode == SplitType.everyoneExcept)
                      _summary(
                        '${_people.length - _selected.length} people included · ${inr(_itemTotal ~/ ((_people.length - _selected.length).clamp(1, _people.length)))} base share each',
                        Icons.groups_2_outlined,
                      ),
                    if (_mode == SplitType.custom)
                      _summary(
                        remaining == 0
                            ? '✓ Split complete'
                            : remaining > 0
                            ? 'Remaining: ${inr(remaining, decimals: true)}'
                            : 'Over allocated: ${inr(-remaining, decimals: true)}',
                        remaining == 0
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_rounded,
                        good: remaining == 0,
                      ),
                  ],
                  if (_mode == SplitType.quantity) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Assign units · $_quantityAssigned / $_qty',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    ..._people.map(_quantityRow),
                    _summary(
                      'Total ${inr(_itemTotal)} · ${_qty == 0 ? inr(0) : inr(_price)} per unit',
                      Icons.toll_outlined,
                      good: _qty > 0 && _quantityAssigned == _qty,
                    ),
                  ],
                  if (_mode == SplitType.proportional)
                    _summary(
                      _consumptionWeights.isEmpty
                          ? 'Add and allocate food items first to split proportionally.'
                          : 'Split according to each person’s existing item consumption.',
                      Icons.pie_chart_outline,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: canSave ? _saveItem : null,
                  child: Text(
                    widget.existing == null
                        ? 'Add ${widget.isCharge ? 'charge' : 'item'}'
                        : 'Save changes',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(SplitType type) => ChoiceChip(
    label: Text(splitLabel(type)),
    selected: _mode == type,
    onSelected: (_) => setState(() {
      final previous = _mode;
      final allIds = _people.map((p) => p.id).toSet();
      if (type == SplitType.everyone) _selected = allIds;
      if (type == SplitType.everyoneExcept) {
        _selected =
            previous == SplitType.specificMembers ||
                previous == SplitType.custom
            ? allIds.difference(_selected)
            : <String>{};
      }
      if (type == SplitType.specificMembers || type == SplitType.custom) {
        if (previous == SplitType.everyoneExcept) {
          _selected = allIds.difference(_selected);
        } else if (previous == SplitType.everyone &&
            type == SplitType.specificMembers) {
          _selected = {};
        } else if (previous == SplitType.everyone && type == SplitType.custom) {
          _selected = allIds;
        }
      }
      if (type == SplitType.quantity) {
        _selected = {};
        _quantities.updateAll((id, q) => 0);
      }
      _mode = type;
    }),
  );
  Widget _summary(String text, IconData icon, {bool good = false}) => Card(
    color: good ? Colors.green.withValues(alpha: .08) : null,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: good ? Colors.green : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _personSelectRow(Person p) {
    final checked = _selected.contains(p.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 5),
      child: CheckboxListTile(
        value: checked,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(p.name),
        onChanged: (v) => setState(() {
          if (v == true) {
            _selected.add(p.id);
          } else {
            _selected.remove(p.id);
          }
        }),
        secondary: _mode == SplitType.custom && _selected.contains(p.id)
            ? SizedBox(
                width: 112,
                child: TextField(
                  controller: _customAmount(p.id),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  textAlign: TextAlign.end,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: '₹',
                  ),
                ),
              )
            : null,
      ),
    );
  }

  TextEditingController _customAmount(String id) =>
      _custom.putIfAbsent(id, () => TextEditingController());
  Widget _quantityRow(Person p) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(p.name)),
        IconButton(
          onPressed: (_quantities[p.id] ?? 0) > 0
              ? () => setState(
                  () => _quantities[p.id] = (_quantities[p.id] ?? 0) - 1,
                )
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '${_quantities[p.id] ?? 0}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        IconButton(
          onPressed: _quantityAssigned < _qty
              ? () => setState(() {
                  _quantities[p.id] = (_quantities[p.id] ?? 0) + 1;
                  _selected.add(p.id);
                })
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
  void _saveItem() {
    final qty = _directTotal ? 1 : _qty;
    final price = _directTotal ? (parsePaise(_total.text) ?? 0) : _price;
    final total = qty * price;
    if (_name.text.trim().isEmpty || qty <= 0 || price <= 0) return;
    final ids = _people.map((p) => p.id).toList();
    List<ItemAllocation> allocations;
    switch (_mode) {
      case SplitType.everyone:
        allocations = BillCalculator.equalSplit(total, ids);
        break;
      case SplitType.everyoneExcept:
        final excluded = _selected;
        allocations = BillCalculator.equalSplit(
          total,
          ids.where((id) => !excluded.contains(id)).toList(),
        );
        break;
      case SplitType.specificMembers:
        allocations = BillCalculator.equalSplit(
          total,
          ids.where(_selected.contains).toList(),
        );
        break;
      case SplitType.quantity:
        allocations = BillCalculator.quantitySplit(price, _quantities);
        break;
      case SplitType.custom:
        allocations = [
          for (final id in ids.where(_selected.contains))
            ItemAllocation(
              personId: id,
              amountPaise: parsePaise(_customAmount(id).text) ?? 0,
            ),
        ];
        break;
      case SplitType.proportional:
        allocations = BillCalculator.proportionalSplit(
          total,
          _consumptionWeights,
        );
        break;
    }
    if (_mode == SplitType.quantity &&
        allocations.fold<int>(0, (s, a) => s + a.quantity) != qty) {
      return;
    }
    if (allocations.fold<int>(0, (s, a) => s + a.amountPaise) != total) return;
    Navigator.pop(
      context,
      BillItem(
        id: widget.existing?.id ?? makeId(),
        name: _name.text.trim(),
        quantity: qty,
        unitPricePaise: price,
        splitType: _mode,
        allocations: allocations,
        isCharge: widget.isCharge,
      ),
    );
  }
}

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.bill, required this.onChanged});
  final Bill bill;
  final Future<void> Function() onChanged;
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  Future<void> _add() async {
    final value = await _showTextInputDialog(
      context: context,
      title: 'Add person',
      hintText: 'Name',
      capitalizeWords: true,
    );
    if (value == null) return;
    final name = value.trim();
    if (name.isEmpty ||
        widget.bill.people.any(
          (p) => p.name.toLowerCase() == name.toLowerCase(),
        )) {
      _notice(
        name.isEmpty ? 'Enter a name.' : 'That name is already in the bill.',
      );
      return;
    }
    widget.bill.people.add(Person(makeId(), name));
    await widget.onChanged();
    setState(() {});
  }

  Future<void> _edit(Person p) async {
    final value = await _showTextInputDialog(
      context: context,
      title: 'Edit person',
      initialValue: p.name,
      labelText: 'Name',
    );
    if (value == null) return;
    final n = value.trim();
    if (n.isNotEmpty &&
        !widget.bill.people.any(
          (x) => x.id != p.id && x.name.toLowerCase() == n.toLowerCase(),
        )) {
      p.name = n;
      await widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _remove(Person p) async {
    if (widget.bill.people.length <= 2) {
      _notice('A bill needs at least two people.');
      return;
    }
    final referenced =
        widget.bill.items.any(
          (i) => i.allocations.any((a) => a.personId == p.id),
        ) ||
        widget.bill.payments.any((x) => x.personId == p.id);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: Text(
          referenced
              ? 'This person has item allocations or payments. Their allocations will be removed and affected item totals may become unmatched. Continue?'
              : 'Remove this person from the bill?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    for (final item in widget.bill.items) {
      item.allocations.removeWhere((a) => a.personId == p.id);
    }
    widget.bill.payments.removeWhere((x) => x.personId == p.id);
    widget.bill.people.remove(p);
    await widget.onChanged();
    setState(() {});
  }

  void _notice(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('People')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          '${widget.bill.people.length} people · Tap a name to edit',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...widget.bill.people.map(
          (p) => Card(
            margin: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              onTap: () => _edit(p),
              leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
              title: Text(p.name),
              trailing: IconButton(
                onPressed: () => _remove(p),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add person'),
        ),
      ],
    ),
  );
}

class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.bill,
    required this.person,
    required this.onChanged,
  });
  final Bill bill;
  final Person person;
  final Future<void> Function() onChanged;
  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  Future<void> _payment([bool full = false]) async {
    final b = widget.bill, person = widget.person;
    final owed = BillCalculator.personTotals(b)[person.id] ?? 0,
        paid = BillCalculator.paidTotals(b)[person.id] ?? 0,
        remaining = (owed - paid).clamp(0, owed).toInt();
    if (remaining <= 0) return;
    final value = full
        ? (remaining / 100).toStringAsFixed(2)
        : await _showTextInputDialog(
            context: context,
            title: 'Add payment',
            labelText: 'Amount · ${inr(remaining)} remaining',
            numeric: true,
          );
    if (value == null) return;
    final amount = full ? remaining : parsePaise(value);
    if (amount == null || amount <= 0 || amount > remaining) {
      _note('Payment must be positive and no greater than ${inr(remaining)}.');
      return;
    }
    b.payments.add(
      Payment(
        id: makeId(),
        personId: person.id,
        amountPaise: amount,
        createdAt: DateTime.now(),
      ),
    );
    await widget.onChanged();
    setState(() {});
  }

  void _note(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  @override
  Widget build(BuildContext context) {
    final b = widget.bill,
        p = widget.person,
        totals = BillCalculator.personTotals(b),
        payments = BillCalculator.paidTotals(b);
    final total = totals[p.id] ?? 0,
        paid = payments[p.id] ?? 0,
        remaining = (total - paid).clamp(0, total).toInt();
    final contributions = b.items
        .where((i) => BillCalculator.itemShare(i, p.id) > 0)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL OWED',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(letterSpacing: 1),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    inr(total, decimals: true),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text('Paid  ${inr(paid)}')),
                      Expanded(
                        child: Text(
                          'Remaining  ${inr(remaining)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    remaining == 0
                        ? '✓ Paid'
                        : paid > 0
                        ? 'Partially paid'
                        : 'Unpaid',
                    style: TextStyle(
                      color: remaining == 0
                          ? Colors.green
                          : paid > 0
                          ? Colors.orange
                          : Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Consumed',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...contributions.map(
            (item) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(item.name),
              subtitle:
                  item.allocations
                      .where((a) => a.personId == p.id)
                      .any((a) => a.quantity > 0)
                  ? Text(
                      'Quantity: ${item.allocations.where((a) => a.personId == p.id).fold<int>(0, (s, a) => s + a.quantity)}',
                    )
                  : null,
              trailing: Text(
                inr(BillCalculator.itemShare(item, p.id), decimals: true),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text(
              'Total',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Text(
              inr(total, decimals: true),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 16),
          if (remaining > 0)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _payment(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add payment'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _payment(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark full amount paid'),
                ),
              ],
            ),
          if (b.payments.any((x) => x.personId == p.id)) ...[
            const SizedBox(height: 20),
            Text(
              'Payments',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            ...b.payments
                .where((x) => x.personId == p.id)
                .map(
                  (x) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(inr(x.amountPaise)),
                    subtitle: Text(
                      MaterialLocalizations.of(context)
                          .formatMediumDate(x.createdAt),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _sharePerson,
            icon: const Icon(Icons.ios_share),
            label: const Text('Share this breakdown'),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePerson() async {
    final b = widget.bill, p = widget.person;
    final total = BillCalculator.personTotals(b)[p.id] ?? 0,
        paid = BillCalculator.paidTotals(b)[p.id] ?? 0;
    final lines = <String>['${b.name} · ${p.name}', 'Total: ${inr(total)}', ''];
    for (final i in b.items) {
      final share = BillCalculator.itemShare(i, p.id);
      if (share > 0) lines.add('- ${i.name}: ${inr(share)}');
    }
    lines.addAll([
      '',
      'Paid: ${inr(paid)}',
      'Remaining: ${inr((total - paid).clamp(0, total).toInt())}',
    ]);
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }
}

class SettlementScreen extends StatelessWidget {
  const SettlementScreen({super.key, required this.bill});
  final Bill bill;
  @override
  Widget build(BuildContext context) {
    final owed = BillCalculator.personTotals(bill),
        paid = BillCalculator.paidTotals(bill),
        total = BillCalculator.allocatedTotal(bill),
        paidTotal = bill.payments.fold<int>(0, (s, p) => s + p.amountPaise),
        diff = bill.receiptTotalPaise == null
            ? null
            : bill.receiptTotalPaise! - total;
    return Scaffold(
      appBar: AppBar(title: const Text('Bill summary')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _row(
                    'Food subtotal',
                    inr(
                      bill.items
                          .where((i) => !i.isCharge)
                          .fold<int>(0, (s, i) => s + i.totalPaise),
                      decimals: true,
                    ),
                  ),
                  _row(
                    'Additional charges',
                    inr(
                      bill.items
                          .where((i) => i.isCharge)
                          .fold<int>(0, (s, i) => s + i.totalPaise),
                      decimals: true,
                    ),
                  ),
                  _row(
                    'Receipt total',
                    bill.receiptTotalPaise == null
                        ? 'Not set'
                        : inr(bill.receiptTotalPaise!, decimals: true),
                  ),
                  _row('Allocated total', inr(total, decimals: true)),
                  _row('Paid', inr(paidTotal, decimals: true)),
                  const Divider(height: 24),
                  _row(
                    'Outstanding',
                    inr(
                      (total - paidTotal).clamp(0, total).toInt(),
                      decimals: true,
                    ),
                    bold: true,
                  ),
                  if (diff != null)
                    _row(
                      'Receipt check',
                      diff == 0
                          ? '✓ Matched'
                          : diff > 0
                          ? '${inr(diff, decimals: true)} unallocated'
                          : '${inr(-diff, decimals: true)} over allocated',
                      bold: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'People',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...bill.people.map((p) {
            final o = owed[p.id] ?? 0,
                pay = paid[p.id] ?? 0,
                rem = (o - pay).clamp(0, o).toInt();
            return Card(
              margin: const EdgeInsets.only(bottom: 7),
              child: ListTile(
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Owes ${inr(o)} · Paid ${inr(pay)}'),
                trailing: Text(
                  rem == 0
                      ? 'Paid ✓'
                      : rem == o
                      ? 'Unpaid'
                      : 'Partial',
                  style: TextStyle(
                    color: rem == 0
                        ? Colors.green
                        : rem == o
                        ? Theme.of(context).colorScheme.error
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share group summary'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: bold ? 17 : null,
          ),
        ),
      ],
    ),
  );
  Future<void> _share(BuildContext context) async {
    final total = BillCalculator.allocatedTotal(bill),
        paid = BillCalculator.paidTotals(bill);
    final text = StringBuffer('${bill.name}\nTotal bill: ${inr(total)}\n\n');
    for (final p in bill.people) {
      final owes = BillCalculator.personTotals(bill)[p.id] ?? 0,
          personPaid = paid[p.id] ?? 0;
      text.writeln(
        '${p.name}: ${inr(owes)} · Paid ${inr(personPaid)} · Remaining ${inr((owes - personPaid).clamp(0, owes).toInt())}',
      );
    }
    await SharePlus.instance.share(ShareParams(text: text.toString()));
  }
}
