import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/accounts/accounts.dart';
import 'package:nuist_aio/src/accounts/accounts_page.dart';
import 'package:nuist_aio/src/accounts/dorm_picker.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/shell.dart';

Map<String, dynamic> sampleBill({String? month, int page = 1}) => {
  'month': month ?? currentMonth(),
  'page': page,
  'total': 41,
  'size': 20,
  'incomeCents': 10000,
  'expensesCents': 2468,
  'records': [
    {
      'description': '示例消费',
      'amountCents': 1234,
      'income': false,
      'directionKnown': true,
      'time': '2026-11-01 08:00:00',
      'method': '示例支付',
    },
  ],
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
};
Map<String, dynamic> sampleWallet() => {
  'cards': [
    {
      'label': '示例校园卡',
      'electronicCents': 1234,
      'physicalCents': 251,
      'lost': false,
      'frozen': false,
    },
  ],
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
};
DormSelection firstRoom(DormService service) {
  var nodes = service.nodes;
  final path = <DormNode>[];
  for (int i = 0; i < service.codes.length; i++) {
    path.add(nodes.first);
    nodes = nodes.first.children;
  }
  return DormSelection(service.id, service.label, {
    for (int i = 0; i < path.length; i++) service.codes[i]: path[i].value,
  }, path.map((n) => n.name).toList());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'all service directories are complete, separate and contain exact paths',
    () async {
      final catalog = await DormCatalog.load();
      expect(catalog.services.map((s) => s.id).toSet(), {'448', '568', '429'});
      int count(List<DormNode> nodes) => nodes.fold(
        0,
        (n, x) => n + (x.children.isEmpty ? 1 : count(x.children)),
      );
      expect(catalog.services.map((s) => count(s.nodes)).toList(), [
        9796,
        423,
        2199,
      ]);
      for (final service in catalog.services) {
        final selected = firstRoom(service);
        expect(catalog.contains(selected), isTrue);
        expect(DormSelection.fromJson(selected.toJson()).key, selected.key);
        expect(
          catalog.contains(
            DormSelection(service.id, service.label, {
              ...selected.fields,
              'room_id': 'not-in-directory',
            }, selected.names),
          ),
          isFalse,
        );
      }
      expect(catalog.services.firstWhere((s) => s.id == '568').codes, [
        'building_id',
        'room_id',
      ]);
    },
  );
  test('money, pagination and income direction preserve cents', () {
    expect(money(1234), '12.34');
    expect(money(1), '0.01');
    expect(money(9007199254740991), '90071992547409.91');
    final bill = BillPage.fromJson(sampleBill());
    expect(bill.pages, 3);
    expect(bill.records.single.amount, '−12.34');
    expect(BillRecord('收入', 1234, true, true, '', '').amount, '+12.34');
    expect(BillRecord('未知', 1234, false, false, '', '').amount, '12.34');
  });
  test('historical bills never overwrite current-month homepage summary', () {
    final current = const AccountCache().merge({'bills': sampleBill()});
    final historical = current.merge({
      'bills': sampleBill(month: '2020-02', page: 2),
    });
    expect(historical.bills!.month, '2020-02');
    expect(historical.currentBills!.month, currentMonth());
    expect(historical.currentBills!.expensesCents, 2468);
    expect(
      AccountCache.fromJson(historical.toJson()).toJson(),
      historical.toJson(),
    );
  });
  test('electricity retains precise value, marks correct units and rejects empty fields', () {
    final data = Electricity('room', {'剩余电量': '123.456789'}, DateTime.now());
    expect(data.display, '123.46 度');
    expect(data.fields['剩余电量'], '123.456789');
    expect(
      Electricity('room', {'电费余额': '-12.34'}, DateTime.now()).display,
      '-12.34 元',
    );
    expect(
      () => Electricity.fromJson({
        'dormKey': 'x',
        'fields': {},
        'updatedAt': DateTime.now().toIso8601String(),
      }),
      throwsFormatException,
    );
  });
  test('switching rooms clears power and discards an in-flight result for the old room', () async {
    final catalog = await DormCatalog.load();
    final a = firstRoom(catalog.services.first),
        b = firstRoom(catalog.services[1]);
    final state = AppState();
    await state.load();
    await state.setDorm(a);
    final data = {
      'wallet': sampleWallet(),
      'electricity': {
        'dormKey': a.key,
        'fields': {'剩余电量': '123'},
        'updatedAt': DateTime.now().toIso8601String(),
      },
    };
    await state.saveAccounts(data, generation: state.sessionGeneration);
    expect(state.accounts.electricity, isNotNull);
    await state.setDorm(b);
    expect(state.accounts.electricity, isNull);
    await state.saveAccounts(data, generation: state.sessionGeneration);
    expect(state.accounts.electricity, isNull);
    final loaded = AppState();
    await loaded.load();
    expect(loaded.dorm!.key, b.key);
    expect(loaded.accounts.wallet!.balance, 1234);
    final oldGeneration = state.sessionGeneration;
    await state.clearPrivateData();
    await state.saveAccounts(data, generation: oldGeneration);
    expect(state.accounts.wallet, isNull);
    final cleared = AppState();
    await cleared.load();
    expect(cleared.dorm, isNull);
    expect(cleared.accounts.wallet, isNull);
  });
  test('query navigation never allows order or payment pages', () {
    expect(CampusAccountsPage.allowed(CampusAccountsPage.entry), isTrue);
    for (final raw in [
      'http://icard.nuist.edu.cn/plat-pc/',
      'https://icard.nuist.edu.cn/charge-pc/pays/448',
      'https://icard.nuist.edu.cn/charge/order/add',
      'https://icard.nuist.edu.cn.evil.test/plat-pc/',
      'https://icard.nuist.edu.cn:8443/plat-pc/',
    ]) {
      expect(CampusAccountsPage.allowed(Uri.parse(raw)), isFalse);
    }
  });
  Future<AppState> setup(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = AppState();
    await state.load();
    state.onboarded = true;
    await tester.pumpWidget(CampusApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets(
    'home displays cached account amounts and query pages work without a platform WebView',
    (tester) async {
      final state = await setup(tester);
      await state.saveAccounts({
        'wallet': sampleWallet(),
        'bills': sampleBill(),
      }, generation: state.sessionGeneration);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('¥ 12.34'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('¥ 12.34').hitTestable(), findsOneWidget);
      expect(find.text('¥ 24.68').hitTestable(), findsOneWidget);
      await tester.tap(find.text('¥ 12.34').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('电子账户余额'), findsOneWidget);
      await tester.tap(find.text('账单'));
      await tester.pumpAndSettle();
      expect(find.text('示例消费'), findsOneWidget);
      expect(find.text('¥ −12.34'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline dorm picker searches rooms and resets descendants on service change',
    (tester) async {
      final state = await setup(tester);
      Navigator.of(tester.element(find.byType(CampusShell))).push(
        MaterialPageRoute<void>(builder: (_) => DormPickerPage(state: state)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('沁园42、43栋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('楼栋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('沁园42栋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('房间'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '101');
      await tester.pumpAndSettle();
      final option = find.byType(ListTile).hitTestable().last;
      await tester.tap(option);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, '保存宿舍');
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(find.text('本部缴电费'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('account cards remain usable on small screens with large text', (
    tester,
  ) async {
    final state = await setup(tester, scale: 1.8);
    await state.saveAccounts({
      'wallet': sampleWallet(),
      'bills': sampleBill(),
    }, generation: state.sessionGeneration);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('¥ 12.34'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('¥ 12.34').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('账单'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
