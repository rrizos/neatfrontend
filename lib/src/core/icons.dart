import 'dart:math' as math;

import 'package:flutter/material.dart';

class CommentBubbleIcon extends StatelessWidget {
  const CommentBubbleIcon({super.key, required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _CommentBubblePainter(color)),
    );
  }
}

class _CommentBubblePainter extends CustomPainter {
  const _CommentBubblePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = size.width * 0.082;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final inset = sw / 2 + 1.0;

    final cx = w * 0.42;
    final cy = h * 0.42;
    final r = cx - inset;

    const startAngle = 32.0 * math.pi / 180;
    const endAngle = 62.0 * math.pi / 180;
    const sweepAngle = 2 * math.pi - (endAngle - startAngle);

    final gapEndPt = Offset(cx + r * math.cos(endAngle), cy + r * math.sin(endAngle));
    final tailTip  = Offset(w - inset, h - inset);

    final path = Path()
      ..moveTo(gapEndPt.dx, gapEndPt.dy)
      ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r), endAngle, sweepAngle, false)
      ..lineTo(tailTip.dx, tailTip.dy)
      ..lineTo(gapEndPt.dx, gapEndPt.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CommentBubblePainter old) => old.color != color;
}
