import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Bundled stroke vectors: no icon-font lookup or network loading.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 24;
    return ExcludeSemantics(
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox.square(
          dimension: dimension,
          child: CustomPaint(
            painter: _StrokeIcon(icon, color ?? theme.color ?? Colors.white),
          ),
        ),
      ),
    );
  }
}

class _StrokeIcon extends CustomPainter {
  const _StrokeIcon(this.icon, this.color);
  final IconData icon;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void path(List<Offset> points, {bool close = false}) {
      final shape = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        shape.lineTo(point.dx, point.dy);
      }
      if (close) shape.close();
      canvas.drawPath(shape, p);
    }

    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), p);
    void box(double x, double y, double w, double h, [double radius = 2]) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(radius),
          ),
          p,
        );
    void circle(double x, double y, double r) =>
        canvas.drawCircle(Offset(x, y), r, p);
    switch (icon) {
      case Icons.settings_outlined:
        circle(12, 12, 3);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          line(
            12 + 7 * math.cos(angle),
            12 + 7 * math.sin(angle),
            12 + 9 * math.cos(angle),
            12 + 9 * math.sin(angle),
          );
        }
        circle(12, 12, 7);

      case Icons.brightness_6_outlined:
        circle(12, 12, 8);
        canvas.save();
        canvas.clipRect(const Rect.fromLTWH(4, 4, 8, 16));
        canvas.drawCircle(
          const Offset(12, 12),
          8,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
        canvas.restore();

      case Icons.light_mode_outlined:
        circle(12, 12, 4);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          line(
            12 + 7 * math.cos(angle),
            12 + 7 * math.sin(angle),
            12 + 10 * math.cos(angle),
            12 + 10 * math.sin(angle),
          );
        }
      case Icons.dark_mode_outlined:
        canvas.drawPath(
          Path()
            ..moveTo(17, 3)
            ..cubicTo(6, 0, 0, 13, 8, 20)
            ..cubicTo(14, 25, 23, 19, 21, 12)
            ..cubicTo(13, 17, 8, 8, 17, 3)
            ..close(),
          p,
        );

      case Icons.notifications_none_rounded:
        canvas.drawPath(
          Path()
            ..moveTo(6, 16)
            ..lineTo(6, 10)
            ..cubicTo(6, 2, 18, 2, 18, 10)
            ..lineTo(18, 16)
            ..lineTo(21, 18)
            ..lineTo(3, 18)
            ..close(),
          p,
        );
        canvas.drawArc(const Rect.fromLTWH(9, 18, 6, 4), 0, math.pi, false, p);
      case Icons.more_vert_rounded:
        for (final y in [5.0, 12.0, 19.0]) {
          canvas.drawCircle(Offset(12, y), 1.6, Paint()..color = color);
        }
      case Icons.circle:
        canvas.drawCircle(const Offset(12, 12), 9, Paint()..color = color);
      case Icons.close_rounded:
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
      case Icons.add_rounded:
        line(12, 5, 12, 19);
        line(5, 12, 19, 12);
      case Icons.chevron_right_rounded:
        path([const Offset(9, 5), const Offset(16, 12), const Offset(9, 19)]);
      case Icons.expand_more_rounded:
        path([const Offset(5, 9), const Offset(12, 16), const Offset(19, 9)]);
      case Icons.arrow_forward_rounded:
        line(4, 12, 20, 12);
        path([const Offset(13, 5), const Offset(20, 12), const Offset(13, 19)]);
      case Icons.arrow_back_rounded:
        line(4, 12, 20, 12);
        path([const Offset(11, 5), const Offset(4, 12), const Offset(11, 19)]);
      case Icons.arrow_outward_rounded:
        line(6, 18, 18, 6);
        path([const Offset(6, 6), const Offset(18, 6), const Offset(18, 18)]);
      case Icons.arrow_upward_rounded:
        line(12, 4, 12, 20);
        path([const Offset(5, 11), const Offset(12, 4), const Offset(19, 11)]);
      case Icons.download_rounded:
        path([const Offset(8, 10), const Offset(12, 14), const Offset(16, 10)]);
        line(12, 3, 12, 14);
        path([
          const Offset(4, 15),
          const Offset(4, 20),
          const Offset(20, 20),
          const Offset(20, 15),
        ]);
      case Icons.copy_rounded:
        box(8, 8, 12, 13);
        path([const Offset(15, 4), const Offset(4, 4), const Offset(4, 16)]);
      case Icons.content_paste_rounded:
        box(5, 5, 14, 16);
        box(9, 3, 6, 4, 1);
        line(9, 11, 15, 11);
        line(9, 15, 13, 15);
      case Icons.folder_outlined:
      case Icons.folder_rounded:
      case Icons.folder_open_rounded:
        path([
          const Offset(3, 7),
          const Offset(3, 20),
          const Offset(21, 20),
          const Offset(21, 7),
          const Offset(12, 7),
          const Offset(10, 4),
          const Offset(3, 4),
          const Offset(3, 7),
        ], close: true);
        if (icon == Icons.folder_open_rounded) line(6, 11, 18, 11);
      case Icons.insert_drive_file_outlined:
        path([
          const Offset(5, 3),
          const Offset(14, 3),
          const Offset(19, 8),
          const Offset(19, 21),
          const Offset(5, 21),
        ], close: true);
        path([const Offset(13, 3), const Offset(13, 9), const Offset(19, 9)]);
        line(9, 13, 15, 13);
        line(9, 17, 15, 17);
      case Icons.chat_bubble_outline_rounded:
        path([
          const Offset(4, 4),
          const Offset(20, 4),
          const Offset(20, 17),
          const Offset(9, 17),
          const Offset(4, 21),
        ], close: true);
        line(8, 9, 16, 9);
        line(8, 13, 13, 13);
      case Icons.password_rounded:
        circle(6, 10, 1);
        circle(12, 10, 1);
        circle(18, 10, 1);
        line(4, 17, 20, 17);
      case Icons.laptop_rounded:
      case Icons.computer_rounded:
        box(4, 4, 16, 13, 1);
        path([
          const Offset(4, 17),
          const Offset(2, 20),
          const Offset(22, 20),
          const Offset(20, 17),
        ], close: true);
      case Icons.devices_outlined:
      case Icons.devices_rounded:
        path([
          const Offset(13, 17),
          const Offset(3, 17),
          const Offset(3, 4),
          const Offset(21, 4),
          const Offset(21, 8),
        ]);
        line(2, 20, 12, 20);
        box(15, 10, 7, 12, 1);
        line(18, 19, 19, 19);
      case Icons.link_rounded:
      case Icons.add_link_rounded:
      case Icons.link_off_rounded:
        final a = Path()
          ..moveTo(10, 7)
          ..lineTo(7, 7)
          ..cubicTo(0, 7, 0, 17, 7, 17)
          ..lineTo(10, 17);
        final b = Path()
          ..moveTo(14, 7)
          ..lineTo(17, 7)
          ..cubicTo(24, 7, 24, 17, 17, 17)
          ..lineTo(14, 17);
        canvas.drawPath(a, p);
        canvas.drawPath(b, p);
        line(8, 12, 16, 12);
        if (icon == Icons.link_off_rounded) line(3, 3, 21, 21);
        if (icon == Icons.add_link_rounded) {
          line(19, 18, 19, 23);
          line(16.5, 20.5, 21.5, 20.5);
        }
      case Icons.search_rounded:
      case Icons.search_off_rounded:
        circle(10, 10, 6);
        line(14.5, 14.5, 21, 21);
        if (icon == Icons.search_off_rounded) line(3, 3, 21, 21);
      case Icons.wifi_rounded:
      case Icons.wifi_off_rounded:
        for (final radius in [5.0, 10.0, 15.0]) {
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(12, 21), radius: radius),
            -math.pi * .75,
            math.pi * .5,
            false,
            p,
          );
        }
        circle(12, 20, 0.6);
        if (icon == Icons.wifi_off_rounded) line(3, 3, 21, 21);
      case Icons.refresh_rounded:
      case Icons.sync_rounded:
        canvas.drawArc(
          const Rect.fromLTWH(4, 4, 16, 16),
          .4,
          math.pi * 1.65,
          false,
          p,
        );
        path([const Offset(20, 3), const Offset(20, 9), const Offset(14, 9)]);
      case Icons.info_outline_rounded:
      case Icons.error_outline_rounded:
        circle(12, 12, 9);
        line(12, 10, 12, 16);
        circle(12, 7, .4);
      case Icons.tune_rounded:
        line(3, 6, 8, 6);
        line(12, 6, 21, 6);
        circle(10, 6, 2);
        line(3, 12, 14, 12);
        line(18, 12, 21, 12);
        circle(16, 12, 2);
        line(3, 18, 6, 18);
        line(10, 18, 21, 18);
        circle(8, 18, 2);
      case Icons.qr_code_scanner_rounded:
        path([const Offset(3, 8), const Offset(3, 3), const Offset(8, 3)]);
        path([const Offset(16, 3), const Offset(21, 3), const Offset(21, 8)]);
        path([const Offset(3, 16), const Offset(3, 21), const Offset(8, 21)]);
        path([
          const Offset(16, 21),
          const Offset(21, 21),
          const Offset(21, 16),
        ]);
        box(7, 7, 3, 3, 0);
        box(14, 7, 3, 3, 0);
        box(7, 14, 3, 3, 0);
        line(14, 14, 17, 14);
        line(17, 14, 17, 17);
      case Icons.no_photography_outlined:
        box(3, 6, 18, 14);
        circle(12, 13, 4);
        line(3, 3, 21, 21);
      case Icons.usb_rounded:
        line(12, 3, 12, 20);
        path([const Offset(9, 6), const Offset(12, 3), const Offset(15, 6)]);
        circle(12, 21, 1);
        path([const Offset(12, 16), const Offset(6, 12), const Offset(6, 8)]);
        circle(6, 7, 1);
        path([const Offset(12, 13), const Offset(18, 9), const Offset(18, 7)]);
        box(17, 5, 2, 2, 0);
      case Icons.flash_on_rounded:
      case Icons.flash_off_rounded:
        path([
          const Offset(13, 2),
          const Offset(5, 13),
          const Offset(11, 13),
          const Offset(10, 22),
          const Offset(19, 10),
          const Offset(13, 10),
        ], close: true);
        if (icon == Icons.flash_off_rounded) line(3, 3, 21, 21);
      default:
        box(4, 4, 16, 16);
        line(8, 12, 16, 12);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokeIcon old) => old.icon != icon || old.color != color;
}
