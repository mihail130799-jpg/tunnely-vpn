import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/vpn_platform.dart';
import '../theme/app_theme.dart';

/// The connect button: concentric arches with a portal and a road, after the
/// Tunnely logo. Arches light up one by one while connecting, the portal
/// flashes on connect, and the road markings drift toward the light.
class TunnelButton extends StatefulWidget {
  const TunnelButton({super.key, required this.status, required this.onTap, this.size = 260});

  final VpnStatus status;
  final VoidCallback onTap;
  final double size;

  @override
  State<TunnelButton> createState() => _TunnelButtonState();
}

class _TunnelButtonState extends State<TunnelButton> with TickerProviderStateMixin {
  late final AnimationController _lit = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _road = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0,
    upperBound: 1,
  );

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply(null, widget.status);
  }

  @override
  void didUpdateWidget(TunnelButton old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _apply(old.status, widget.status);
  }

  void _apply(VpnStatus? from, VpnStatus to) {
    switch (to) {
      case VpnStatus.connecting:
      case VpnStatus.reconnecting:
        _road.stop();
        if (_reduceMotion) {
          _lit.value = .5;
        } else {
          _lit.repeat();
        }
      case VpnStatus.connected:
        _lit.animateTo(1, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
        if (from != null && from != VpnStatus.connected) {
          HapticFeedback.mediumImpact();
          if (!_reduceMotion) _flash.forward(from: 0);
        }
        if (!_reduceMotion) _road.repeat();
      case VpnStatus.disconnected:
      case VpnStatus.disconnecting:
      case VpnStatus.error:
        _road.stop();
        _lit.animateBack(0, duration: const Duration(milliseconds: 400), curve: Curves.easeIn);
        if (from == VpnStatus.connected) HapticFeedback.lightImpact();
        if (to == VpnStatus.error && from != VpnStatus.error) HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _lit.dispose();
    _flash.dispose();
    _road.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final connecting = widget.status == VpnStatus.connecting || widget.status == VpnStatus.reconnecting;
    return Semantics(
      button: true,
      label: switch (widget.status) {
        VpnStatus.connected => 'Отключить VPN',
        VpnStatus.connecting || VpnStatus.reconnecting => 'Подключение, нажмите чтобы отменить',
        _ => 'Подключить VPN',
      },
      child: GestureDetector(
        onTapDown: (_) => _press.forward(),
        onTapCancel: () => _press.reverse(),
        onTapUp: (_) => _press.reverse(),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_lit, _flash, _road, _press]),
          builder: (context, _) => Transform.scale(
            scale: 1 - _press.value * .04,
            child: CustomPaint(
              size: Size(widget.size, widget.size * .9),
              painter: _TunnelPainter(
                lit: _lit.value,
                wave: connecting,
                flash: _flash.value,
                roadPhase: _road.value,
                error: widget.status == VpnStatus.error,
                colors: tc,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TunnelPainter extends CustomPainter {
  _TunnelPainter({
    required this.lit,
    required this.wave,
    required this.flash,
    required this.roadPhase,
    required this.error,
    required this.colors,
  });

  final double lit;
  final bool wave;
  final double flash;
  final double roadPhase;
  final bool error;
  final TunnelyColors colors;

  static const _rings = 6;
  static const _onOuter = Brand.blue;
  static const _onInner = Color(0xFF0A0E57);

  /// Path of an arch (semicircle on top of a rectangle) in the 200x180 box.
  Path _arch(double r, {double cx = 100, double cy = 100, double bottom = 178}) => Path()
    ..moveTo(cx - r, bottom)
    ..lineTo(cx - r, cy)
    ..arcToPoint(Offset(cx + r, cy), radius: Radius.circular(r))
    ..lineTo(cx + r, bottom)
    ..close();

  /// Brightness of ring [i] (0 = outer) for the current [lit] value.
  double _ringLit(int i) {
    if (wave) {
      // A band of light travelling inward and fading behind.
      final pos = lit * (_rings + 1);
      final d = pos - i;
      if (d < 0) return 0;
      return math.max(0, 1 - d / 2.5);
    }
    return (lit * (_rings + 1) - i).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 180);
    final outer = _arch(92);

    // Halo behind the tunnel when lit.
    final halo = (lit * .5 + flash * .5).clamp(0.0, 1.0);
    if (halo > 0) {
      canvas.drawPath(
        outer,
        Paint()
          ..color = Brand.cyan.withValues(alpha: .35 * halo)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    canvas.save();
    canvas.clipPath(outer);
    for (var i = 0; i < _rings; i++) {
      final r = 92.0 - i * 13;
      final t = i / (_rings - 1);
      final off = Color.lerp(colors.archOffOuter, colors.archOffInner, t)!;
      final on = Color.lerp(_onOuter, _onInner, t)!;
      canvas.drawPath(_arch(r), Paint()..color = Color.lerp(off, on, _ringLit(i))!);
    }

    final portalLit = wave ? _ringLit(_rings) : lit;
    final glow = (portalLit + flash * .8).clamp(0.0, 1.6);
    if (glow > 0) {
      canvas.drawCircle(
        const Offset(100, 112),
        34 + 30 * flash,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFBFF0FF).withValues(alpha: (.95 * glow).clamp(0, 1)),
              Brand.cyan.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: const Offset(100, 112), radius: 34 + 30 * flash)),
      );
    }

    // Road and lane markings drifting toward the portal.
    final roadColor = Color.lerp(colors.roadOff, Colors.white.withValues(alpha: .18), lit)!;
    canvas.drawPath(
      Path()
        ..moveTo(92, 124)
        ..lineTo(108, 124)
        ..lineTo(150, 180)
        ..lineTo(50, 180)
        ..close(),
      Paint()..color = roadColor,
    );
    final dash = Paint()
      ..color = Color.lerp(colors.muted.withValues(alpha: .35), Colors.white.withValues(alpha: .9), lit)!
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 4; k++) {
      // Perspective: segments shrink as they approach the portal at y=126.
      final u = ((k + 1 - roadPhase) / 4).clamp(0.0, 1.0); // 0 at portal, 1 at bottom
      final y0 = 126 + 54 * u * u;
      final len = 3 + 9 * u;
      if (y0 + len > 178) continue;
      canvas.drawLine(Offset(100, y0), Offset(100, y0 + len), dash);
    }

    canvas.drawPath(
      Path()
        ..moveTo(90, 124)
        ..lineTo(90, 112)
        ..arcToPoint(const Offset(110, 112), radius: const Radius.circular(10))
        ..lineTo(110, 124)
        ..close(),
      Paint()..color = Color.lerp(colors.portalOff, Colors.white, portalLit.clamp(0, 1))!,
    );
    canvas.restore();

    // Outline: sides and arch only, the bottom stays open like a tunnel mouth.
    final rim = Path()
      ..moveTo(8, 178)
      ..lineTo(8, 100)
      ..arcToPoint(const Offset(192, 100), radius: const Radius.circular(92))
      ..lineTo(192, 178);
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = error ? 2.5 : 2
        ..color = error
            ? Brand.danger
            : Color.lerp(colors.archOffEdge, Brand.cyan, _ringLit(0))!.withValues(alpha: .8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TunnelPainter o) =>
      o.lit != lit || o.flash != flash || o.roadPhase != roadPhase || o.error != error || o.wave != wave || o.colors != colors;
}
