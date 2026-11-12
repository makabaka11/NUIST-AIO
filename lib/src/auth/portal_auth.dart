import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'session_store.dart';
import '../services/navigation.dart';
import '../services/sso_diagnostics.dart';

/// Bounded portal recovery in the same native cookie container as all services.
class PortalAuth {
  HeadlessInAppWebView? _view;
  Completer<bool>? _pending;
  int _generation = 0;

  Future<void> close() async {
    _generation++;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final view = _view;
    _view = null;
    await view?.dispose();
  }

  Future<bool> verify(
    SessionStore sessions, {
    bool forcePasskey = false,
  }) async {
    await close();
    final generation = _generation;
    final owner = await sessions.accountKey();
    if (owner == null || generation != _generation) return false;
    final bundle = await sessions.readPasskey();
    SsoDiagnostics.record('portal', 'passkey_available', ok: bundle != null);
    if (generation != _generation) return false;
    final entry = forcePasskey && bundle != null
        ? SessionStore.loginUri.replace(
            queryParameters: {
              ...SessionStore.loginUri.queryParameters,
              'renew': 'true',
            },
          )
        : SessionStore.loginUri;
    final done = Completer<bool>();
    _pending = done;
    bool probing = false, attempted = false, documentReady = false;
    int document = 0, assertionDocument = -1;
    Future<void> inspect(InAppWebViewController c) async {
      if (probing ||
          !documentReady ||
          done.isCompleted ||
          generation != _generation) {
        return;
      }
      probing = true;
      final inspectedDocument = document;
      try {
        final url = await c.getUrl();
        final uri = Uri.tryParse(url?.toString() ?? '');
        if (!SessionStore.isAllowedNavigation(uri)) return;
        final stable = await c
            .evaluateJavascript(
              source:
                  'location.origin === ${jsonEncode(uri!.origin)} && location.pathname === ${jsonEncode(uri.path)} && document.readyState === "complete" && typeof window.flutter_inappwebview?.callHandler === "function"',
            )
            .timeout(const Duration(seconds: 2));
        if (stable != true || inspectedDocument != document) return;
        SsoDiagnostics.record('portal', 'auth_document', location: uri);
        if (SessionStore.isPortalLanding(uri)) {
          final script = await rootBundle.loadString(
            'assets/js/nuist_portal_probe.js',
          );
          final result = await c
              .callAsyncJavaScript(functionBody: script)
              .timeout(const Duration(seconds: 12));
          if (generation != _generation ||
              done.isCompleted ||
              inspectedDocument != document) {
            return;
          }
          final value = result?.value;
          SsoDiagnostics.record(
            'portal',
            'auth_identity_probe',
            ok:
                result?.error == null &&
                value is Map &&
                value['accountKey'] == owner,
          );
          if (result?.error == null &&
              value is Map &&
              value['accountKey'] == owner) {
            final saved = await sessions.capturePortalSession(
              accountKey: owner,
              isCurrent: () => generation == _generation && !done.isCompleted,
              displayName: value['displayName'] as String? ?? '',
            );
            if (!done.isCompleted) {
              done.complete(saved && generation == _generation);
            }
          } else {
            done.complete(false);
          }
        } else if (SchoolNavigation.trusted(uri, {'authserver.nuist.edu.cn'}) &&
            uri.path == '/authserver/login') {
          if (attempted) {
            if (document > assertionDocument) done.complete(false);
          } else if (bundle == null) {
            done.complete(false);
          } else {
            attempted = true;
            assertionDocument = document;
            final script = await rootBundle.loadString(
              'assets/js/nuist_passkey_login.js',
            );
            final result = await c
                .callAsyncJavaScript(
                  functionBody: script,
                  arguments: {'bundle': bundle},
                )
                .timeout(const Duration(seconds: 15));
            SsoDiagnostics.record(
              'portal',
              'passkey_assertion',
              ok: result?.error == null && result?.value == true,
              type: result?.error == null
                  ? result?.value.runtimeType.toString()
                  : 'script_error',
            );
            final stage = await c
                .evaluateJavascript(
                  source: "['context','execution','challenge','challenge_response','key_import','signing','submitting'].includes(globalThis.__aioAssertionStage) ? globalThis.__aioAssertionStage : 'unknown'",
                )
                .timeout(const Duration(seconds: 2));
            SsoDiagnostics.record(
              'portal',
              'passkey_stage',
              type: stage is String ? stage : 'unknown',
            );
            // Navigation can destroy the JS result. The landing probe decides success.
            if (result?.value == false && !done.isCompleted) {
              done.complete(false);
            }
          }
        }
      } catch (error) {
        SsoDiagnostics.record(
          'portal',
          'auth_inspect_error',
          type: error.runtimeType.toString(),
        );
        if (!done.isCompleted && inspectedDocument == document) {
          done.complete(false);
        }
      } finally {
        probing = false;
      }
    }

    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(entry.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      ),
      shouldOverrideUrlLoading: (c, action) async {
        final uri = Uri.tryParse(action.request.url?.toString() ?? '');
        if (SessionStore.isAllowedNavigation(uri)) {
          return NavigationActionPolicy.ALLOW;
        }
        final secure = SchoolNavigation.httpsUpgrade(
          uri,
          SessionStore.isAllowedNavigation,
        );
        if (secure != null) {
          await c.loadUrl(
            urlRequest: URLRequest(url: WebUri(secure.toString())),
          );
        }
        return NavigationActionPolicy.CANCEL;
      },
      onLoadStart: (_, _) {
        document++;
        documentReady = false;
      },
      onLoadStop: (c, _) {
        documentReady = true;
        unawaited(inspect(c));
      },
      onReceivedHttpError: (_, request, response) {
        SsoDiagnostics.record(
          'portal',
          'auth_http',
          status: response.statusCode,
          mainFrame: request.isForMainFrame,
        );
      },
      onReceivedError: (_, request, _) {
        SsoDiagnostics.record(
          'portal',
          'auth_load_error',
          mainFrame: request.isForMainFrame,
        );
        if (request.isForMainFrame == true && !done.isCompleted) {
          done.complete(false);
        }
      },
    );
    _view = view;
    Timer? timer;
    try {
      return await (() async {
        await view.run();
        timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
          final controller = view.webViewController;
          if (controller != null) unawaited(inspect(controller));
        });
        return await done.future;
      })().timeout(const Duration(seconds: 45), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      timer?.cancel();
      if (identical(_view, view)) await close();
    }
  }
}
