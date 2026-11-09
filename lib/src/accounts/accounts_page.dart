import '../services/script_result.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_state.dart';
import '../services/sso_diagnostics.dart';
import '../widgets.dart';
import '../webview_page_lifecycle.dart';
import '../services/navigation.dart';
import 'accounts.dart';
import 'dorm_picker.dart';

enum AccountSection { card, bills, electricity }

void openAccounts(
  BuildContext context,
  AppState state, {
  AccountSection section = AccountSection.card,
  bool autoSync = false,
}) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CampusAccountsPage(
        state: state,
        initial: section,
        autoSync: autoSync,
      ),
    ),
  );
}

class CampusAccountsPage extends StatefulWidget {
  const CampusAccountsPage({
    super.key,
    required this.state,
    this.initial = AccountSection.card,
    this.autoSync = false,
  });
  final AppState state;
  final AccountSection initial;
  final bool autoSync;
  static final entry = SchoolNavigation.cardEntry;
  static bool allowed(Uri? uri) => SchoolNavigation.card(uri);
  @override
  State<CampusAccountsPage> createState() => _CampusAccountsPageState();
}

class _CampusAccountsPageState extends State<CampusAccountsPage>
    with WebViewPageLifecycle<CampusAccountsPage> {
  @override
  void initState() {
    super.initState();
    if (supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          begin(
            widget.autoSync
                ? 'sync'
                : switch (widget.initial) {
                    AccountSection.card => 'wallet',
                    AccountSection.bills => 'bills',
                    AccountSection.electricity =>
                      widget.state.dorm == null ? 'sync' : 'electricity',
                  },
          );
        }
      });
    }
  }

  InAppWebViewController? controller;
  late AccountSection section = widget.initial;
  bool started = false,
      showBrowser = false,
      ready = false,
      busy = false,
      probing = false;
  String? error;
  String month = currentMonth(), pending = 'sync';
  int page = 1;
  bool get supported => widget.state.cardSession.available;
  Future<Map<String, dynamic>> script(String task) async {
    final url = await controller?.getUrl();
    if (url?.scheme != 'https' || url?.host != 'icard.nuist.edu.cn') {
      throw const FormatException('请先完成学校一卡通登录。');
    }
    final dorm = widget.state.dorm;
    if (dorm != null && !(await DormCatalog.load()).contains(dorm)) {
      throw const FormatException('宿舍目录已变化，请重新选择宿舍。');
    }
    final body = await rootBundle.loadString('assets/js/nuist_accounts.js');
    final result = await controller!
        .callAsyncJavaScript(
          functionBody: schoolScriptBody(body),
          arguments: {
            'task': task,
            'month': month,
            'page': page,
            'dorm': dorm?.toJson(),
          },
        )
        .timeout(const Duration(seconds: 120));
    if (result?.error != null || result?.value == null) {
      throw const FormatException('校园服务读取失败，请重试。');
    }
    final value = result!.value;
    final data = Map<String, dynamic>.from(
      (value is String ? jsonDecode(value) : value) as Map,
    );
    if (data['ok'] != true) {
      throw FormatException(data['error'] as String? ?? '查询失败。');
    }
    return data;
  }

  Future<void> read(String task) async {
    if (busy || !mounted) return;
    final generation = widget.state.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Map<String, dynamic> data;
      if (!showBrowser) {
        data = await widget.state.cardSession.query(
          task,
          widget.state.accountArguments(month: month, page: page),
        );
      } else {
        data = await script(task);
      }
      if (!mounted) return;
      if (!['wallet', 'bills', 'electricity'].any(data.containsKey)) {
        throw const FormatException('没有获取到有效数据，请重新连接后重试。');
      }
      await widget.state.saveAccounts(data, generation: generation);
      if (!mounted) return;
      if (generation != widget.state.sessionGeneration) {
        throw const FormatException('账号状态已变化，请重新查询。');
      }
      final failures = (data['errors'] as List? ?? [])
          .map(
            (e) => switch (e['part']) {
              'wallet' => '校园卡余额未更新',
              'bills' => '账单未更新',
              'electricity' => '电费未更新',
              _ => '部分数据未更新',
            },
          )
          .join('；');
      setState(() {
        showBrowser = false;
        error = failures.isEmpty ? null : '$failures。保留上次缓存，请稍后重试。';
      });
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          started = true;
          ready = false;
          showBrowser = true;
        });
      }
    } catch (e) {
      SsoDiagnostics.record(
        'campusCard',
        'account_query_error',
        type: e.runtimeType.toString(),
      );
      if (mounted) {
        setState(() {
          error = '查询或保存失败，请检查网络后重试。';
          started = true;
          showBrowser = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> probeAndRead() async {
    if (probing || busy || !mounted) return;
    setState(() => probing = true);
    try {
      final result = await script('probe');
      if (!mounted) return;
      if (result['ready'] == true) {
        ready = true;
        await read(pending);
      } else {
        setState(() => error = '请在官方页面完成登录，再检查连接。');
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法连接学校服务，请重新加载。');
    } finally {
      if (mounted) {
        setState(() => probing = false);
      }
    }
  }

  Future<void> inspectCardPage(WebUri? url) async {
    if (mounted &&
        webViewVisible &&
        showBrowser &&
        !busy &&
        !probing &&
        url?.scheme == 'https' &&
        url?.host == 'icard.nuist.edu.cn' &&
        (url!.path == '/plat-pc' || url.path.startsWith('/plat-pc/'))) {
      await probeAndRead();
    }
  }

  Future<void> begin(String task) async {
    if (busy || probing) return;
    pending = task;
    if (!supported) {
      setState(() => error = '请在安卓或 iOS 客户端连接一卡通。');
      return;
    }
    if (showBrowser && ready && controller != null) {
      await read(task);
      return;
    }
    setState(() {
      showBrowser = false;
      error = null;
    });
    await read(task);
  }

  Future<void> reconnect() async {
    if (busy || probing) return;
    setState(() {
      ready = false;
      showBrowser = true;
      error = null;
    });
    await controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(CampusAccountsPage.entry.toString())),
    );
  }

  Future<void> dormPicker() async {
    final old = widget.state.dorm?.key;
    await openDormPicker(context, widget.state);
    if (mounted && widget.state.dorm != null && old != widget.state.dorm?.key) {
      await begin('electricity');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => guardWebViewPage(
      Scaffold(
        appBar: AppBar(
          title: Text(showBrowser ? '连接学校一卡通' : '校园账户'),
          actions: [
            if (showBrowser)
              IconButton(
                tooltip: '返回数据',
                icon: const Icon(Icons.dashboard_outlined),
                onPressed: () => setState(() => showBrowser = false),
              ),
            IconButton(
              tooltip: showBrowser ? '重新连接' : '更新账户',
              icon: const Icon(Icons.refresh),
              onPressed: busy || probing
                  ? null
                  : () => showBrowser ? reconnect() : begin('sync'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (busy || probing) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: showBrowser ? 1 : 0,
                  children: [
                    nativeBody(context),
                    if (started && webViewVisible)
                      Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            child: const Text(
                              '学校官方页面 · 完成登录后读取余额与账单。仅同步查询数据，凭据保留在学校页面会话中。',
                            ),
                          ),
                          Expanded(
                            child: InAppWebView(
                              initialUrlRequest: URLRequest(
                                url: WebUri(
                                  CampusAccountsPage.entry.toString(),
                                ),
                              ),
                              initialSettings: InAppWebViewSettings(
                                javaScriptEnabled: true,
                                useHybridComposition: false,
                                preferredContentMode:
                                    UserPreferredContentMode.DESKTOP,
                                useShouldOverrideUrlLoading: true,
                                supportMultipleWindows: false,
                                javaScriptCanOpenWindowsAutomatically: false,
                                mixedContentMode:
                                    MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                                isInspectable: false,
                              ),
                              onWebViewCreated: (value) => controller = value,
                              shouldOverrideUrlLoading: (_, action) async {
                                final u = action.request.url;
                                if (action.isForMainFrame == false) {
                                  return u?.toString() == 'about:blank' ||
                                          CampusAccountsPage.allowed(
                                            u == null
                                                ? null
                                                : Uri.tryParse(u.toString()),
                                          )
                                      ? NavigationActionPolicy.ALLOW
                                      : NavigationActionPolicy.CANCEL;
                                }
                                if (CampusAccountsPage.allowed(
                                  u == null ? null : Uri.tryParse(u.toString()),
                                )) {
                                  return NavigationActionPolicy.ALLOW;
                                }
                                final secure = SchoolNavigation.httpsUpgrade(
                                  u == null ? null : Uri.tryParse(u.toString()),
                                  CampusAccountsPage.allowed,
                                );
                                if (secure != null) {
                                  await controller?.loadUrl(
                                    urlRequest: URLRequest(
                                      url: WebUri(secure.toString()),
                                    ),
                                  );
                                  return NavigationActionPolicy.CANCEL;
                                }
                                if (mounted) {
                                  setState(
                                    () => error = '此链接超出查询范围，请返回一卡通登录页面。',
                                  );
                                }
                                return NavigationActionPolicy.CANCEL;
                              },
                              onLoadStop: (_, url) => inspectCardPage(url),
                              onUpdateVisitedHistory: (_, url, _) =>
                                  inspectCardPage(url),
                              onReceivedError: (_, request, _) {
                                if (mounted && request.isForMainFrame == true) {
                                  setState(
                                    () => error = '学校页面加载失败，请检查网络后重新连接。',
                                  );
                                }
                              },
                              onReceivedHttpError: (_, request, _) {
                                if (mounted && request.isForMainFrame == true) {
                                  setState(() => error = '学校服务暂不可用，请稍后重试。');
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                              onPressed: busy || probing ? null : probeAndRead,
                              icon: const Icon(Icons.sync),
                              label: Text(
                                busy || probing ? '正在读取…' : '已完成登录，检查连接',
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget nativeBody(BuildContext context) {
    final cache = widget.state.accounts;
    final colors = Theme.of(context).colorScheme;
    return PageBody(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              (AccountSection.card, '校园卡'),
              (AccountSection.bills, '账单'),
              (AccountSection.electricity, '电费'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: section == item.$1,
                onSelected: (_) {
                  setState(() => section = item.$1);
                  if (supported) {
                    begin(switch (item.$1) {
                      AccountSection.card => 'wallet',
                      AccountSection.bills => 'bills',
                      AccountSection.electricity =>
                        widget.state.dorm == null ? 'sync' : 'electricity',
                    });
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (section == AccountSection.card) ...[
          if (cache.wallet == null)
            EmptyCard(
              icon: Icons.credit_card_outlined,
              title: '连接校园卡',
              message: '从学校一卡通同步电子账户余额，查询结果仅保存在本机。',
              action: FilledButton(
                onPressed: busy ? null : () => begin('sync'),
                child: const Text('连接并同步'),
              ),
            )
          else if (cache.wallet!.cards.isEmpty)
            const EmptyCard(
              icon: Icons.credit_card_off_outlined,
              title: '暂无可用卡账户',
              message: '学校接口未返回卡包，请检查一卡通账号。',
            )
          else ...[
            for (final card in cache.wallet!.cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  color: colors.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        const Text('电子账户余额'),
                        const SizedBox(height: 8),
                        Text(
                          '¥ ${money(card.electronicCents)}',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 16),
                        Text('卡片账户余额（含待结算）：¥ ${money(card.physicalCents)}'),
                        if (card.lost || card.frozen)
                          Text(
                            [
                              if (card.lost) '已挂失',
                              if (card.frozen) '已冻结',
                            ].join(' · '),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            stamp(cache.wallet!.updatedAt),
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => begin('wallet'),
              icon: const Icon(Icons.sync),
              label: const Text('更新余额'),
            ),
          ],
        ],
        if (section == AccountSection.bills) ...billBody(context),
        if (section == AccountSection.electricity) ...[
          Card(
            color: colors.surfaceContainerLow,
            child: ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: const Text('实际宿舍'),
              subtitle: Text(widget.state.dorm?.label ?? '尚未选择宿舍'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : dormPicker,
            ),
          ),
          const SizedBox(height: 20),
          if (widget.state.dorm == null)
            EmptyCard(
              icon: Icons.bolt_outlined,
              title: '先选择宿舍',
              message: '根据学校目录选择服务范围、园区、楼栋和房间。',
              action: FilledButton(
                onPressed: dormPicker,
                child: const Text('选择宿舍'),
              ),
            )
          else if (cache.electricity == null ||
              cache.electricity!.dormKey != widget.state.dorm!.key)
            EmptyCard(
              icon: Icons.bolt_outlined,
              title: '还没有电费数据',
              message: '已保存宿舍，连接一卡通后可读取当前余量。',
              action: FilledButton(
                onPressed: busy ? null : () => begin('electricity'),
                child: const Text('查询所选宿舍'),
              ),
            )
          else ...[
            Card(
              color: colors.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cache.electricity!.primary.key,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      cache.electricity!.display,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    for (final entry in cache.electricity!.fields.entries.where(
                      (e) => e.key != cache.electricity!.primary.key,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('${entry.key}：${entry.value}'),
                      ),
                  ],
                ),
              ),
            ),
            stamp(cache.electricity!.updatedAt),
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => begin('electricity'),
              icon: const Icon(Icons.sync),
              label: const Text('更新电费'),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Text(
          '页面显示本机查询缓存，余额和电量可能已变化，请按需更新。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget stamp(DateTime date) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      '更新于 ${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
  List<Widget> billBody(BuildContext context) {
    final bill = widget.state.accounts.bills;
    final data = bill?.month == month && bill?.page == page ? bill : null;
    final now = chinaNow();
    final months = [
      for (int i = 0; i < 24; i++)
        DateTime(now.year, now.month - i).toIso8601String().substring(0, 7),
    ];
    if (!months.contains(month)) months.add(month);
    return [
      DropdownButtonFormField<String>(
        initialValue: month,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '账单月份'),
        items: months
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
        onChanged: busy
            ? null
            : (value) async {
                if (value == null) return;
                setState(() {
                  month = value;
                  page = 1;
                });
                await begin('bills');
              },
      ),
      const SizedBox(height: 16),
      if (data == null)
        EmptyCard(
          icon: Icons.receipt_long_outlined,
          title: '读取所选月份账单',
          message: '包含电子账户与聚合支付等交易，支出使用学校服务端汇总。',
          action: FilledButton(
            onPressed: busy ? null : () => begin('bills'),
            child: const Text('查询账单'),
          ),
        )
      else ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                Text('支出 ¥ ${money(data.expensesCents)}'),
                Text('收入 ¥ ${money(data.incomeCents)}'),
                Text('共 ${data.total} 条'),
              ],
            ),
          ),
        ),
        stamp(data.updatedAt),
        if (data.records.isEmpty) const Text('该月份暂无账单记录。'),
        for (final record in data.records)
          Card(
            child: ListTile(
              title: Text(record.description),
              subtitle: Text('${record.time}\n${record.methodDisplay}'),
              isThreeLine: true,
              trailing: Text(
                '¥ ${record.amount}',
                style: TextStyle(
                  color: record.income
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.description,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Text('¥ ${record.amount}'),
                        const SizedBox(height: 12),
                        Text(record.time),
                        const SizedBox(height: 12),
                        Text(record.methodDisplay),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: page <= 1 || busy
                  ? null
                  : () async {
                      setState(() => page--);
                      await begin('bills');
                    },
              child: const Text('上一页'),
            ),
            Text('$page / ${data.pages == 0 ? 1 : data.pages}'),
            OutlinedButton(
              onPressed: page >= data.pages || busy
                  ? null
                  : () async {
                      setState(() => page++);
                      await begin('bills');
                    },
              child: const Text('下一页'),
            ),
          ],
        ),
      ],
    ];
  }
}
