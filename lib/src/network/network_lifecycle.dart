import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app_state.dart';

/// Keep startup probing outside load(), so rendering and offline data never wait
/// for network access and tests that load preferences do not perform requests.
class CampusNetworkLifecycle extends StatefulWidget {
  const CampusNetworkLifecycle({
    super.key,
    required this.state,
    required this.child,
  });
  final AppState state;
  final Widget child;
  @override
  State<CampusNetworkLifecycle> createState() => _CampusNetworkLifecycleState();
}

class _CampusNetworkLifecycleState extends State<CampusNetworkLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.state.detectNetworkLinks());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !widget.state.networkLinks.checking) {
      unawaited(widget.state.maintainPortal());
      unawaited(widget.state.detectNetworkLinks(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
