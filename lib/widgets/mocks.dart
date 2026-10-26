import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../state/studio_state.dart';
import '../theme.dart';
import 'common.dart';

/// Design size of the screen mocks. Wrap in FittedBox to show them smaller.
const double kMockW = 222;
const double kMockH = 462;

const _shadow = [Shadow(color: Color(0x47000000), blurRadius: 10)];

/// Lock screen mock over any [background] (see media_view.dart).
/// [tag] is the small pill at the top-left: 'LIVE', 'STILL', or null to hide it.
class LockScreenMock extends StatelessWidget {
  const LockScreenMock({
    super.key,
    required this.background,
    this.clockLabel,
    this.tag = 'LIVE',
  });

  final Widget background;
  final String? clockLabel;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    Widget chip(String big, String small) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(big,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
              Text(small,
                  style: const TextStyle(color: Colors.white70, fontSize: 7.5)),
            ],
          ),
        );

    return SizedBox(
      width: kMockW,
      height: kMockH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          Positioned(
            left: 0,
            right: 0,
            top: 58,
            child: Column(
              children: [
                const Text('Saturday, June 14',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: _shadow)),
                const Text('9:41',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                        shadows: _shadow)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    chip('62', 'Mon'),
                    chip('24° Sunny', 'Beach Rd'),
                    chip('7.2k', 'steps'),
                  ],
                ),
              ],
            ),
          ),
          if (tag != null)
            Positioned(left: 16, top: 40, child: Pill(tag!, live: tag == 'LIVE')),
          if (clockLabel != null)
            Positioned(
              right: 16,
              top: 42,
              child: Text(clockLabel!, style: AppText.mono.copyWith(color: Colors.white)),
            ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The paired Home still: [background] blurred, dimmed and tinted by the
/// Theme Builder values. Tint colours come from [StudioState.palette].
class HomeScreenMock extends StatelessWidget {
  const HomeScreenMock({
    super.key,
    required this.background,
    required this.state,
    this.showDock = true,
  });

  final Widget background;
  final StudioState state;
  final bool showDock;

  @override
  Widget build(BuildContext context) {
    final sigma = state.blur * 0.3;
    final icon = BoxDecoration(
      color: Colors.white.withOpacity(0.3),
      borderRadius: BorderRadius.circular(11),
    );

    return SizedBox(
      width: kMockW,
      height: kMockH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Transform.scale(scale: 1.15, child: background),
            ),
          ),
          ColoredBox(color: Colors.black.withOpacity(state.dim / 100 * 0.8)),
          ColoredBox(
            color: state.palette[state.tintIdx].withOpacity(state.tint / 100 * 0.55),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: 56,
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (var i = 0; i < 12; i++) DecoratedBox(decoration: icon)],
            ),
          ),
          if (showDock)
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              height: 56,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dark rounded phone frame with a Dynamic Island.
class PhoneBezel extends StatelessWidget {
  const PhoneBezel({
    super.key,
    required this.child,
    this.width = 236,
    this.height = 476,
    this.glow,
    this.radius = 40,
    this.border = 7,
    this.showIsland = true,
  });

  final Widget child;
  final double width;
  final double height;
  final double radius;
  final double border;
  final Color? glow;
  final bool showIsland;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(border),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0C14),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (glow != null) BoxShadow(color: glow!, blurRadius: 70, spreadRadius: 6),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - border),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: child),
            if (showIsland)
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 9),
                  width: 68,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
