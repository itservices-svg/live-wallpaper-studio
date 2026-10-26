import 'package:flutter/material.dart';

import '../theme.dart';

String fmtTime(double t) {
  final cs = (t * 100).round();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(cs ~/ 6000)}:${p((cs ~/ 100) % 60)}.${p(cs % 100)}';
}

/// "00:03.12" -> "03.12"
String fmtSec(double t) => fmtTime(t).substring(3);

/// Pink corner marks around a child (the "crop" motif from the design).
class CropMarks extends StatelessWidget {
  const CropMarks({
    super.key,
    required this.child,
    this.color = AppColors.live,
    this.inset = 3,
  });

  final Widget child;
  final Color color;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _CropPainter(color, inset)),
          ),
        ),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.color, this.inset);

  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final r = Rect.fromLTWH(-inset, -inset, s.width + inset * 2, s.height + inset * 2);
    const l = 13.0;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o.translate(dx * l, 0), p);
      canvas.drawLine(o, o.translate(0, dy * l), p);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomLeft, 1, -1);
    corner(r.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.color != color || old.inset != inset;
}

/// Small LIVE / STILL label.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.live = false});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppText.mono.copyWith(
              fontSize: 9,
              color: live ? AppColors.live : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control. [square] is the outlined variant used for loop style.
class Seg extends StatelessWidget {
  const Seg({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.square = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(square ? 0 : 3),
      decoration: BoxDecoration(
        color: square ? Colors.transparent : AppColors.dim,
        border: square ? Border.all(color: AppColors.line) : null,
        borderRadius: BorderRadius.circular(square ? 8 : 10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(square ? 7 : 8),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: EdgeInsets.symmetric(vertical: square ? 10 : 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (i == index || square) ? Colors.white : Colors.transparent,
                      borderRadius: square ? null : BorderRadius.circular(8),
                      border: square && i == index
                          ? Border.all(color: AppColors.ink, width: 2)
                          : null,
                      boxShadow: !square && i == index
                          ? const [
                              BoxShadow(
                                color: Color(0x2E28145A),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.sub,
    this.wide = false,
  });

  final String label;
  final String? sub;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pri,
      borderRadius: BorderRadius.circular(wide ? 16 : 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(wide ? 16 : 14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 0 : 20, vertical: wide ? 15 : 12),
          child: Row(
            mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: wide ? 15 : 14,
                ),
              ),
              if (sub != null) ...[
                const SizedBox(width: 6),
                Text(sub!, style: AppText.mono.copyWith(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar: optional back label on the left, title centred, action on the right.
class AppNav extends StatelessWidget {
  const AppNav({
    super.key,
    required this.title,
    this.back,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? back;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: back == null
                  ? null
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                      child: Row(
                        children: [
                          const Icon(Icons.chevron_left, color: AppColors.pri, size: 26),
                          Text(
                            back!,
                            style: const TextStyle(
                              color: AppColors.pri,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            SizedBox(
              width: 84,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ),
      ),
    );
  }
}

class NavAction extends StatelessWidget {
  const NavAction(this.label, {super.key, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: filled
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
            : const EdgeInsets.symmetric(vertical: 6),
        decoration: filled
            ? BoxDecoration(color: AppColors.pri, borderRadius: BorderRadius.circular(20))
            : null,
        child: Text(
          label,
          style: TextStyle(
            color: filled ? Colors.white : AppColors.pri,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// Floating Studio / Guide pill.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final on = i == index;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: on
                ? const [BoxShadow(color: Color(0x2E28145A), blurRadius: 8, offset: Offset(0, 2))]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: on ? AppColors.live : AppColors.sub),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.ink : AppColors.sub,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(color: Color(0x5928145A), blurRadius: 30, offset: Offset(0, 10), spreadRadius: -10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(0, Icons.home_outlined, 'Studio'),
          item(1, Icons.school_outlined, 'Guide'),
        ],
      ),
    );
  }
}
