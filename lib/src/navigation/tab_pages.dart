import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Persistent tab pages: MIUIX pans horizontally; MD3 keeps its fade transition.
/// All pages stay mounted so changing the theme or tab preserves local state.
class TabPages extends StatefulWidget {
  const TabPages({
    super.key,
    required this.index,
    required this.horizontal,
    required this.onSelected,
    required this.children,
  });

  final int index;
  final bool horizontal;
  final ValueChanged<int> onSelected;
  final List<Widget> children;

  @override
  State<TabPages> createState() => _TabPagesState();
}

class _TabPagesState extends State<TabPages> with TickerProviderStateMixin {
  // miuix 0.9.4 PagerNavigationSpringSpec, used by SukiSU's springAnimateToPage.
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 322.2,
    damping: 32.31,
  );
  late final _position = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late int _target;
  int _revision = 0;
  int _dragStart = 0;
  bool _dragging = false;
  double _width = 1;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);
  double get _direction =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;
  double get _page => _position.value.clamp(0.0, widget.children.length - 1.0);

  @override
  void initState() {
    super.initState();
    _target = widget.index;
  }

  @override
  void didUpdateWidget(covariant TabPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.horizontal != widget.horizontal) {
      _target = widget.index;
      _jumpTo(widget.index);
      _fade.value = 1;
    } else if (oldWidget.index != widget.index && widget.index != _target) {
      _target = widget.index;
      if (widget.horizontal) {
        _settle(widget.index);
      } else {
        _jumpTo(widget.index);
        if (_reduceMotion) {
          _fade.value = 1;
        } else {
          _fade.forward(from: 0);
        }
      }
    }
  }

  void _jumpTo(int index) {
    _revision++;
    _position.stop();
    _position.value = index.toDouble();
  }

  void _report(int index) {
    if (_target == index) return;
    _target = index;
    widget.onSelected(index);
  }

  void _settle(int index, [double velocity = 0]) {
    final revision = ++_revision;
    _position.stop();
    if (_reduceMotion || (_position.value - index).abs() < 0.00001) {
      _position.value = index.toDouble();
      return;
    }
    _position
        .animateWith(
          SpringSimulation(
            _spring,
            _position.value,
            index.toDouble(),
            velocity,
            tolerance: Tolerance(
              distance: 0.5 / _width,
              velocity: 31.25 / _width,
            ),
          ),
        )
        .whenCompleteOrCancel(() {
          // A newer tab click or drag owns the position after interruption.
          if (mounted && revision == _revision) {
            _position.value = index.toDouble();
          }
        });
  }

  void _dragBegin(DragStartDetails details) {
    _revision++;
    _position.stop();
    _dragging = true;
    _dragStart = _page.round();
    _report(_dragStart);
  }

  void _dragUpdate(DragUpdateDetails details) {
    _position.value = (_page - details.delta.dx * _direction / _width).clamp(
      0.0,
      widget.children.length - 1.0,
    );
    _report(_page.round());
  }

  void _dragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = -details.velocity.pixelsPerSecond.dx * _direction / _width;
    final target =
        (velocity.abs() > 0.5
                ? (velocity > 0 ? _page.ceil() : _page.floor())
                : _page.round())
            .clamp(0, widget.children.length - 1);
    _report(target);
    _settle(target, velocity);
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _report(_dragStart);
    _settle(_dragStart);
  }

  void _accessibilityStep(int step) {
    final next = (_target + step).clamp(0, widget.children.length - 1);
    _report(next);
    _settle(next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
      return Semantics(
        onScrollLeft: widget.horizontal
            ? () => _accessibilityStep(_direction.toInt())
            : null,
        onScrollRight: widget.horizontal
            ? () => _accessibilityStep(-_direction.toInt())
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.horizontal ? _dragBegin : null,
          onHorizontalDragUpdate: widget.horizontal ? _dragUpdate : null,
          onHorizontalDragEnd: widget.horizontal ? _dragEnd : null,
          onHorizontalDragCancel: widget.horizontal ? _dragCancel : null,
          child: FadeTransition(
            opacity: _fade.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _position,
                builder: (context, _) {
                  final page = _page;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      for (var i = 0; i < widget.children.length; i++)
                        Offstage(
                          key: ValueKey('shell-tab-$i'),
                          offstage: i < page.floor() || i > page.ceil(),
                          child: TickerMode(
                            enabled: i >= page.floor() && i <= page.ceil(),
                            child: Transform.translate(
                              offset: Offset(
                                (i - page) * _width * _direction,
                                0,
                              ),
                              child: widget.children[i],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    _revision++;
    _position.dispose();
    _fade.dispose();
    super.dispose();
  }
}
