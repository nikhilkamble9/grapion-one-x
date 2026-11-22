// //Added By Nikhil 18Nov26 22:31 For Visible Dynamic 3D Gyroscope Orbit
//Modified By Nikhil 21Nov26 20:43 For splash matching ui_prototype_docspot. Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\launch_screen_2043_SplashMatch\launch_screen_original.dart START
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
//Removed By Nikhil 21Nov26 21:16 For bundled fonts (google_fonts 9 targets material_ui): import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../auth/login_screen.dart';

// Prototype colours (ui_prototype_docspot.html, STARTUP ANIMATION block).
const _sky = Color(0xFF38BDF8);
const _emerald = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _slate400 = Color(0xFF94A3B8);
const _slate500 = Color(0xFF64748B);

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> with TickerProviderStateMixin {
  late final AnimationController _ringOuter =
      AnimationController(vsync: this, duration: AppMotion.ringOuter);
  late final AnimationController _ringMiddle =
      AnimationController(vsync: this, duration: AppMotion.ringMiddle);
  late final AnimationController _ringInner =
      AnimationController(vsync: this, duration: AppMotion.ringInner);
  late final AnimationController _flare =
      AnimationController(vsync: this, duration: AppMotion.flare);
  late final AnimationController _float =
      AnimationController(vsync: this, duration: AppMotion.floatHalf);
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: AppMotion.satellitePulseHalf);
  late final AnimationController _grid =
      AnimationController(vsync: this, duration: AppMotion.gridFly);
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: AppMotion.splashTimeline);
  late final AnimationController _exit =
      AnimationController(vsync: this, duration: AppMotion.splashExit);

  late final List<AnimationController> _loops = [_ringOuter, _ringMiddle, _ringInner, _flare, _grid];
  late final List<AnimationController> _pingPongs = [_float, _pulse];

  //Added By Nikhil 21Nov26 21:16 For true 3D gyroscope START
  late final Animation<double> _floatCurve = CurvedAnimation(parent: _float, curve: Curves.easeInOut);

  // The three .gyro-ring elements, with the exact CSS sizes, borders, tilts and timings.
  late final List<_RingSpec> _rings = [
    _RingSpec(
      animation: _ringOuter,
      diameter: 160,
      strokeWidth: 1.5,
      color: _sky.withValues(alpha: 0.6),
      style: _RingStyle.dashed,
      tiltX: 65,
      tiltY: 15,
      angleOf: (t) => t * 2 * math.pi,
      glow: _sky.withValues(alpha: 0.2),
    ),
    _RingSpec(
      animation: _ringMiddle,
      diameter: 135,
      strokeWidth: 2,
      color: _emerald,
      style: _RingStyle.arcs,
      tiltX: 30,
      tiltY: 70,
      angleOf: (t) => -AppMotion.ringMiddleCurve.transform(t) * 2 * math.pi,
    ),
    _RingSpec(
      animation: _ringInner,
      diameter: 110,
      strokeWidth: 1,
      color: _amber.withValues(alpha: 0.7),
      style: _RingStyle.dotted,
      tiltX: -45,
      tiltY: -45,
      angleOf: (t) => (1 - t) * 2 * math.pi, // animation-direction: reverse
    ),
  ];
  //Added By Nikhil 21Nov26 21:16 For true 3D gyroscope END

  bool _exiting = false;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    // Same as the prototype: the timeline fills for 4.2s, then the splash closes by itself.
    _progress.forward().whenComplete(_close);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "remove animations" setting: decorative loops stop, the timeline still runs.
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      for (final c in [..._loops, ..._pingPongs]) {
        c.stop();
      }
    } else {
      for (final c in _loops) {
        c.repeat();
      }
      for (final c in _pingPongs) {
        c.repeat(reverse: true);
      }
    }
  }

  Future<void> _close() async {
    if (_exiting || !mounted) return;
    _exiting = true;
    // Prototype: splash fades out while scaling to 1.08, then the login view is shown.
    if (_reduceMotion != true) {
      await _exit.forward();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, a1, a2) => const LoginScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [..._loops, ..._pingPongs, _progress, _exit]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    // Prototype phone: 50px top padding includes a ~44px status bar.
    final topInset = math.max(insets.top, 44.0) + 6;

    // CSS radial-gradient(circle at 50% 40%) uses "farthest-corner" as its radius.
    final farthest = math.sqrt(math.pow(size.width / 2, 2) + math.pow(size.height * 0.6, 2));
    final gradientRadius = farthest / math.max(1.0, size.shortestSide);

    final exitCurve = CurvedAnimation(parent: _exit, curve: AppMotion.smooth);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.lightBg,
        body: AnimatedBuilder(
          animation: exitCurve,
          builder: (context, child) => Opacity(
            opacity: 1 - exitCurve.value,
            child: Transform.scale(scale: 1 + 0.08 * exitCurve.value, child: child),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: gradientRadius,
                colors: const [Color(0xFF0D1629), Color(0xFF040711)],
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(child: RepaintBoundary(child: _CyberGrid(animation: _grid))),

                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, topInset, 24, insets.bottom + 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            const SizedBox(height: 60),
                            RepaintBoundary(child: _buildKineticStage()),
                            const SizedBox(height: 26),
                            _buildBrandTitle(),
                            const SizedBox(height: 6),
                            Text(
                              'MULTI-VERTICAL ENTERPRISE SUITE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.5,
                                color: _sky,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _buildProgress(),
                          ],
                        ),
                        _buildCredits(),
                      ],
                    ),
                  ),
                ),

                Positioned(top: topInset, right: 20, child: _buildSkipButton()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 170x170 stage: three gyroscope rings, the laser flare, and the floating core crystal.
  Widget _buildKineticStage() {
    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        //Modified By Nikhil 21Nov26 21:16 For true 3D gyroscope (rings pass in front of and behind the crystal). Old: three flat _GyroRing widgets drawn behind the crystal START
        children: [
          Positioned.fill(child: CustomPaint(painter: _GyroLayerPainter(rings: _rings, float: _floatCurve, front: false))),
          _LaserFlare(animation: _flare),
          _buildCoreCrystal(),
          Positioned.fill(child: CustomPaint(painter: _GyroLayerPainter(rings: _rings, float: _floatCurve, front: true))),
        ],
        //Modified By Nikhil 21Nov26 21:16 For true 3D gyroscope END
      ),
    );
  }

  Widget _buildCoreCrystal() {
    final float = CurvedAnimation(parent: _float, curve: Curves.easeInOut);
    final pulse = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);

    return AnimatedBuilder(
      animation: float,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, -6 * float.value), child: child),
      child: SizedBox(
        width: 86,
        height: 86,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4), // "circle at 35% 30%"
                    radius: 0.9,
                    colors: [Color(0xFF1E293B), Color(0xFF030712)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _amber.withValues(alpha: 0.8), width: 2),
                  boxShadow: [BoxShadow(color: _emerald.withValues(alpha: 0.4), blurRadius: 40)],
                ),
              ),
            ),
            // inset 0 0 15px rgba(255,255,255,0.2)
            const Positioned.fill(child: CustomPaint(painter: _InsetGlowPainter(radius: 24))),
            Center(child: _buildEmblemG()),
            Positioned(
              right: -6,
              bottom: -6,
              child: AnimatedBuilder(
                animation: pulse,
                builder: (context, child) {
                  final p = pulse.value;
                  return Transform.scale(
                    scale: 1 + 0.15 * p,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_emerald, Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFF030712), width: 2),
                        boxShadow: [
                          BoxShadow(color: _emerald, blurRadius: ui.lerpDouble(15, 25, p)!),
                          BoxShadow(color: _sky.withValues(alpha: 0.9 * p), blurRadius: 45),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  'X',
                  style: TextStyle(fontFamily: 'Orbitron', 
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Gold gradient "G" (background-clip: text) with a 14px amber drop-shadow glow behind it.
  Widget _buildEmblemG() {
    final style = TextStyle(fontFamily: 'Orbitron', fontSize: 42, fontWeight: FontWeight.w900, height: 1);
    return Stack(
      alignment: Alignment.center,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Text('G', style: style.copyWith(color: _amber.withValues(alpha: 0.8))),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDE68A), _amber, Color(0xFFB45309)],
            stops: [0, 0.7, 1],
          ).createShader(rect),
          child: Text('G', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildBrandTitle() {
    final base = TextStyle(fontFamily: 'Orbitron', 
      fontSize: 28,
      fontWeight: FontWeight.w900,
      letterSpacing: 4,
      color: Colors.white,
      shadows: [Shadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 20)],
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: const [
          TextSpan(text: 'G.ONE.'),
          TextSpan(
            text: 'X',
            style: TextStyle(color: _emerald, shadows: [Shadow(color: _emerald, blurRadius: 20)]),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildProgress() {
    final fill = CurvedAnimation(parent: _progress, curve: AppMotion.splashProgressCurve);
    return Column(
      children: [
        Container(
          width: 150,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: fill,
            builder: (context, child) => FractionallySizedBox(
              widthFactor: fill.value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: child,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_emerald, _sky, _amber]),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Opening Workspace...',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: _slate500,
          ),
        ),
      ],
    );
  }

  Widget _buildCredits() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Designed by Grapion Digital • Powered by SENJA MATRIX',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _slate400),
          ),
          const SizedBox(height: 4),
          Text(
            'IN PARTNERSHIP WITH SENJA MATRIX',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: _sky,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipButton() {
    return Semantics(
      button: true,
      label: 'Skip intro',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
            child: InkWell(
              onTap: _close,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  'Skip →',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

//Modified By Nikhil 21Nov26 21:16 For true 3D gyroscope. Old: _GyroRing + _RingPainter (flat rings, backup launch_screen_2116_Gyro3D) START
enum _RingStyle { dashed, dotted, arcs }

/// One .gyro-ring: size, border style, CSS tilt and spin.
class _RingSpec {
  const _RingSpec({
    required this.animation,
    required this.diameter,
    required this.strokeWidth,
    required this.color,
    required this.style,
    required this.tiltX,
    required this.tiltY,
    required this.angleOf,
    this.glow,
  });

  final Animation<double> animation;
  final double diameter;
  final double strokeWidth;
  final Color color;
  final _RingStyle style;
  final double tiltX; // degrees, CSS rotateX
  final double tiltY; // degrees, CSS rotateY
  final double Function(double t) angleOf; // CSS rotateZ in radians for animation value t
  final Color? glow; // box-shadow glow (gyro-1)
}

/// Paints the rings of the 3D stage, split by depth.
///
/// The prototype uses `transform-style: preserve-3d`, so the browser depth-sorts every ring pixel
/// against the core crystal (which floats at translateZ(30→45px)). Parts of a ring that come
/// towards the viewer pass IN FRONT of the crystal; the rest go BEHIND it. Flutter has no
/// depth sorting, so we do it ourselves: each ring point goes through the same CSS matrix
/// rotateX · rotateY · rotateZ (y down, z towards the viewer), and this painter runs twice —
/// once behind the crystal (front: false) and once on top of it (front: true).
class _GyroLayerPainter extends CustomPainter {
  _GyroLayerPainter({required this.rings, required this.float, required this.front})
      : super(repaint: Listenable.merge([float, ...rings.map((r) => r.animation)]));

  final List<_RingSpec> rings;
  final Animation<double> float;
  final bool front;

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final crystalZ = 30 + 15 * float.value; // crystalFloat: translateZ(30px) → translateZ(45px)

    for (final ring in rings) {
      final r = ring.diameter / 2 - ring.strokeWidth / 2; // CSS border sits inside the box
      final ca = math.cos(_rad(ring.tiltX)), sa = math.sin(_rad(ring.tiltX));
      final cb = math.cos(_rad(ring.tiltY)), sb = math.sin(_rad(ring.tiltY));
      final g = ring.angleOf(ring.animation.value);
      final cg = math.cos(g), sg = math.sin(g);

      // Point on the ring at angle th → (screen offset, depth z). Orthographic, like the prototype
      // (the stage itself has no perspective, only the background grid does).
      (Offset, double) project(double th) {
        final x0 = r * math.cos(th), y0 = r * math.sin(th);
        final x1 = x0 * cg - y0 * sg, y1 = x0 * sg + y0 * cg; // rotateZ
        final x2 = x1 * cb, z2 = -x1 * sb; // rotateY
        final y3 = y1 * ca - z2 * sa, z3 = y1 * sa + z2 * ca; // rotateX
        return (center + Offset(x2, y3), z3);
      }

      bool mine(double z) => front ? z > crystalZ : z <= crystalZ;

      // Soft outer glow (box-shadow 0 0 20px) — behind the crystal only.
      if (ring.glow != null && !front) {
        final path = Path();
        for (var i = 0; i <= 72; i++) {
          final (p, _) = project(i / 72 * 2 * math.pi);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = ring.glow!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      final paint = Paint()
        ..color = ring.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.strokeWidth;

      switch (ring.style) {
        case _RingStyle.dashed:
          // Chrome dashed border ≈ dashes and gaps of ~3× the border width.
          final dash = ring.strokeWidth * 3, gap = ring.strokeWidth * 3;
          final count = (2 * math.pi * r / (dash + gap)).floor();
          final step = 2 * math.pi / count, sweep = dash / r;
          for (var i = 0; i < count; i++) {
            final a0 = i * step;
            final (p0, _) = project(a0);
            final (pm, zm) = project(a0 + sweep / 2);
            final (p1, _) = project(a0 + sweep);
            if (!mine(zm)) continue;
            canvas.drawPath(Path()..moveTo(p0.dx, p0.dy)..quadraticBezierTo(pm.dx, pm.dy, p1.dx, p1.dy), paint);
          }
        case _RingStyle.dotted:
          final count = (2 * math.pi * r / (ring.strokeWidth * 2)).floor();
          final pts = <Offset>[];
          for (var i = 0; i < count; i++) {
            final (p, z) = project(i / count * 2 * math.pi);
            if (mine(z)) pts.add(p);
          }
          canvas.drawPoints(
            ui.PointMode.points,
            pts,
            paint
              ..strokeWidth = ring.strokeWidth * 1.3
              ..strokeCap = StrokeCap.round,
          );
        case _RingStyle.arcs:
          // border-top + border-bottom only: two 90° arcs centred on 12 and 6 o'clock.
          for (final start in [-3 * math.pi / 4, math.pi / 4]) {
            const steps = 24;
            Path? seg;
            for (var i = 0; i <= steps; i++) {
              final (p, z) = project(start + i / steps * math.pi / 2);
              if (mine(z)) {
                if (seg == null) {
                  seg = Path()..moveTo(p.dx, p.dy);
                } else {
                  seg.lineTo(p.dx, p.dy);
                }
              } else if (seg != null) {
                canvas.drawPath(seg, paint);
                seg = null;
              }
            }
            if (seg != null) canvas.drawPath(seg, paint);
          }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GyroLayerPainter old) => old.front != front || old.rings != rings;
}
//Modified By Nikhil 21Nov26 21:16 For true 3D gyroscope END

// laser-flare: 140x2 line that sweeps 360° while growing (scaleX 0.2→1→0.2) and fading (0→0.8→0).
class _LaserFlare extends StatelessWidget {
  const _LaserFlare({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        // CSS ease-in-out applies per keyframe segment (0→50%, 50→100%).
        final firstHalf = t < 0.5;
        final p = Curves.easeInOut.transform(firstHalf ? t * 2 : (t - 0.5) * 2);
        final rotation = (firstHalf ? p * 180 : 180 + p * 180) * math.pi / 180;
        final scaleX = firstHalf ? 0.2 + 0.8 * p : 1 - 0.8 * p;
        final opacity = firstHalf ? 0.8 * p : 0.8 * (1 - p);
        return Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: rotation,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scaleX, 1, 1),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        width: 140,
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, _sky.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _InsetGlowPainter extends CustomPainter {
  const _InsetGlowPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect.deflate(2));
    canvas.drawRRect(
      rrect.deflate(2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InsetGlowPainter old) => old.radius != radius;
}

// cyber-grid: 200% plane tilted rotateX(60deg) under 1000px perspective, drifting 40px every 15s.
class _CyberGrid extends StatelessWidget {
  const _CyberGrid({required this.animation});

  final Animation<double> animation;

  static const double _cell = 40;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return ClipRect(
          child: OverflowBox(
            maxWidth: w * 2,
            maxHeight: h * 2,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 1 / 1000)
                  ..rotateX(-60 * math.pi / 180) //Modified By Nikhil 21Nov26 21:16 For floor tilting away like CSS (Flutter z points away). Old: ..rotateX(60 * math.pi / 180)
                  ..multiply(Matrix4.translationValues(0, animation.value * _cell, 0)),
                child: child,
              ),
              child: const SizedBox.expand(child: CustomPaint(painter: _GridPainter(cell: _cell))),
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.cell});

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = Paint()
      ..color = _emerald.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final vertical = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double y = 0; y <= size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontal);
    }
    for (double x = 0; x <= size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), vertical);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.cell != cell;
}
//Modified By Nikhil 21Nov26 20:43 For splash matching ui_prototype_docspot END
