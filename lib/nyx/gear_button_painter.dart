import 'dart:math';
import 'package:flutter/material.dart';

/// Рисует кнопку-шестерёнку МехаВПН: 12-зубчатое колесо с иконкой питания.
/// Цвет задаётся через [color] (тьюнт по состоянию), [rotation] крутит колесо,
/// [glow] (0..1) управляет ореолом свечения.
///
/// geometry совпадает с gear_button.svg и дизайн-спекой NYX.
class GearButtonPainter extends CustomPainter {
  GearButtonPainter({
    required this.color,
    this.rotation = 0,
    this.glow = 0,
  });

  final Color color;
  final double rotation; // радианы
  final double glow; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);
    canvas.translate(-cx, -cy);

    // 1. Ореол свечения под шестерёнкой
    if (glow > 0) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.35 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, r * 0.22 * glow);
      canvas.drawCircle(Offset(cx, cy), r * 0.82, glowPaint);
    }

    // 2. Тело шестерёнки (12 зубцов)
    final gearPath = _gearPath(cx, cy, r * 0.92, r * 0.74, teeth: 12);
    final bodyFill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF15151A);
    final bodyStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.025
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(gearPath, bodyFill);
    canvas.drawPath(gearPath, bodyStroke);

    // 3. Hub-диск с радиальным градиентом
    final hubRect = Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.47);
    final hubPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.3),
        radius: 0.7,
        colors: [Color(0xFF1C1C22), Color(0xFF0B0B0E)],
      ).createShader(hubRect);
    canvas.drawCircle(Offset(cx, cy), r * 0.47, hubPaint);
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.47,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.02
        ..color = color,
    );

    // 4. Внутреннее пунктирное кольцо
    _drawDashedCircle(
      canvas,
      Offset(cx, cy),
      r * 0.40,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withOpacity(0.35),
      dashLen: 3,
      gapLen: 4,
    );

    // 5. Иконка питания: дуга 270° (открыта сверху) + вертикальная черта
    // иконка питания не вращается вместе с шестерёнкой
    canvas.restore();
    final iconR = r * 0.30;
    final arcRect = Rect.fromCircle(center: Offset(cx, cy), radius: iconR);
    // старт 315° (верх-право), sweep 270° по часовой через низ → разрыв сверху
    canvas.drawArc(
      arcRect,
      315 * pi / 180,
      270 * pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.05
        ..color = color,
    );
    // черта от верха круга вниз до центра
    canvas.drawLine(
      Offset(cx, cy - iconR),
      Offset(cx, cy + iconR * 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.05
        ..color = color,
    );

  }

  /// Путь 12-зубчатой шестерёнки. rTip — радиус до вершины зубца,
  /// rRoot — до впадины. toothTipFrac — доля дуги на кончик зубца.
  Path _gearPath(
    double cx,
    double cy,
    double rTip,
    double rRoot, {
    int teeth = 12,
    double toothTipFrac = 0.40,
  }) {
    final seg = 2 * pi / teeth;
    final halfTip = seg * toothTipFrac / 2;
    final p = Path();
    for (int i = 0; i < teeth; i++) {
      final a0 = i * seg - halfTip;
      final a1 = i * seg + halfTip;
      final a2 = (i + 1) * seg - halfTip;
      final pts = <Offset>[
        Offset(cx + rTip * cos(a0), cy + rTip * sin(a0)),
        Offset(cx + rTip * cos(a1), cy + rTip * sin(a1)),
        Offset(cx + rRoot * cos(a1), cy + rRoot * sin(a1)),
        Offset(cx + rRoot * cos(a2), cy + rRoot * sin(a2)),
      ];
      if (i == 0) {
        p.moveTo(pts[0].dx, pts[0].dy);
      } else {
        p.lineTo(pts[0].dx, pts[0].dy);
      }
      for (int j = 1; j < 4; j++) {
        p.lineTo(pts[j].dx, pts[j].dy);
      }
    }
    p.close();
    return p;
  }

  /// Пунктирная окружность — рисуем короткими сегментами по дуге.
  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    double dashLen = 3,
    double gapLen = 4,
  }) {
    const steps = 180;
    final unit = 2 * pi * radius / steps;
    final period = dashLen + gapLen;
    double walked = 0;
    bool drawing = true;
    for (int i = 0; i < steps; i++) {
      if (drawing) {
        final a0 = (i / steps) * 2 * pi;
        final a1 = ((i + 1) / steps) * 2 * pi;
        canvas.drawLine(
          Offset(center.dx + radius * cos(a0), center.dy + radius * sin(a0)),
          Offset(center.dx + radius * cos(a1), center.dy + radius * sin(a1)),
          paint,
        );
      }
      walked += unit;
      if (walked >= period) {
        drawing = !drawing;
        walked = 0;
      } else if (drawing && walked >= dashLen) {
        drawing = false;
      } else if (!drawing && walked >= dashLen + gapLen) {
        drawing = true;
        walked = 0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant GearButtonPainter old) =>
      old.color != color ||
      old.rotation != rotation ||
      old.glow != glow;
}
