import 'dart:convert';

import 'package:flutter/services.dart';

String money(int cents) {
  final value = cents.abs();
  return '${cents < 0 ? '-' : ''}${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
}

DateTime chinaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
String currentMonth() => chinaNow().toIso8601String().substring(0, 7);
DateTime _stamp(dynamic value) => DateTime.parse(value as String).toLocal();

class DormNode {
  const DormNode(this.name, this.value, this.children);
  final String name, value;
  final List<DormNode> children;
  factory DormNode.fromJson(Map<String, dynamic> j) => DormNode(
    j['name'],
    j['value'],
    (j['children'] as List? ?? [])
        .map((n) => DormNode.fromJson(Map<String, dynamic>.from(n)))
        .toList(),
  );
}

class DormService {
  const DormService(
    this.id,
    this.label,
    this.codes,
    this.levelNames,
    this.nodes,
  );
  final String id, label;
  final List<String> codes, levelNames;
  final List<DormNode> nodes;
  factory DormService.fromJson(Map<String, dynamic> j) => DormService(
    j['id'],
    j['label'],
    (j['levels'] as List).map((x) => x['code'] as String).toList(),
    (j['levels'] as List).map((x) => x['name'] as String).toList(),
    (j['nodes'] as List)
        .map((n) => DormNode.fromJson(Map<String, dynamic>.from(n)))
        .toList(),
  );
}

class DormCatalog {
  const DormCatalog(this.updated, this.services);
  final String updated;
  final List<DormService> services;
  static Future<DormCatalog>? _loading;
  static DormCatalog? _cached;
  static Future<DormCatalog> load() => _cached != null
      ? Future.value(_cached!)
      : _loading ??= rootBundle
            .loadString('assets/data/nuist_dormitories.json')
            .then((s) {
              final j = jsonDecode(s) as Map<String, dynamic>;
              return _cached = DormCatalog(
                j['fetchedAt'],
                (j['services'] as List)
                    .map(
                      (s) => DormService.fromJson(Map<String, dynamic>.from(s)),
                    )
                    .toList(),
              );
            });
  bool contains(DormSelection selection) {
    final matching = services.where((s) => s.id == selection.serviceId);
    if (matching.isEmpty) return false;
    final service = matching.single;
    var nodes = service.nodes;
    if (selection.fields.length != service.codes.length) return false;
    for (final code in service.codes) {
      final found = nodes.where((n) => n.value == selection.fields[code]);
      if (found.isEmpty) return false;
      nodes = found.single.children;
    }
    return true;
  }
}

class DormSelection {
  const DormSelection(
    this.serviceId,
    this.serviceName,
    this.fields,
    this.names,
  );
  final String serviceId, serviceName;
  final Map<String, String> fields;
  final List<String> names;
  String get key => jsonEncode([
    serviceId,
    ...(fields.keys.toList()..sort()).map((k) => [k, fields[k]]),
  ]);
  String get label => [serviceName, ...names].join(' / ');
  Map<String, dynamic> toJson() => {
    'serviceId': serviceId,
    'serviceName': serviceName,
    'fields': fields,
    'names': names,
    'key': key,
  };
  factory DormSelection.fromJson(Map<String, dynamic> j) => DormSelection(
    j['serviceId'],
    j['serviceName'],
    Map<String, String>.from(j['fields']),
    List<String>.from(j['names']),
  );
}

class CampusCard {
  const CampusCard(
    this.label,
    this.electronicCents,
    this.physicalCents,
    this.lost,
    this.frozen,
  );
  final String label;
  final int electronicCents, physicalCents;
  final bool lost, frozen;
  factory CampusCard.fromJson(Map<String, dynamic> j) => CampusCard(
    j['label'],
    j['electronicCents'],
    j['physicalCents'],
    j['lost'],
    j['frozen'],
  );
  Map<String, dynamic> toJson() => {
    'label': label,
    'electronicCents': electronicCents,
    'physicalCents': physicalCents,
    'lost': lost,
    'frozen': frozen,
  };
}

class Wallet {
  const Wallet(this.cards, this.updatedAt);
  final List<CampusCard> cards;
  final DateTime updatedAt;
  int get balance => cards.fold(0, (n, c) => n + c.electronicCents);
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
    (j['cards'] as List)
        .map((x) => CampusCard.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    _stamp(j['updatedAt']),
  );
  Map<String, dynamic> toJson() => {
    'cards': cards.map((x) => x.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class BillRecord {
  const BillRecord(
    this.description,
    this.amountCents,
    this.income,
    this.directionKnown,
    this.time,
    this.method,
  );
  final String description, time, method;
  final int amountCents;
  final bool income, directionKnown;
  String get methodDisplay => directionKnown ? method : '$method · 收支方向待确认';
  String get amount =>
      '${directionKnown ? (income ? '+' : '−') : ''}${money(amountCents)}';
  factory BillRecord.fromJson(Map<String, dynamic> j) => BillRecord(
    j['description'],
    j['amountCents'],
    j['income'],
    j['directionKnown'],
    j['time'],
    j['method'],
  );
  Map<String, dynamic> toJson() => {
    'description': description,
    'amountCents': amountCents,
    'income': income,
    'directionKnown': directionKnown,
    'time': time,
    'method': method,
  };
}

class BillPage {
  const BillPage(
    this.month,
    this.page,
    this.total,
    this.size,
    this.incomeCents,
    this.expensesCents,
    this.records,
    this.updatedAt,
  );
  final String month;
  final int page, total, size, incomeCents, expensesCents;
  final List<BillRecord> records;
  final DateTime updatedAt;
  int get pages => (total / size).ceil();
  factory BillPage.fromJson(Map<String, dynamic> j) => BillPage(
    j['month'],
    j['page'],
    j['total'],
    j['size'],
    j['incomeCents'],
    j['expensesCents'],
    (j['records'] as List)
        .map((x) => BillRecord.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
    _stamp(j['updatedAt']),
  );
  Map<String, dynamic> toJson() => {
    'month': month,
    'page': page,
    'total': total,
    'size': size,
    'incomeCents': incomeCents,
    'expensesCents': expensesCents,
    'records': records.map((x) => x.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class Electricity {
  const Electricity(this.dormKey, this.fields, this.updatedAt);
  final String dormKey;
  final Map<String, String> fields;
  final DateTime updatedAt;
  MapEntry<String, String> get primary => fields.entries.firstWhere(
    (e) => e.key.contains('电量'),
    orElse: () => fields.entries.first,
  );
  String get unit => primary.key.contains('电量')
      ? '度'
      : RegExp('金额|电费|余额').hasMatch(primary.key)
      ? '元'
      : '';
  String get display {
    final n = num.tryParse(primary.value.replaceAll(RegExp('[度元]'), '').trim());
    return n == null
        ? primary.value
        : '${n.toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'}';
  }

  factory Electricity.fromJson(Map<String, dynamic> j) {
    final fields = Map<String, String>.from(j['fields']);
    if (fields.isEmpty) throw const FormatException('缺少电费字段。');
    return Electricity(j['dormKey'], fields, _stamp(j['updatedAt']));
  }
  Map<String, dynamic> toJson() => {
    'dormKey': dormKey,
    'fields': fields,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class AccountCache {
  const AccountCache({
    this.wallet,
    this.bills,
    this.currentBills,
    this.electricity,
  });
  final Wallet? wallet;
  final BillPage? bills, currentBills;
  final Electricity? electricity;
  AccountCache merge(Map<String, dynamic> j) {
    final nextBill = j['bills'] == null
        ? null
        : BillPage.fromJson(Map<String, dynamic>.from(j['bills']));
    return AccountCache(
      wallet: j['wallet'] == null
          ? wallet
          : Wallet.fromJson(Map<String, dynamic>.from(j['wallet'])),
      bills: nextBill ?? bills,
      currentBills: nextBill?.month == currentMonth() ? nextBill : currentBills,
      electricity: j['electricity'] == null
          ? electricity
          : Electricity.fromJson(Map<String, dynamic>.from(j['electricity'])),
    );
  }

  AccountCache withoutElectricity() =>
      AccountCache(wallet: wallet, bills: bills, currentBills: currentBills);
  Map<String, dynamic> toJson() => {
    'wallet': wallet?.toJson(),
    'bills': bills?.toJson(),
    'currentBills': currentBills?.toJson(),
    'electricity': electricity?.toJson(),
  };
  factory AccountCache.fromJson(Map<String, dynamic> j) => AccountCache(
    wallet: j['wallet'] == null
        ? null
        : Wallet.fromJson(Map<String, dynamic>.from(j['wallet'])),
    bills: j['bills'] == null
        ? null
        : BillPage.fromJson(Map<String, dynamic>.from(j['bills'])),
    currentBills: j['currentBills'] == null
        ? null
        : BillPage.fromJson(Map<String, dynamic>.from(j['currentBills'])),
    electricity: j['electricity'] == null
        ? null
        : Electricity.fromJson(Map<String, dynamic>.from(j['electricity'])),
  );
}
