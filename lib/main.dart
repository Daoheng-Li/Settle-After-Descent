import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SettleAfterDescent());
}

class SettleAfterDescent extends StatelessWidget {
  const SettleAfterDescent({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '下山算账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const TripListScreen(),
    );
  }
}

class AppTheme {
  static ThemeData light() {
    const seed = Color(0xFF1E4D3A);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        surface: const Color(0xFFF6F3EE),
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F3EE),
      fontFamily: null,
      textTheme: Typography.blackCupertino.apply(
        bodyColor: const Color(0xFF171A17),
        displayColor: const Color(0xFF171A17),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.86),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

enum SplitKind { average, fixed, tiered, discount, adjustment }

extension SplitKindText on SplitKind {
  String get zh => switch (this) {
        SplitKind.average => '平均分摊',
        SplitKind.fixed => '固定金额',
        SplitKind.tiered => '价格等级',
        SplitKind.discount => '优惠抵扣',
        SplitKind.adjustment => '手动调整',
      };

  String get en => switch (this) {
        SplitKind.average => 'Average Split',
        SplitKind.fixed => 'Fixed Amount',
        SplitKind.tiered => 'Price Tiers',
        SplitKind.discount => 'Discount',
        SplitKind.adjustment => 'Adjustment',
      };
}

class Member {
  Member({
    required this.id,
    required this.name,
    required this.avatarColor,
    this.note = '',
  });

  final String id;
  String name;
  Color avatarColor;
  String note;
}

class Payment {
  Payment({
    required this.memberId,
    required this.amount,
    this.method = '微信',
    this.note = '',
  });

  final String memberId;
  final double amount;
  final String method;
  final String note;
}

class PriceTier {
  PriceTier({
    required this.id,
    required this.name,
    required this.amount,
  });

  final String id;
  final String name;
  final double amount;
}

class SplitRule {
  SplitRule.average({
    required this.participantIds,
  })  : kind = SplitKind.average,
        fixedAmounts = const {},
        tiers = const [],
        memberTierIds = const {},
        targetSubExpenseId = null;

  SplitRule.fixed({
    required this.fixedAmounts,
  })  : kind = SplitKind.fixed,
        participantIds = fixedAmounts.keys.toList(),
        tiers = const [],
        memberTierIds = const {},
        targetSubExpenseId = null;

  SplitRule.tiered({
    required this.tiers,
    required this.memberTierIds,
  })  : kind = SplitKind.tiered,
        participantIds = memberTierIds.keys.toList(),
        fixedAmounts = const {},
        targetSubExpenseId = null;

  SplitRule.discount({
    required this.participantIds,
    this.targetSubExpenseId,
  })  : kind = SplitKind.discount,
        fixedAmounts = const {},
        tiers = const [],
        memberTierIds = const {};

  SplitRule.adjustment({
    required this.fixedAmounts,
  })  : kind = SplitKind.adjustment,
        participantIds = fixedAmounts.keys.toList(),
        tiers = const [],
        memberTierIds = const {},
        targetSubExpenseId = null;

  final SplitKind kind;
  final List<String> participantIds;
  final Map<String, double> fixedAmounts;
  final List<PriceTier> tiers;
  final Map<String, String> memberTierIds;
  final String? targetSubExpenseId;
}

class SubExpense {
  SubExpense({
    required this.id,
    required this.name,
    required this.amount,
    required this.rule,
    this.note = '',
  });

  final String id;
  String name;
  double amount;
  SplitRule rule;
  String note;
}

class Expense {
  Expense({
    required this.id,
    required this.name,
    required this.timeLabel,
    required this.month,
    required this.day,
    required this.hour,
    required this.amount,
    required this.payments,
    required this.participantIds,
    this.rule,
    this.subExpenses = const [],
    this.note = '',
  });

  final String id;
  String name;
  String timeLabel;
  int month;
  int day;
  int hour;
  double amount;
  List<Payment> payments;
  List<String> participantIds;
  SplitRule? rule;
  List<SubExpense> subExpenses;
  String note;

  bool get isComposite => subExpenses.isNotEmpty;

  int get sortKey => month * 31 * 24 + day * 24 + hour;

  String get monthDayLabel =>
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

class Trip {
  Trip({
    required this.id,
    required this.name,
    required this.dateLabel,
    required this.members,
    required this.expenses,
    this.backgroundAsset,
    this.backgroundImagePath,
    this.backgroundColorValue = 0xFFFFFFFF,
  });

  final String id;
  String name;
  String dateLabel;
  List<Member> members;
  List<Expense> expenses;
  String? backgroundAsset;
  String? backgroundImagePath;
  int backgroundColorValue;
}

class MemberLedger {
  const MemberLedger({
    required this.memberId,
    required this.paid,
    required this.owed,
  });

  final String memberId;
  final double paid;
  final double owed;
  double get net => paid - owed;
}

class SettlementTransfer {
  const SettlementTransfer({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
  });

  final String fromMemberId;
  final String toMemberId;
  final double amount;
}

class ExpenseCalculator {
  static List<MemberLedger> ledgersFor(Trip trip) {
    final paid = {for (final m in trip.members) m.id: 0.0};
    final owed = {for (final m in trip.members) m.id: 0.0};

    for (final expense in trip.expenses) {
      for (final payment in expense.payments) {
        paid[payment.memberId] = (paid[payment.memberId] ?? 0) + payment.amount;
      }

      if (expense.isComposite) {
        for (final sub in expense.subExpenses) {
          _addAllocation(owed, _allocate(sub.amount, sub.rule));
        }
      } else if (expense.rule != null) {
        _addAllocation(owed, _allocate(expense.amount, expense.rule!));
      }
    }

    return trip.members
        .map((m) => MemberLedger(
              memberId: m.id,
              paid: _money(paid[m.id] ?? 0),
              owed: _money(owed[m.id] ?? 0),
            ))
        .toList();
  }

  static List<SettlementTransfer> shortestTransfers(
      List<MemberLedger> ledgers) {
    final debtors = ledgers
        .where((l) => l.net < -0.004)
        .map((l) => _Balance(l.memberId, -l.net))
        .toList();
    final creditors = ledgers
        .where((l) => l.net > 0.004)
        .map((l) => _Balance(l.memberId, l.net))
        .toList();
    final transfers = <SettlementTransfer>[];
    var i = 0;
    var j = 0;
    while (i < debtors.length && j < creditors.length) {
      final amount = _money(min(debtors[i].amount, creditors[j].amount));
      if (amount > 0) {
        transfers.add(SettlementTransfer(
          fromMemberId: debtors[i].memberId,
          toMemberId: creditors[j].memberId,
          amount: amount,
        ));
      }
      debtors[i].amount = _money(debtors[i].amount - amount);
      creditors[j].amount = _money(creditors[j].amount - amount);
      if (debtors[i].amount <= 0.004) i++;
      if (creditors[j].amount <= 0.004) j++;
    }
    return transfers;
  }

  static List<SettlementTransfer> hubTransfers(
    List<MemberLedger> ledgers,
    String hubId,
  ) {
    final incoming = <SettlementTransfer>[];
    final outgoing = <SettlementTransfer>[];
    for (final ledger in ledgers) {
      if (ledger.memberId == hubId) continue;
      if (ledger.net < -0.004) {
        incoming.add(SettlementTransfer(
          fromMemberId: ledger.memberId,
          toMemberId: hubId,
          amount: _money(-ledger.net),
        ));
      }
      if (ledger.net > 0.004) {
        outgoing.add(SettlementTransfer(
          fromMemberId: hubId,
          toMemberId: ledger.memberId,
          amount: _money(ledger.net),
        ));
      }
    }
    return [...incoming, ...outgoing];
  }

  static Map<String, double> allocationForExpense(Expense expense) {
    final result = <String, double>{};
    if (expense.isComposite) {
      for (final sub in expense.subExpenses) {
        _addAllocation(result, _allocate(sub.amount, sub.rule));
      }
    } else if (expense.rule != null) {
      _addAllocation(result, _allocate(expense.amount, expense.rule!));
    }
    return result.map((key, value) => MapEntry(key, _money(value)));
  }

  static Map<String, double> _allocate(double amount, SplitRule rule) {
    switch (rule.kind) {
      case SplitKind.average:
      case SplitKind.discount:
        if (rule.participantIds.isEmpty) return {};
        final per = _money(amount / rule.participantIds.length);
        final result = {for (final id in rule.participantIds) id: per};
        final delta = _money(amount - result.values.fold(0.0, (a, b) => a + b));
        if (delta.abs() >= 0.01) {
          final first = rule.participantIds.first;
          result[first] = _money((result[first] ?? 0) + delta);
        }
        return result;
      case SplitKind.fixed:
        return rule.fixedAmounts
            .map((key, value) => MapEntry(key, _money(value)));
      case SplitKind.tiered:
        final tierMap = {for (final tier in rule.tiers) tier.id: tier};
        return {
          for (final entry in rule.memberTierIds.entries)
            entry.key: _money(tierMap[entry.value]?.amount ?? 0),
        };
      case SplitKind.adjustment:
        return rule.fixedAmounts
            .map((key, value) => MapEntry(key, _money(value)));
    }
  }

  static void _addAllocation(
    Map<String, double> target,
    Map<String, double> allocation,
  ) {
    for (final entry in allocation.entries) {
      target[entry.key] = (target[entry.key] ?? 0) + entry.value;
    }
  }
}

class _Balance {
  _Balance(this.memberId, this.amount);

  final String memberId;
  double amount;
}

double _money(double value) => (value * 100).roundToDouble() / 100;

String yuan(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign¥${value.abs().toStringAsFixed(2)}';
}

// 宽度上限按“英文字符”计：英文/数字算 1，汉字等全角字符算 2。
// 默认上限 9，约等于 9 个英文字符或 4-5 个汉字。
String clipName(String name, {int maxUnits = 9}) {
  var units = 0;
  final buffer = StringBuffer();
  for (final ch in name.characters) {
    final width = _charWidth(ch);
    if (units + width > maxUnits) {
      return '$buffer...';
    }
    units += width;
    buffer.write(ch);
  }
  return name;
}

int _charWidth(String ch) {
  if (ch.isEmpty) return 1;
  final code = ch.runes.first;
  return code >= 0x1100 ? 2 : 1;
}

const _tripsStorageKey = 'settle_after_descent_trips_v1';

class AppState extends ChangeNotifier {
  AppState() : trips = [_sampleTrip()] {
    _load();
  }

  final List<Trip> trips;

  Trip get activeTrip => trips.first;

  Trip tripById(String tripId) =>
      trips.firstWhere((trip) => trip.id == tripId, orElse: () => activeTrip);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tripsStorageKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    trips
      ..clear()
      ..addAll(decoded.map(
          (item) => _tripFromJson(Map<String, Object?>.from(item as Map))));
    if (trips.isEmpty) trips.add(_sampleTrip());
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tripsStorageKey,
      jsonEncode(trips.map(_tripToJson).toList()),
    );
  }

  void addTrip(
    String name, {
    int backgroundColorValue = 0xFFEAF1EC,
    String? backgroundImagePath,
  }) {
    trips.insert(
      0,
      Trip(
        id: _id(),
        name: name,
        dateLabel: '本地旅行',
        members: [],
        expenses: [],
        backgroundColorValue: backgroundColorValue,
        backgroundImagePath: backgroundImagePath,
      ),
    );
    _save();
    notifyListeners();
  }

  void addMember(String tripId, String name) {
    final trip = tripById(tripId);
    final colors = [
      const Color(0xFF315C48),
      const Color(0xFF7A4D2F),
      const Color(0xFF435B7B),
      const Color(0xFF6E4B6A),
      const Color(0xFF5E6238),
    ];
    trip.members.add(Member(
      id: _id(),
      name: name,
      avatarColor: colors[trip.members.length % colors.length],
    ));
    _save();
    notifyListeners();
  }

  void addQuickAverageExpense({
    required String tripId,
    required String name,
    required double amount,
    required String payerId,
    required List<String> participantIds,
  }) {
    tripById(tripId).expenses.add(Expense(
          id: _id(),
          name: name,
          timeLabel: '刚刚',
          month: 0,
          day: 0,
          hour: TimeOfDay.now().hour,
          amount: amount,
          payments: [Payment(memberId: payerId, amount: amount)],
          participantIds: participantIds,
          rule: SplitRule.average(participantIds: participantIds),
        ));
    _save();
    notifyListeners();
  }

  void upsertExpense({
    required String tripId,
    required Expense expense,
  }) {
    final trip = tripById(tripId);
    final index = trip.expenses.indexWhere((item) => item.id == expense.id);
    if (index >= 0) {
      trip.expenses[index] = expense;
    } else {
      trip.expenses.add(expense);
    }
    _save();
    notifyListeners();
  }

  void updateTripBackground({
    required String tripId,
    String? asset,
    String? imagePath,
    required int colorValue,
  }) {
    final trip = tripById(tripId);
    trip.backgroundAsset = asset;
    trip.backgroundImagePath = imagePath;
    trip.backgroundColorValue = colorValue;
    _save();
    notifyListeners();
  }

  void deleteTrip(String tripId) {
    trips.removeWhere((trip) => trip.id == tripId);
    _save();
    notifyListeners();
  }

  void deleteExpense({
    required String tripId,
    required String expenseId,
  }) {
    tripById(tripId).expenses.removeWhere((item) => item.id == expenseId);
    _save();
    notifyListeners();
  }
}

Trip _sampleTrip() {
  final jab =
      Member(id: 'm1', name: 'JabJabich', avatarColor: const Color(0xFF315C48));
  final lucky =
      Member(id: 'm2', name: 'Lucky宇', avatarColor: const Color(0xFF7A4D2F));
  final zhou =
      Member(id: 'm3', name: '周某人', avatarColor: const Color(0xFF435B7B));
  final ganzi =
      Member(id: 'm4', name: '甘孜王', avatarColor: const Color(0xFF6E4B6A));
  final bianmu =
      Member(id: 'm5', name: '雅拉王', avatarColor: const Color(0xFF5E6238));
  final litang =
      Member(id: 'm6', name: '理塘王', avatarColor: const Color(0xFF8A6B3B));
  final genie =
      Member(id: 'm7', name: '格聂王', avatarColor: const Color(0xFF466A67));
  final prince =
      Member(id: 'm8', name: '甘孜王子', avatarColor: const Color(0xFF8B4A4A));
  final dora =
      Member(id: 'm9', name: 'Dora', avatarColor: const Color(0xFF4E587E));
  final germain =
      Member(id: 'm10', name: 'Germain', avatarColor: const Color(0xFF7C5A7D));
  final rengar =
      Member(id: 'm11', name: 'RENGAR', avatarColor: const Color(0xFF405F3C));
  final members = [
    jab,
    lucky,
    zhou,
    ganzi,
    bianmu,
    litang,
    genie,
    prince,
    dora,
    germain,
    rengar,
  ];
  final ids = members.map((m) => m.id).toList();
  final trainIds =
      members.where((m) => m.id != rengar.id).map((m) => m.id).toList();
  const trainAmount = 3801.5;
  const dessertAmount = 131.6;
  const guizhouHotpotShared = 968.4;
  const guizhouHotpotTotal = guizhouHotpotShared + dessertAmount;

  return Trip(
    id: 't1',
    name: '2026端午节雅拉正穿',
    dateLabel: 'Jun 2026',
    backgroundAsset: 'assets_yala_default.png',
    backgroundColorValue: 0xFFEAF1EC,
    members: members,
    expenses: [
      Expense(
        id: 'e1',
        name: '0619康定牦牛肉火锅',
        timeLabel: '',
        month: 6,
        day: 19,
        hour: 19,
        note: '晚餐',
        amount: 1280,
        payments: [Payment(memberId: jab.id, amount: 1280)],
        participantIds: ids,
        rule: SplitRule.average(participantIds: ids),
      ),
      Expense(
        id: 'e2',
        name: '0622成都贵州菜火锅',
        timeLabel: '',
        month: 6,
        day: 22,
        hour: 18,
        note: '晚餐',
        amount: guizhouHotpotTotal,
        payments: [Payment(memberId: lucky.id, amount: guizhouHotpotTotal)],
        participantIds: ids,
        subExpenses: [
          SubExpense(
            id: 's2_1',
            name: '个人甜点',
            amount: dessertAmount,
            rule: SplitRule.fixed(
              fixedAmounts: {
                jab.id: 12.3,
                lucky.id: 14.8,
                zhou.id: 11.7,
                ganzi.id: 13.6,
                bianmu.id: 14.1,
                litang.id: 12.9,
                genie.id: 11.4,
                prince.id: 15.0,
                dora.id: 13.2,
                rengar.id: 12.6,
              },
            ),
          ),
          SubExpense(
            id: 's2_2',
            name: '火锅锅底和涮菜',
            amount: guizhouHotpotShared,
            rule: SplitRule.average(participantIds: ids),
          ),
        ],
      ),
      Expense(
        id: 'e3',
        name: '拉猪车',
        timeLabel: '',
        month: 6,
        day: 20,
        hour: 9,
        note: '路程',
        amount: 880,
        payments: [Payment(memberId: ganzi.id, amount: 880)],
        participantIds: ids,
        rule: SplitRule.average(participantIds: ids),
      ),
      Expense(
        id: 'e4',
        name: '北京-->成都动车',
        timeLabel: '',
        month: 6,
        day: 18,
        hour: 20,
        note: '出发交通',
        amount: trainAmount,
        payments: [Payment(memberId: dora.id, amount: trainAmount)],
        participantIds: trainIds,
        rule: SplitRule.tiered(
          tiers: [
            PriceTier(id: 'train_student_upper', name: '学生票上铺', amount: 280.5),
            PriceTier(id: 'train_student_lower', name: '学生票下铺', amount: 304.0),
            PriceTier(id: 'train_adult_upper', name: '成人票上铺', amount: 421.5),
            PriceTier(id: 'train_adult_lower', name: '成人票下铺', amount: 456.0),
          ],
          memberTierIds: {
            jab.id: 'train_adult_lower',
            lucky.id: 'train_student_upper',
            zhou.id: 'train_adult_upper',
            ganzi.id: 'train_student_lower',
            bianmu.id: 'train_adult_lower',
            litang.id: 'train_adult_upper',
            genie.id: 'train_student_upper',
            prince.id: 'train_adult_upper',
            dora.id: 'train_student_lower',
            germain.id: 'train_adult_lower',
          },
        ),
      ),
      Expense(
        id: 'e5',
        name: 'KTV组合消费',
        timeLabel: '',
        month: 6,
        day: 22,
        hour: 21,
        note: '夜间',
        amount: 820,
        payments: [Payment(memberId: jab.id, amount: 820)],
        participantIds: ids,
        subExpenses: [
          SubExpense(
            id: 's5_1',
            name: '包厢钱',
            amount: 660,
            rule: SplitRule.average(participantIds: ids),
          ),
          SubExpense(
            id: 's5_2',
            name: '酒水钱',
            amount: 280,
            rule: SplitRule.average(participantIds: [jab.id, ganzi.id]),
          ),
          SubExpense(
            id: 's5_3',
            name: '服务不好退款差价',
            amount: -120,
            rule: SplitRule.discount(participantIds: ids),
          ),
        ],
      ),
      Expense(
        id: 'e6',
        name: '民宿-->成都东站打车',
        timeLabel: '',
        month: 6,
        day: 23,
        hour: 8,
        note: '上午',
        amount: 120,
        payments: [Payment(memberId: lucky.id, amount: 120)],
        participantIds: [lucky.id, ganzi.id, jab.id],
        rule: SplitRule.average(participantIds: [lucky.id, ganzi.id, jab.id]),
      ),
    ],
  );
}

Map<String, Object?> _tripToJson(Trip trip) => {
      'id': trip.id,
      'name': trip.name,
      'dateLabel': trip.dateLabel,
      'backgroundAsset': trip.backgroundAsset,
      'backgroundImagePath': trip.backgroundImagePath,
      'backgroundColorValue': trip.backgroundColorValue,
      'members': trip.members
          .map((m) => {
                'id': m.id,
                'name': m.name,
                'avatarColor': m.avatarColor.toARGB32(),
                'note': m.note,
              })
          .toList(),
      'expenses': trip.expenses.map(_expenseToJson).toList(),
    };

Trip _tripFromJson(Map<String, Object?> json) => Trip(
      id: json['id'] as String,
      name: json['name'] as String,
      dateLabel: json['dateLabel'] as String? ?? '本地旅行',
      backgroundAsset: json['backgroundAsset'] as String?,
      backgroundImagePath: json['backgroundImagePath'] as String?,
      backgroundColorValue: json['backgroundColorValue'] as int? ?? 0xFFFFFFFF,
      members: ((json['members'] as List?) ?? []).map((item) {
        final map = Map<String, Object?>.from(item as Map);
        return Member(
          id: map['id'] as String,
          name: map['name'] as String,
          avatarColor: Color(map['avatarColor'] as int? ?? 0xFF315C48),
          note: map['note'] as String? ?? '',
        );
      }).toList(),
      expenses: ((json['expenses'] as List?) ?? [])
          .map((item) =>
              _expenseFromJson(Map<String, Object?>.from(item as Map)))
          .toList(),
    );

Map<String, Object?> _expenseToJson(Expense expense) => {
      'id': expense.id,
      'name': expense.name,
      'timeLabel': expense.timeLabel,
      'month': expense.month,
      'day': expense.day,
      'hour': expense.hour,
      'amount': expense.amount,
      'payments': expense.payments
          .map((p) => {
                'memberId': p.memberId,
                'amount': p.amount,
                'method': p.method,
                'note': p.note,
              })
          .toList(),
      'participantIds': expense.participantIds,
      'rule': expense.rule == null ? null : _splitRuleToJson(expense.rule!),
      'subExpenses': expense.subExpenses.map(_subExpenseToJson).toList(),
      'note': expense.note,
    };

Expense _expenseFromJson(Map<String, Object?> json) => Expense(
      id: json['id'] as String,
      name: json['name'] as String,
      timeLabel: json['timeLabel'] as String? ?? '',
      month: json['month'] as int? ?? 6,
      day: json['day'] as int? ?? 1,
      hour: json['hour'] as int? ?? 12,
      amount: (json['amount'] as num).toDouble(),
      payments: ((json['payments'] as List?) ?? []).map((item) {
        final map = Map<String, Object?>.from(item as Map);
        return Payment(
          memberId: map['memberId'] as String,
          amount: (map['amount'] as num).toDouble(),
          method: map['method'] as String? ?? '微信',
          note: map['note'] as String? ?? '',
        );
      }).toList(),
      participantIds:
          List<String>.from((json['participantIds'] as List?) ?? []),
      rule: json['rule'] == null
          ? null
          : _splitRuleFromJson(Map<String, Object?>.from(json['rule'] as Map)),
      subExpenses: ((json['subExpenses'] as List?) ?? [])
          .map((item) =>
              _subExpenseFromJson(Map<String, Object?>.from(item as Map)))
          .toList(),
      note: json['note'] as String? ?? '',
    );

Map<String, Object?> _subExpenseToJson(SubExpense subExpense) => {
      'id': subExpense.id,
      'name': subExpense.name,
      'amount': subExpense.amount,
      'rule': _splitRuleToJson(subExpense.rule),
      'note': subExpense.note,
    };

SubExpense _subExpenseFromJson(Map<String, Object?> json) => SubExpense(
      id: json['id'] as String,
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      rule: _splitRuleFromJson(Map<String, Object?>.from(json['rule'] as Map)),
      note: json['note'] as String? ?? '',
    );

Map<String, Object?> _splitRuleToJson(SplitRule rule) => {
      'kind': rule.kind.name,
      'participantIds': rule.participantIds,
      'fixedAmounts': rule.fixedAmounts,
      'tiers': rule.tiers
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'amount': t.amount,
              })
          .toList(),
      'memberTierIds': rule.memberTierIds,
      'targetSubExpenseId': rule.targetSubExpenseId,
    };

SplitRule _splitRuleFromJson(Map<String, Object?> json) {
  final kind = SplitKind.values.firstWhere(
    (item) => item.name == json['kind'],
    orElse: () => SplitKind.average,
  );
  return switch (kind) {
    SplitKind.average => SplitRule.average(
        participantIds:
            List<String>.from((json['participantIds'] as List?) ?? []),
      ),
    SplitKind.fixed => SplitRule.fixed(
        fixedAmounts: Map<String, double>.from(
          ((json['fixedAmounts'] as Map?) ?? {}).map(
            (key, value) => MapEntry(key as String, (value as num).toDouble()),
          ),
        ),
      ),
    SplitKind.tiered => SplitRule.tiered(
        tiers: ((json['tiers'] as List?) ?? []).map((item) {
          final map = Map<String, Object?>.from(item as Map);
          return PriceTier(
            id: map['id'] as String,
            name: map['name'] as String,
            amount: (map['amount'] as num).toDouble(),
          );
        }).toList(),
        memberTierIds:
            Map<String, String>.from((json['memberTierIds'] as Map?) ?? {}),
      ),
    SplitKind.discount => SplitRule.discount(
        participantIds:
            List<String>.from((json['participantIds'] as List?) ?? []),
        targetSubExpenseId: json['targetSubExpenseId'] as String?,
      ),
    SplitKind.adjustment => SplitRule.adjustment(
        fixedAmounts: Map<String, double>.from(
          ((json['fixedAmounts'] as Map?) ?? {}).map(
            (key, value) => MapEntry(key as String, (value as num).toDouble()),
          ),
        ),
      ),
  };
}

String _id() => DateTime.now().microsecondsSinceEpoch.toString();

class TripListScreen extends StatefulWidget {
  const TripListScreen({super.key});

  @override
  State<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends State<TripListScreen> {
  final state = AppState();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下山算账',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Settle After Descent',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Colors.black45,
                                    letterSpacing: 0.6,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '精细、公平、可追溯的山野分账',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.black54,
                                  ),
                        ),
                        const SizedBox(height: 22),
                        BilingualButton(
                          zh: '新建旅行',
                          en: 'New Trip',
                          onTap: () => _showAddTrip(context),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(18),
                  sliver: SliverList.builder(
                    itemCount: state.trips.length,
                    itemBuilder: (context, index) {
                      final trip = state.trips[index];
                      final ledgers = ExpenseCalculator.ledgersFor(trip);
                      return TripCard(
                        trip: trip,
                        ledgers: ledgers,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TripDetailScreen(
                              state: state,
                              tripId: trip.id,
                            ),
                          ),
                        ),
                        onLongPressAt: (pos) =>
                            _showTripCardMenu(context, trip, pos),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTripCardMenu(
    BuildContext context,
    Trip trip,
    Offset position,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          child: Text(
            '删除旅行',
            style: TextStyle(
              color: Color(0xFFC62828),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
    if (selected == 'delete' && context.mounted) {
      await _confirmDeleteTrip(context, trip);
    }
  }

  Future<void> _confirmDeleteTrip(BuildContext context, Trip trip) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除旅行'),
        content: Text('确定要删除「${trip.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('再次确认删除'),
        content: Text(
          '删除「${trip.name}」后，这次旅行的全部成员、花费、子花费和结算数据都会被永久删除，且无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('我再想想'),
          ),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFF9A4B35)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (second != true) return;

    state.deleteTrip(trip.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除「${trip.name}」')),
      );
    }
  }

  void _showAddTrip(BuildContext context) {
    final controller = TextEditingController();
    const colors = [
      0xFFEAF1EC,
      0xFFF3EEE6,
      0xFFE8EEF6,
      0xFFF3E9EF,
      0xFFEDEDDC,
    ];
    var selectedColor = colors.first;
    String? selectedImagePath;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return BottomSheetFrame(
            title: '新建旅行',
            subtitle: 'New Trip',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration:
                      const InputDecoration(hintText: '旅行名称，例如 2026 端午节四川之行'),
                  autofocus: true,
                ),
                const SizedBox(height: 18),
                Text('背景', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: colors.map((colorValue) {
                    final selected = selectedColor == colorValue &&
                        selectedImagePath == null;
                    return GestureDetector(
                      onTap: () => setModalState(() {
                        selectedColor = colorValue;
                        selectedImagePath = null;
                      }),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Color(colorValue),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black12,
                            width: selected ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    final path =
                        await const MethodChannel('settle_after_descent/native')
                            .invokeMethod<String>(
                      'pickImage',
                    );
                    if (path != null && path.isNotEmpty) {
                      setModalState(() => selectedImagePath = path);
                    }
                  },
                  child: Text(selectedImagePath == null ? '选择手机内图片' : '已选择图片'),
                ),
                const SizedBox(height: 18),
                BilingualButton(
                  zh: '创建旅行',
                  en: 'Create Trip',
                  onTap: () {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      state.addTrip(
                        name,
                        backgroundColorValue: selectedColor,
                        backgroundImagePath: selectedImagePath,
                      );
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

class TripCard extends StatelessWidget {
  const TripCard({
    required this.trip,
    required this.ledgers,
    required this.onTap,
    this.onLongPressAt,
    super.key,
  });

  final Trip trip;
  final List<MemberLedger> ledgers;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onLongPressAt;

  @override
  Widget build(BuildContext context) {
    final total = trip.expenses.fold(0.0, (sum, e) => sum + e.amount);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onLongPressStart: onLongPressAt == null
            ? null
            : (details) => onLongPressAt!(details.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(child: TripBackground(trip: trip)),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${trip.members.length} 位成员 · ${trip.expenses.length} 笔花费',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          yuan(total),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: -6,
                      children: trip.members
                          .map((m) => MemberAvatar(member: m, size: 42))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripBackground extends StatelessWidget {
  const TripBackground({required this.trip, super.key});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final image = _backgroundImage();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(trip.backgroundColorValue)),
        if (image != null)
          Opacity(
            opacity: 0.2,
            child: Image(
              image: image,
              fit: BoxFit.cover,
            ),
          ),
        Container(color: Colors.white.withValues(alpha: 0.58)),
      ],
    );
  }

  ImageProvider? _backgroundImage() {
    if (trip.backgroundImagePath != null &&
        trip.backgroundImagePath!.isNotEmpty) {
      return FileImage(File(trip.backgroundImagePath!));
    }
    if (trip.backgroundAsset != null && trip.backgroundAsset!.isNotEmpty) {
      return AssetImage(trip.backgroundAsset!);
    }
    return null;
  }
}

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    required this.state,
    required this.tripId,
    super.key,
  });

  final AppState state;
  final String tripId;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  String? hubMemberId;
  int settlementMode = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final trip = widget.state.tripById(widget.tripId);
        if (trip.members.isEmpty) {
          hubMemberId = null;
        } else if (hubMemberId == null ||
            !trip.members.any((member) => member.id == hubMemberId)) {
          hubMemberId = trip.members.first.id;
        }
        final ledgers = ExpenseCalculator.ledgersFor(trip);
        final shortest = ExpenseCalculator.shortestTransfers(ledgers);
        final hub = hubMemberId == null
            ? <SettlementTransfer>[]
            : ExpenseCalculator.hubTransfers(ledgers, hubMemberId!);
        final sortedExpenses = [...trip.expenses]
          ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
        final expenseMonthDays =
            sortedExpenses.map((e) => e.monthDayLabel).toSet();

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              children: [
                HeaderBar(title: trip.name, subtitle: trip.dateLabel),
                const SizedBox(height: 18),
                _OverviewCard(trip: trip, ledgers: ledgers),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BilingualButton(
                        zh: '添加成员',
                        en: 'Add Member',
                        compact: true,
                        onTap: () => _showAddMember(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BilingualButton(
                        zh: '创建花费',
                        en: 'New Expense',
                        compact: true,
                        onTap: () => _showAddExpense(context, trip),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (trip.members.isEmpty)
                  const EmptyTripCard()
                else ...[
                  const SectionTitle('结算方案', 'Settlement'),
                  const SizedBox(height: 10),
                  SettlementModeTabs(
                    value: settlementMode,
                    onChanged: (value) =>
                        setState(() => settlementMode = value),
                  ),
                  const SizedBox(height: 12),
                  if (settlementMode == 0) ...[
                    _HubSelector(
                      trip: trip,
                      hubId: hubMemberId!,
                      onChanged: (id) => setState(() => hubMemberId = id),
                    ),
                    const SizedBox(height: 8),
                    TransferCard(
                      title: '统一中转人',
                      subtitle: 'Hub Settlement',
                      trip: trip,
                      transfers: hub,
                    ),
                  ] else
                    TransferCard(
                      title: '最短转账路径',
                      subtitle: 'Minimal Transfers',
                      trip: trip,
                      transfers: shortest,
                    ),
                ],
                const SizedBox(height: 18),
                const SectionTitle('花费明细', 'Expenses'),
                const SizedBox(height: 10),
                if (expenseMonthDays.length <= 1)
                  ...sortedExpenses.map((e) => ExpenseTile(
                        state: widget.state,
                        trip: trip,
                        expense: e,
                      ))
                else
                  ..._groupedExpenseWidgets(
                    trip: trip,
                    expenses: sortedExpenses,
                    state: widget.state,
                  ),
                const SizedBox(height: 18),
                const SectionTitle('导出预览', 'Export Preview'),
                const SizedBox(height: 10),
                ExportPreview(trip: trip, ledgers: ledgers),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddMember(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return BottomSheetFrame(
          title: '添加成员',
          subtitle: 'Add Member',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: '成员昵称'),
                autofocus: true,
              ),
              const SizedBox(height: 18),
              BilingualButton(
                zh: '保存成员',
                en: 'Save Member',
                onTap: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    widget.state.addMember(widget.tripId, name);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddExpense(BuildContext context, Trip trip) {
    if (trip.members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加成员')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpenseEditorScreen(
          trip: trip,
          onSave: (expense) => widget.state.upsertExpense(
            tripId: trip.id,
            expense: expense,
          ),
        ),
      ),
    );
  }

  List<Widget> _groupedExpenseWidgets({
    required Trip trip,
    required List<Expense> expenses,
    required AppState state,
  }) {
    final monthDays = expenses.map((e) => e.monthDayLabel).toSet().toList()
      ..sort();
    return [
      for (final monthDay in monthDays) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            monthDay,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ...expenses
            .where((e) => e.monthDayLabel == monthDay)
            .map((expense) => ExpenseTile(
                  state: state,
                  trip: trip,
                  expense: expense,
                )),
      ],
    ];
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.trip, required this.ledgers});

  final Trip trip;
  final List<MemberLedger> ledgers;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('总览', 'Overview', dense: true),
            const SizedBox(height: 14),
            ...ledgers.map((ledger) {
              final member = trip.member(ledger.memberId);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    MemberAvatar(member: member, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('已付',
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                              const SizedBox(width: 6),
                              Text(yuan(ledger.paid),
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Text('应担',
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                              const SizedBox(width: 6),
                              Text(yuan(ledger.owed),
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ledger.net >= 0
                          ? '应收 ${yuan(ledger.net)}'
                          : '应付 ${yuan(-ledger.net)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ledger.net >= 0
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFF9A4B35),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class EmptyTripCard extends StatelessWidget {
  const EmptyTripCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('先添加成员', 'Add Members', dense: true),
            const SizedBox(height: 10),
            Text(
              '这个旅行还没有成员。添加成员后，就可以创建花费并生成结算方案。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.45,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseEditorScreen extends StatefulWidget {
  const ExpenseEditorScreen({
    required this.trip,
    required this.onSave,
    this.expense,
    super.key,
  });

  final Trip trip;
  final Expense? expense;
  final ValueChanged<Expense> onSave;

  @override
  State<ExpenseEditorScreen> createState() => _ExpenseEditorScreenState();
}

class _ExpenseEditorScreenState extends State<ExpenseEditorScreen> {
  late final TextEditingController nameController;
  late final TextEditingController amountController;
  late final TextEditingController noteController;
  late final TextEditingController monthController;
  late final TextEditingController dayController;
  late final TextEditingController hourController;
  late bool isComposite;
  late SplitKind ruleKind;
  late Set<String> selectedParticipantIds;
  late List<PaymentDraft> payments;
  late List<SubExpense> subExpenses;
  final fixedControllers = <String, TextEditingController>{};
  final tierDrafts = <TierDraft>[];
  final memberTierIds = <String, String>{};

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    isComposite = expense?.isComposite ?? false;
    ruleKind = expense?.rule?.kind ?? SplitKind.average;
    nameController = TextEditingController(text: expense?.name ?? '');
    noteController = TextEditingController(text: expense?.note ?? '');
    amountController = TextEditingController(
      text: expense == null ? '' : expense.amount.abs().toStringAsFixed(2),
    );
    monthController =
        TextEditingController(text: expense == null ? '' : '${expense.month}');
    dayController =
        TextEditingController(text: expense == null ? '' : '${expense.day}');
    hourController =
        TextEditingController(text: expense == null ? '' : '${expense.hour}');
    selectedParticipantIds =
        (expense?.participantIds ?? widget.trip.members.map((m) => m.id))
            .toSet();
    payments = (expense?.payments.isNotEmpty ?? false)
        ? expense!.payments
            .map((p) => PaymentDraft(
                  memberId: p.memberId,
                  amount: p.amount.toStringAsFixed(2),
                ))
            .toList()
        : [
            PaymentDraft(
              memberId: widget.trip.members.first.id,
              amount: '',
            )
          ];
    subExpenses = expense?.subExpenses
            .map((s) => SubExpense(
                  id: s.id,
                  name: s.name,
                  amount: s.amount,
                  rule: s.rule,
                  note: s.note,
                ))
            .toList() ??
        [];
    _seedRuleFields(expense?.rule);
  }

  @override
  void dispose() {
    nameController.dispose();
    noteController.dispose();
    amountController.dispose();
    monthController.dispose();
    dayController.dispose();
    hourController.dispose();
    for (final draft in payments) {
      draft.dispose();
    }
    for (final controller in fixedControllers.values) {
      controller.dispose();
    }
    for (final draft in tierDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          children: [
            HeaderBar(
              title: widget.expense == null ? '创建花费' : '编辑花费',
              subtitle: widget.expense == null ? 'New Expense' : 'Edit Expense',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: '花费名称，例如 0619 团建聚餐'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(hintText: '备注，例如 晚餐 / 路程'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: isComposite ? '父级总金额，可留空由子花费汇总' : '总金额',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: monthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Month'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: dayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Day'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: hourController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Hour'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ExpenseModeTabs(
              isComposite: isComposite,
              onChanged: (value) => setState(() => isComposite = value),
            ),
            const SizedBox(height: 18),
            _PaymentEditor(
              trip: widget.trip,
              payments: payments,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 18),
            if (isComposite)
              _buildCompositeEditor()
            else
              _buildSimpleRuleEditor(),
            const SizedBox(height: 24),
            BilingualButton(
              zh: '保存花费',
              en: 'Save Expense',
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleRuleEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('分摊规则', 'Split Rule', dense: true),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SplitKind.values.map((kind) {
                return ChoiceChip(
                  selected: ruleKind == kind,
                  label: Text(kind.zh),
                  onSelected: (_) => setState(() => ruleKind = kind),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (ruleKind == SplitKind.average || ruleKind == SplitKind.discount)
              _ParticipantPicker(
                trip: widget.trip,
                selectedIds: selectedParticipantIds,
                onChanged: () => setState(() {}),
              )
            else if (ruleKind == SplitKind.fixed ||
                ruleKind == SplitKind.adjustment)
              _FixedAmountInputs(
                trip: widget.trip,
                controllers: fixedControllers,
                allowNegative: ruleKind == SplitKind.adjustment,
              )
            else if (ruleKind == SplitKind.tiered)
              _TieredRuleInputs(
                trip: widget.trip,
                tiers: tierDrafts,
                memberTierIds: memberTierIds,
                onChanged: () => setState(() {}),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompositeEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: SectionTitle('子花费', 'Sub Expenses', dense: true),
                ),
                TextButton(
                  onPressed: () => _editSubExpense(null),
                  child: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (subExpenses.isEmpty)
              const Text(
                '组合花费需要至少创建一个子花费。每个子花费可以选择独立分摊规则。',
                style: TextStyle(color: Colors.black54),
              )
            else
              ...subExpenses.asMap().entries.map((entry) {
                final index = entry.key;
                final sub = entry.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(sub.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(sub.rule.kind.zh),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(yuan(sub.amount),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFF9A4B35)),
                        onPressed: () => _confirmDeleteSubExpense(index),
                      ),
                    ],
                  ),
                  onTap: () => _editSubExpense(index),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _seedRuleFields(SplitRule? rule) {
    for (final member in widget.trip.members) {
      final value = rule?.fixedAmounts[member.id];
      fixedControllers[member.id] =
          TextEditingController(text: value == null ? '' : value.toString());
    }
    if (rule?.kind == SplitKind.tiered && rule!.tiers.isNotEmpty) {
      tierDrafts.addAll(rule.tiers.map((tier) => TierDraft(
            id: tier.id,
            name: tier.name,
            amount: tier.amount.toStringAsFixed(2),
          )));
      memberTierIds.addAll(rule.memberTierIds);
    } else {
      tierDrafts.addAll([
        TierDraft(id: _id(), name: '普通价', amount: ''),
        TierDraft(id: _id(), name: '优惠价', amount: ''),
      ]);
      for (final member in widget.trip.members) {
        memberTierIds[member.id] = tierDrafts.first.id;
      }
    }
  }

  Future<void> _confirmDeleteSubExpense(int index) async {
    final sub = subExpenses[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除子花费'),
        content: Text('确定要删除子花费「${sub.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFF9A4B35)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => subExpenses.removeAt(index));
  }

  void _editSubExpense(int? index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SubExpenseEditorSheet(
        trip: widget.trip,
        subExpense: index == null ? null : subExpenses[index],
        onSave: (subExpense) {
          setState(() {
            if (index == null) {
              subExpenses.add(subExpense);
            } else {
              subExpenses[index] = subExpense;
            }
          });
        },
      ),
    );
  }

  void _save() {
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    if (isComposite && subExpenses.isEmpty) return;
    final enteredAmount = double.tryParse(amountController.text.trim());
    final double amount;
    if (isComposite) {
      amount = enteredAmount ??
          subExpenses.fold<double>(0, (sum, item) => sum + item.amount);
    } else {
      amount = _amountForSimpleRule(enteredAmount);
    }
    final month = _parseClamped(monthController.text,
        fallback: 0, minValue: 0, maxValue: 12);
    final day = _parseClamped(dayController.text,
        fallback: 0, minValue: 0, maxValue: 31);
    final hour = _parseClamped(hourController.text, fallback: 0, maxValue: 23);
    final expense = Expense(
      id: widget.expense?.id ?? _id(),
      name: name,
      timeLabel: '',
      month: month,
      day: day,
      hour: hour,
      amount: _money(amount),
      payments: _paymentsFromDrafts(),
      participantIds: isComposite
          ? _participantsFromSubExpenses()
          : _participantIdsForRule(),
      rule: isComposite ? null : _buildRule(),
      subExpenses: isComposite ? subExpenses : const [],
      note: noteController.text.trim(),
    );
    widget.onSave(expense);
    Navigator.pop(context);
  }

  int _parseClamped(
    String raw, {
    required int fallback,
    int minValue = 0,
    int? maxValue,
  }) {
    final parsed = int.tryParse(raw.trim()) ?? fallback;
    return parsed.clamp(minValue, maxValue ?? parsed);
  }

  double _amountForSimpleRule(double? enteredAmount) {
    if (ruleKind == SplitKind.fixed || ruleKind == SplitKind.adjustment) {
      return enteredAmount ??
          _fixedAmountMap().values.fold(0.0, (sum, value) => sum + value);
    }
    if (ruleKind == SplitKind.tiered) {
      return enteredAmount ??
          _tieredAllocation().values.fold(0.0, (sum, value) => sum + value);
    }
    final value = enteredAmount ?? 0;
    return ruleKind == SplitKind.discount ? -value.abs() : value;
  }

  List<Payment> _paymentsFromDrafts() => payments
      .map((draft) => Payment(
            memberId: draft.memberId,
            amount: double.tryParse(draft.amountController.text.trim()) ?? 0,
          ))
      .where((payment) => payment.amount.abs() > 0.004)
      .toList();

  List<String> _participantIdsForRule() {
    if (ruleKind == SplitKind.fixed || ruleKind == SplitKind.adjustment) {
      return _fixedAmountMap().keys.toList();
    }
    if (ruleKind == SplitKind.tiered) return memberTierIds.keys.toList();
    return selectedParticipantIds.toList();
  }

  List<String> _participantsFromSubExpenses() {
    final ids = <String>{};
    for (final sub in subExpenses) {
      ids.addAll(sub.rule.participantIds);
    }
    return ids.toList();
  }

  SplitRule _buildRule() {
    return switch (ruleKind) {
      SplitKind.average =>
        SplitRule.average(participantIds: selectedParticipantIds.toList()),
      SplitKind.fixed => SplitRule.fixed(fixedAmounts: _fixedAmountMap()),
      SplitKind.tiered => SplitRule.tiered(
          tiers: _tiers(),
          memberTierIds: Map<String, String>.from(memberTierIds),
        ),
      SplitKind.discount =>
        SplitRule.discount(participantIds: selectedParticipantIds.toList()),
      SplitKind.adjustment =>
        SplitRule.adjustment(fixedAmounts: _fixedAmountMap()),
    };
  }

  Map<String, double> _fixedAmountMap() {
    final result = <String, double>{};
    for (final entry in fixedControllers.entries) {
      final value = double.tryParse(entry.value.text.trim());
      if (value != null && value.abs() > 0.004) result[entry.key] = value;
    }
    return result;
  }

  Map<String, double> _tieredAllocation() {
    final tierMap = {for (final tier in _tiers()) tier.id: tier.amount};
    return {
      for (final entry in memberTierIds.entries)
        entry.key: tierMap[entry.value] ?? 0,
    };
  }

  List<PriceTier> _tiers() => tierDrafts
      .map((draft) => PriceTier(
            id: draft.id,
            name: draft.nameController.text.trim().isEmpty
                ? '价格等级'
                : draft.nameController.text.trim(),
            amount: double.tryParse(draft.amountController.text.trim()) ?? 0,
          ))
      .where((tier) => tier.amount.abs() > 0.004)
      .toList();
}

class PaymentDraft {
  PaymentDraft({required this.memberId, required String amount})
      : amountController = TextEditingController(text: amount);

  String memberId;
  final TextEditingController amountController;

  void dispose() => amountController.dispose();
}

class TierDraft {
  TierDraft({required this.id, required String name, required String amount})
      : nameController = TextEditingController(text: name),
        amountController = TextEditingController(text: amount);

  final String id;
  final TextEditingController nameController;
  final TextEditingController amountController;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class ExpenseModeTabs extends StatelessWidget {
  const ExpenseModeTabs({
    required this.isComposite,
    required this.onChanged,
    super.key,
  });

  final bool isComposite;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _ModeButton(
              selected: !isComposite,
              zh: '简单花费',
              en: 'Simple',
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              selected: isComposite,
              zh: '组合花费',
              en: 'Composite',
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.zh,
    required this.en,
    required this.onTap,
  });

  final bool selected;
  final String zh;
  final String en;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                zh,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                en,
                style: TextStyle(
                  color: selected ? Colors.white70 : Colors.black38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentEditor extends StatelessWidget {
  const _PaymentEditor({
    required this.trip,
    required this.payments,
    required this.onChanged,
  });

  final Trip trip;
  final List<PaymentDraft> payments;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: SectionTitle('付款记录', 'Payments', dense: true),
                ),
                TextButton(
                  onPressed: () {
                    payments.add(PaymentDraft(
                        memberId: trip.members.first.id, amount: ''));
                    onChanged();
                  },
                  child: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...payments.asMap().entries.map((entry) {
              final index = entry.key;
              final draft = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: draft.memberId,
                        items: trip.members
                            .map((m) => DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.name),
                                ))
                            .toList(),
                        onChanged: (id) {
                          if (id != null) {
                            draft.memberId = id;
                            onChanged();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: draft.amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '付款金额'),
                      ),
                    ),
                    IconButton(
                      onPressed: payments.length == 1
                          ? null
                          : () {
                              payments.removeAt(index).dispose();
                              onChanged();
                            },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ParticipantPicker extends StatelessWidget {
  const _ParticipantPicker({
    required this.trip,
    required this.selectedIds,
    required this.onChanged,
  });

  final Trip trip;
  final Set<String> selectedIds;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('参与人', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: () {
                selectedIds
                  ..clear()
                  ..addAll(trip.members.map((m) => m.id));
                onChanged();
              },
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () {
                selectedIds.clear();
                onChanged();
              },
              child: const Text('全不选'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: trip.members.map((m) {
            final selected = selectedIds.contains(m.id);
            return GestureDetector(
              onTap: () {
                if (selected) {
                  selectedIds.remove(m.id);
                } else {
                  selectedIds.add(m.id);
                }
                onChanged();
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: selected ? 1 : 0.32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MemberAvatar(member: m, size: 48),
                    const SizedBox(height: 4),
                    Text(m.name, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _FixedAmountInputs extends StatelessWidget {
  const _FixedAmountInputs({
    required this.trip,
    required this.controllers,
    this.allowNegative = false,
  });

  final Trip trip;
  final Map<String, TextEditingController> controllers;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: trip.members.map((member) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              MemberAvatar(member: member, size: 38),
              const SizedBox(width: 10),
              Expanded(child: Text(member.name)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: controllers[member.id],
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: InputDecoration(
                    hintText: allowNegative ? '可正可负' : '金额',
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TieredRuleInputs extends StatelessWidget {
  const _TieredRuleInputs({
    required this.trip,
    required this.tiers,
    required this.memberTierIds,
    required this.onChanged,
  });

  final Trip trip;
  final List<TierDraft> tiers;
  final Map<String, String> memberTierIds;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('价格等级', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: () {
                tiers.add(TierDraft(id: _id(), name: '新等级', amount: ''));
                onChanged();
              },
              child: const Text('新增等级'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...tiers.map((tier) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: tier.nameController,
                      decoration: const InputDecoration(hintText: '等级名称'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: tier.amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '价格'),
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 8),
        ...trip.members.map((member) {
          final value = memberTierIds[member.id] ?? tiers.first.id;
          return Row(
            children: [
              Expanded(child: Text(member.name)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  items: tiers
                      .map((tier) => DropdownMenuItem(
                            value: tier.id,
                            child: Text(tier.nameController.text.trim().isEmpty
                                ? '价格等级'
                                : tier.nameController.text.trim()),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id != null) {
                      memberTierIds[member.id] = id;
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class SubExpenseEditorSheet extends StatefulWidget {
  const SubExpenseEditorSheet({
    required this.trip,
    required this.onSave,
    this.subExpense,
    super.key,
  });

  final Trip trip;
  final SubExpense? subExpense;
  final ValueChanged<SubExpense> onSave;

  @override
  State<SubExpenseEditorSheet> createState() => _SubExpenseEditorSheetState();
}

class _SubExpenseEditorSheetState extends State<SubExpenseEditorSheet> {
  late final TextEditingController nameController;
  late final TextEditingController amountController;
  late SplitKind ruleKind;
  late Set<String> selectedParticipantIds;
  final fixedControllers = <String, TextEditingController>{};
  final tierDrafts = <TierDraft>[];
  final memberTierIds = <String, String>{};

  @override
  void initState() {
    super.initState();
    final sub = widget.subExpense;
    nameController = TextEditingController(text: sub?.name ?? '');
    amountController = TextEditingController(
      text: sub == null ? '' : sub.amount.abs().toStringAsFixed(2),
    );
    ruleKind = sub?.rule.kind ?? SplitKind.average;
    selectedParticipantIds =
        (sub?.rule.participantIds ?? widget.trip.members.map((m) => m.id))
            .toSet();
    for (final member in widget.trip.members) {
      final value = sub?.rule.fixedAmounts[member.id];
      fixedControllers[member.id] =
          TextEditingController(text: value == null ? '' : value.toString());
    }
    if (sub?.rule.kind == SplitKind.tiered && sub!.rule.tiers.isNotEmpty) {
      tierDrafts.addAll(sub.rule.tiers.map((tier) => TierDraft(
            id: tier.id,
            name: tier.name,
            amount: tier.amount.toStringAsFixed(2),
          )));
      memberTierIds.addAll(sub.rule.memberTierIds);
    } else {
      tierDrafts.addAll([
        TierDraft(id: _id(), name: '普通价', amount: ''),
        TierDraft(id: _id(), name: '优惠价', amount: ''),
      ]);
      for (final member in widget.trip.members) {
        memberTierIds[member.id] = tierDrafts.first.id;
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    for (final controller in fixedControllers.values) {
      controller.dispose();
    }
    for (final draft in tierDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetFrame(
      title: widget.subExpense == null ? '新增子花费' : '编辑子花费',
      subtitle:
          widget.subExpense == null ? 'New Sub Expense' : 'Edit Sub Expense',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: '子花费名称，例如 酒水'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '子花费金额'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SplitKind.values.map((kind) {
              return ChoiceChip(
                selected: ruleKind == kind,
                label: Text(kind.zh),
                onSelected: (_) => setState(() => ruleKind = kind),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (ruleKind == SplitKind.average || ruleKind == SplitKind.discount)
            _ParticipantPicker(
              trip: widget.trip,
              selectedIds: selectedParticipantIds,
              onChanged: () => setState(() {}),
            )
          else if (ruleKind == SplitKind.fixed ||
              ruleKind == SplitKind.adjustment)
            _FixedAmountInputs(
              trip: widget.trip,
              controllers: fixedControllers,
              allowNegative: ruleKind == SplitKind.adjustment,
            )
          else
            _TieredRuleInputs(
              trip: widget.trip,
              tiers: tierDrafts,
              memberTierIds: memberTierIds,
              onChanged: () => setState(() {}),
            ),
          const SizedBox(height: 18),
          BilingualButton(
            zh: '保存子花费',
            en: 'Save Sub Expense',
            onTap: _save,
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    final enteredAmount = double.tryParse(amountController.text.trim());
    final amount = _amountForRule(enteredAmount);
    widget.onSave(SubExpense(
      id: widget.subExpense?.id ?? _id(),
      name: name,
      amount: _money(amount),
      rule: _buildRule(),
    ));
    Navigator.pop(context);
  }

  double _amountForRule(double? enteredAmount) {
    if (ruleKind == SplitKind.fixed || ruleKind == SplitKind.adjustment) {
      return enteredAmount ??
          _fixedAmountMap().values.fold(0.0, (sum, value) => sum + value);
    }
    if (ruleKind == SplitKind.tiered) {
      final tierMap = {for (final tier in _tiers()) tier.id: tier.amount};
      return enteredAmount ??
          memberTierIds.values
              .map((id) => tierMap[id] ?? 0)
              .fold(0.0, (sum, value) => sum + value);
    }
    final value = enteredAmount ?? 0;
    return ruleKind == SplitKind.discount ? -value.abs() : value;
  }

  SplitRule _buildRule() {
    return switch (ruleKind) {
      SplitKind.average =>
        SplitRule.average(participantIds: selectedParticipantIds.toList()),
      SplitKind.fixed => SplitRule.fixed(fixedAmounts: _fixedAmountMap()),
      SplitKind.tiered => SplitRule.tiered(
          tiers: _tiers(),
          memberTierIds: Map<String, String>.from(memberTierIds),
        ),
      SplitKind.discount =>
        SplitRule.discount(participantIds: selectedParticipantIds.toList()),
      SplitKind.adjustment =>
        SplitRule.adjustment(fixedAmounts: _fixedAmountMap()),
    };
  }

  Map<String, double> _fixedAmountMap() {
    final result = <String, double>{};
    for (final entry in fixedControllers.entries) {
      final value = double.tryParse(entry.value.text.trim());
      if (value != null && value.abs() > 0.004) result[entry.key] = value;
    }
    return result;
  }

  List<PriceTier> _tiers() => tierDrafts
      .map((draft) => PriceTier(
            id: draft.id,
            name: draft.nameController.text.trim().isEmpty
                ? '价格等级'
                : draft.nameController.text.trim(),
            amount: double.tryParse(draft.amountController.text.trim()) ?? 0,
          ))
      .where((tier) => tier.amount.abs() > 0.004)
      .toList();
}

class _HubSelector extends StatelessWidget {
  const _HubSelector({
    required this.trip,
    required this.hubId,
    required this.onChanged,
  });

  final Trip trip;
  final String hubId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '中转人 / Hub',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: hubId,
                items: trip.members
                    .map((m) =>
                        DropdownMenuItem(value: m.id, child: Text(m.name)))
                    .toList(),
                onChanged: (id) {
                  if (id != null) onChanged(id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettlementModeTabs extends StatelessWidget {
  const SettlementModeTabs({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [
      ('中转人', 'Hub'),
      ('最短路径', 'Minimal'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: value == i
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            labels[i].$1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: value == i ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            labels[i].$2,
                            style: TextStyle(
                              color:
                                  value == i ? Colors.white70 : Colors.black38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TransferCard extends StatelessWidget {
  const TransferCard({
    required this.title,
    required this.subtitle,
    required this.trip,
    required this.transfers,
    super.key,
  });

  final String title;
  final String subtitle;
  final Trip trip;
  final List<SettlementTransfer> transfers;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title, subtitle, dense: true),
            const SizedBox(height: 12),
            if (transfers.isEmpty)
              const Text('已经结清，无需转账。', style: TextStyle(color: Colors.black54))
            else
              ...transfers.map((t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            clipName(trip.member(t.fromMemberId).name),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(
                          width: 34,
                          child: Text(
                            '→',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            clipName(trip.member(t.toMemberId).name),
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 84,
                          child: Text(
                            yuan(t.amount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    required this.state,
    required this.trip,
    required this.expense,
    super.key,
  });

  final AppState state;
  final Trip trip;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final typeLabel = expense.isComposite
        ? '组合花费 · ${expense.subExpenses.length} 个子花费'
        : expense.rule?.kind.zh ?? '未设置';
    final subtitle = [
      if (expense.note.trim().isNotEmpty) expense.note.trim(),
      typeLabel,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExpenseDetailScreen(
                state: state,
                tripId: trip.id,
                expenseId: expense.id,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(expense.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Text(yuan(expense.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({
    required this.state,
    required this.tripId,
    required this.expenseId,
    super.key,
  });

  final AppState state;
  final String tripId;
  final String expenseId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final trip = state.tripById(tripId);
        final expense =
            trip.expenses.firstWhere((item) => item.id == expenseId);
        final allocation = ExpenseCalculator.allocationForExpense(expense);
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              children: [
                HeaderBar(title: expense.name, subtitle: 'Expense Detail'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: BilingualButton(
                        zh: '编辑花费',
                        en: 'Edit Expense',
                        compact: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExpenseEditorScreen(
                              trip: trip,
                              expense: expense,
                              onSave: (updated) => state.upsertExpense(
                                tripId: trip.id,
                                expense: updated,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF9A4B35),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: () =>
                            _confirmDeleteExpense(context, trip, expense),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('删除花费',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
                            SizedBox(height: 2),
                            Text('Delete', style: TextStyle(fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle('基础信息', 'Basic Info', dense: true),
                        const SizedBox(height: 10),
                        _InfoRow(
                            label: '类型',
                            value: expense.isComposite ? '组合花费' : '简单花费'),
                        _InfoRow(label: '总金额', value: yuan(expense.amount)),
                        _InfoRow(
                          label: '付款人',
                          value: expense.payments.isEmpty
                              ? '无付款记录'
                              : expense.payments
                                  .map((p) =>
                                      '${trip.member(p.memberId).name} ${yuan(p.amount)}')
                                  .join('，'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (expense.isComposite)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionTitle('子花费', 'Sub Expenses',
                              dense: true),
                          const SizedBox(height: 10),
                          ...expense.subExpenses.map(
                            (sub) => _SubExpenseRow(subExpense: sub),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionTitle('分摊规则', 'Split Rule', dense: true),
                          const SizedBox(height: 10),
                          Text(expense.rule?.kind.zh ?? '未设置'),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle('分摊结果', 'Allocation', dense: true),
                        const SizedBox(height: 10),
                        if (allocation.isEmpty)
                          const Text('暂无分摊结果',
                              style: TextStyle(color: Colors.black54))
                        else
                          ...allocation.entries.map((entry) => Row(
                                children: [
                                  Expanded(
                                      child: Text(trip.member(entry.key).name)),
                                  Text(yuan(entry.value)),
                                ],
                              )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteExpense(
    BuildContext context,
    Trip trip,
    Expense expense,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除花费'),
        content: Text('确定要删除「${expense.name}」吗？该花费及其子花费、付款记录都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFF9A4B35)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    state.deleteExpense(tripId: trip.id, expenseId: expense.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SubExpenseRow extends StatelessWidget {
  const _SubExpenseRow({required this.subExpense});

  final SubExpense subExpense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text('${subExpense.name} · ${subExpense.rule.kind.zh}'),
          ),
          Text(yuan(subExpense.amount)),
        ],
      ),
    );
  }
}

class ExportPreview extends StatelessWidget {
  const ExportPreview({
    required this.trip,
    required this.ledgers,
    super.key,
  });

  final Trip trip;
  final List<MemberLedger> ledgers;

  @override
  Widget build(BuildContext context) {
    final rows = _tableRows();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('表格预览', 'Sheet Preview', dense: true),
            const SizedBox(height: 10),
            SizedBox(
              height: 320,
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 28,
                      headingTextStyle:
                          const TextStyle(fontWeight: FontWeight.w800),
                      columns: const [
                        DataColumn(label: Text('类型')),
                        DataColumn(label: Text('名称')),
                        DataColumn(label: Text('Month')),
                        DataColumn(label: Text('Day')),
                        DataColumn(label: Text('Hour')),
                        DataColumn(label: Text('备注')),
                        DataColumn(label: Text('已付')),
                        DataColumn(label: Text('应担')),
                        DataColumn(label: Text('净额/金额')),
                        DataColumn(label: Text('规则')),
                      ],
                      rows: rows
                          .map(
                            (row) => DataRow(
                              cells: row
                                  .map((cell) => DataCell(Text(cell)))
                                  .toList(),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: BilingualButton(
                    zh: '导出 CSV',
                    en: 'Export CSV',
                    compact: true,
                    onTap: () => _exportCsv(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BilingualButton(
                    zh: '导出大图片',
                    en: 'Export Image',
                    compact: true,
                    onTap: () => _exportImage(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _csvText() {
    final buffer = StringBuffer()
      ..writeln([
        '类型',
        '名称',
        'Month',
        'Day',
        'Hour',
        '备注',
        '已付',
        '应担',
        '净额/金额',
        '规则'
      ].map(_csvCell).join(','));
    for (final row in _tableRows()) {
      buffer.writeln(row.map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  List<List<String>> _tableRows() {
    final rows = <List<String>>[];
    for (final l in ledgers) {
      final member = trip.member(l.memberId);
      rows.add([
        '成员',
        member.name,
        '',
        '',
        '',
        '',
        l.paid.toStringAsFixed(2),
        l.owed.toStringAsFixed(2),
        l.net.toStringAsFixed(2),
        '',
      ]);
    }
    for (final expense in trip.expenses) {
      rows.add([
        '花费',
        expense.name,
        expense.month == 0 ? '' : '${expense.month}',
        '${expense.day}',
        expense.hour == 0 ? '' : '${expense.hour}',
        expense.note,
        '',
        '',
        expense.amount.toStringAsFixed(2),
        expense.isComposite ? '组合花费' : expense.rule?.kind.zh ?? '',
      ]);
    }
    return rows;
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _exportImage(BuildContext context) async {
    final directory = Directory.systemTemp;
    final safeName = trip.name.replaceAll(RegExp(r'[\\/:*?"<>|\\s]+'), '_');
    final file = File('${directory.path}/${safeName}_expenses.png');
    final bytes = await _tableImageBytes();
    await file.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    await const MethodChannel('settle_after_descent/native').invokeMethod<void>(
      'shareFile',
      {
        'path': file.path,
        'title': '${trip.name} 花费大图',
        'mimeType': 'image/png',
      },
    );
  }

  Future<Uint8List> _tableImageBytes() async {
    final headers = [
      '类型',
      '名称',
      'Month',
      'Day',
      'Hour',
      '备注',
      '已付',
      '应担',
      '净额/金额',
      '规则'
    ];
    final rows = [headers, ..._tableRows()];
    final colWidths = <double>[
      for (var col = 0; col < headers.length; col++)
        max(
          88,
          rows.map((row) => row[col].length * 13.0).fold<double>(0, max) + 32,
        ),
    ];
    const rowHeight = 46.0;
    const padding = 24.0;
    final width =
        colWidths.fold<double>(0, (sum, value) => sum + value) + padding * 2;
    final height = rows.length * rowHeight + padding * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paint);

    var y = padding;
    for (var r = 0; r < rows.length; r++) {
      var x = padding;
      final isHeader = r == 0;
      paint.color = isHeader ? const Color(0xFFEAF1EC) : Colors.white;
      canvas.drawRect(
          Rect.fromLTWH(padding, y, width - padding * 2, rowHeight), paint);
      for (var c = 0; c < rows[r].length; c++) {
        paint
          ..color = const Color(0xFFE1DED7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(Rect.fromLTWH(x, y, colWidths[c], rowHeight), paint);
        final painter = TextPainter(
          text: TextSpan(
            text: rows[r][c],
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '...',
        )..layout(maxWidth: colWidths[c] - 18);
        painter.paint(
            canvas, Offset(x + 9, y + (rowHeight - painter.height) / 2));
        x += colWidths[c];
      }
      y += rowHeight;
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _exportCsv(BuildContext context) async {
    final directory = Directory.systemTemp;
    final safeName = trip.name.replaceAll(RegExp(r'[\\/:*?"<>|\\s]+'), '_');
    final file = File('${directory.path}/${safeName}_expenses.csv');
    await file.writeAsString(_csvText(), flush: true);
    if (!context.mounted) return;
    await const MethodChannel('settle_after_descent/native').invokeMethod<void>(
      'shareFile',
      {
        'path': file.path,
        'title': '${trip.name} 花费表格',
        'mimeType': 'text/csv',
      },
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(subtitle, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.zh, this.en, {this.dense = false, super.key});

  final String zh;
  final String en;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          zh,
          style: (dense
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.titleLarge)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          en,
          style: TextStyle(
            color: Colors.black45,
            fontSize: dense ? 11 : 12,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class BilingualButton extends StatelessWidget {
  const BilingualButton({
    required this.zh,
    required this.en,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final String zh;
  final String en;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 20,
          vertical: compact ? 12 : 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(zh,
              style: TextStyle(
                  fontSize: compact ? 15 : 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(en,
              style:
                  TextStyle(fontSize: compact ? 9 : 11, color: Colors.white70)),
        ],
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({required this.member, this.size = 36, super.key});

  final Member member;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: member.avatarColor,
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        member.name.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}

class BottomSheetFrame extends StatelessWidget {
  const BottomSheetFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight =
        max(280.0, mediaQuery.size.height * 0.9 - mediaQuery.viewInsets.bottom);
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: mediaQuery.viewInsets.bottom + 22,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SectionTitle(title, subtitle),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension TripLookup on Trip {
  Member member(String id) => members.firstWhere((m) => m.id == id);
}
