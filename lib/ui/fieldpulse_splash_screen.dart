import 'package:flutter/material.dart';

class FieldPulseSplashScreen extends StatelessWidget {
  const FieldPulseSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF031733),
    body: _FieldPulseSplashBody(),
  );
}

class _FieldPulseSplashBody extends StatelessWidget {
  const _FieldPulseSplashBody();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF031733),
              Color(0xFF082B56),
              Color(0xFF0B3768),
            ],
          ),
        ),
      ),
      const Positioned(
        top: -110,
        right: -80,
        child: _GlowCircle(size: 280, color: Color(0x3327B8FF)),
      ),
      const Positioned(
        bottom: -150,
        left: -120,
        child: _GlowCircle(size: 360, color: Color(0x2234D399)),
      ),
      const Positioned(
        bottom: 90,
        right: -45,
        child: _GlowCircle(size: 160, color: Color(0x1F60A5FA)),
      ),
      SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 118,
                  height: 118,
                  child: CustomPaint(painter: _FieldPulseMarkPainter()),
                ),
                SizedBox(height: 30),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Field',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Pulse',
                          style: TextStyle(color: Color(0xFF55B8FF)),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 48,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'by BusinessOS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFD7E6F7),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.2,
                  ),
                ),
                SizedBox(height: 22),
                SizedBox(
                  width: 84,
                  child: Divider(
                    color: Color(0x6655B8FF),
                    thickness: 2,
                    height: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _FieldPulseMarkPainter extends CustomPainter {
  const _FieldPulseMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 118;
    final stroke = 15 * scale;

    final path = Path()
      ..moveTo(29 * scale, 28 * scale)
      ..lineTo(29 * scale, 62 * scale)
      ..cubicTo(
        29 * scale,
        86 * scale,
        58 * scale,
        89 * scale,
        58 * scale,
        66 * scale,
      )
      ..lineTo(58 * scale, 52 * scale)
      ..cubicTo(
        58 * scale,
        33 * scale,
        86 * scale,
        31 * scale,
        86 * scale,
        52 * scale,
      )
      ..lineTo(86 * scale, 82 * scale);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF2F7DFF),
          Color(0xFF2FC6E8),
          Color(0xFF38D39F),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawPath(path, paint);

    final nodePaint = Paint()..color = Colors.white;
    final haloPaint = Paint()..color = const Color(0xFF6CC7FF);

    canvas.drawCircle(Offset(29 * scale, 28 * scale), 12 * scale, haloPaint);
    canvas.drawCircle(Offset(29 * scale, 28 * scale), 5 * scale, nodePaint);

    canvas.drawCircle(Offset(86 * scale, 82 * scale), 12 * scale, haloPaint);
    canvas.drawCircle(Offset(86 * scale, 82 * scale), 5 * scale, nodePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
