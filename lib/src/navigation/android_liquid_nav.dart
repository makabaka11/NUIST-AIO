import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

/// Hybrid composition keeps the Kotlin bar in the native hierarchy, with
/// Flutter's background image surface available for GPU backdrop sampling.
class AndroidLiquidNav extends StatefulWidget {
  const AndroidLiquidNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<AndroidLiquidNav> createState() => _AndroidLiquidNavState();
}

class _AndroidLiquidNavState extends State<AndroidLiquidNav> {
  MethodChannel? _channel;
  bool _ready = false;

  Map<String, Object> get _configuration {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return {
      'selectedIndex': widget.selectedIndex,
      'primary': colors.primary.toARGB32(),
      'onSurface': colors.onSurface.toARGB32(),
      'surface': colors.surfaceContainerHigh.toARGB32(),
      'dark': colors.brightness == Brightness.dark,
      'textScale': media.textScaler.scale(12) / 12,
      'reduceMotion': media.disableAnimations,
      'rtl': Directionality.of(context) == TextDirection.rtl,
    };
  }

  Future<void> _update() async {
    if (!_ready) return;
    try {
      await _channel?.invokeMethod<void>('configure', _configuration);
    } on PlatformException {
      // A disposed platform view can finish a queued configuration update.
    }
  }

  @override
  Widget build(BuildContext context) {
    _update();
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 472),
          child: SizedBox(
            // The original 56dp indicator expands to 78dp on press; reserve
            // space around the 64dp bar so hybrid composition won't clip it.
            height: 96,
            child: PlatformViewLink(
              viewType: 'nuistaio/liquid_nav',
              surfaceFactory: (context, controller) => AndroidViewSurface(
                controller: controller as AndroidViewController,
                gestureRecognizers:
                    const <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        EagerGestureRecognizer.new,
                      ),
                    },
                hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              ),
              onCreatePlatformView: (params) {
                final channel = MethodChannel(
                  'nuistaio/liquid_nav/${params.id}',
                );
                _channel = channel;
                channel.setMethodCallHandler((call) async {
                  if (!mounted || call.method != 'select') return;
                  final index = call.arguments;
                  if (index is int && index >= 0 && index < 4) {
                    widget.onSelected(index);
                  }
                });
                return PlatformViewsService.initExpensiveAndroidView(
                    id: params.id,
                    viewType: 'nuistaio/liquid_nav',
                    layoutDirection: Directionality.of(context),
                    creationParams: _configuration,
                    creationParamsCodec: const StandardMessageCodec(),
                    onFocus: () => params.onFocusChanged(true),
                  )
                  ..addOnPlatformViewCreatedListener(
                    params.onPlatformViewCreated,
                  )
                  ..addOnPlatformViewCreatedListener((_) {
                    if (!mounted) return;
                    _ready = true;
                    _update();
                  })
                  ..create();
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ready = false;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }
}
