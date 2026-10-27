import 'dart:async';

import 'package:flutter/material.dart';

import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_view.dart';
import '../widgets/scene_view.dart';
import 'studio_screen.dart';

class MotionEditorScreen extends StatefulWidget {
  const MotionEditorScreen({super.key});

  @override
  State<MotionEditorScreen> createState() => _MotionEditorScreenState();
}

class _MotionEditorScreenState extends State<MotionEditorScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => studio.tick(0.05));
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Pause after this frame; notifying listeners while the tree is locked would throw.
    WidgetsBinding.instance.addPostFrameCallback((_) => studio.setPlaying(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final s = studio;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AppNav(
                  title: 'Motion Editor',
                  back: 'Media',
                  trailing: NavAction(
                    'Next',
                    filled: true,
                    onTap: () async {
                      studio.setPlaying(false);
                      await goAfterEdit(context, fromVideo: true);
                      if (mounted) studio.setPlaying(true);
                    },
                  ),
                ),
                _PreviewCard(state: s),
                const SizedBox(height: 14),
                _TimelinePanel(state: s),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x40000000), blurRadius: 8)];
    Widget roundBtn(IconData icon, String label, VoidCallback onTap, {required bool left}) {
      return Positioned(
        left: left ? 10 : null,
        right: left ? null : 10,
        bottom: 12,
        child: Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(height: 3),
            Text(label, style: AppText.mono.copyWith(fontSize: 8, color: Colors.white)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: (MediaQuery.of(context).size.height * 0.4).clamp(240.0, 360.0).toDouble(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PinchLayer(
              state: state,
              child: LiveBackdrop(state: state, showVideo: true, animate: state.playing),
            ),
            if (state.mediaError)
              const Center(
                child: Text('Could not open this video',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 22,
              child: Column(
                children: [
                  const Text('Wednesday, May 14',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: shadow)),
                  const Text('9:41',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 54,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                          shadows: shadow)),
                  const SizedBox(height: 56),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                        state.zoom > 1
                            ? 'Zoom ${state.zoom.toStringAsFixed(1)}x · drag to move'
                            : 'Pinch to reposition',
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ],
              ),
            ),
            roundBtn(state.playing ? Icons.pause : Icons.play_arrow, 'PAUSE', state.togglePlay, left: true),
            roundBtn(Icons.replay, 'RESTART', state.restart, left: false),
            const Positioned(left: 56, bottom: 14, child: Pill('LIVE', live: true)),
            Positioned(
              right: 56,
              bottom: 16,
              child: Text(fmtTime(state.playhead),
                  style: AppText.mono.copyWith(fontSize: 10, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-finger pinch zooms, one finger moves the picture once it is zoomed.
class _PinchLayer extends StatefulWidget {
  const _PinchLayer({required this.state, required this.child});

  final StudioState state;
  final Widget child;

  @override
  State<_PinchLayer> createState() => _PinchLayerState();
}

class _PinchLayerState extends State<_PinchLayer> {
  double _baseZoom = 1;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return LayoutBuilder(builder: (context, bc) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _baseZoom = s.zoom,
        onScaleUpdate: (d) {
          final z = (_baseZoom * d.scale).clamp(1.0, 4.0).toDouble();
          final slackX = (z - 1) / 2 * bc.maxWidth;
          final slackY = (z - 1) / 2 * bc.maxHeight;
          final px = slackX <= 0 ? 0.0 : s.panX + d.focalPointDelta.dx / slackX;
          final py = slackY <= 0 ? 0.0 : s.panY + d.focalPointDelta.dy / slackY;
          s.setFraming(z, px, py);
        },
        onDoubleTap: () => s.setFraming(1, 0, 0),
        child: widget.child,
      );
    });
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    final maxed = state.span >= state.maxSpan - 0.005;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${fmtTime(state.start)} → ${fmtTime(state.end)}',
                  style: AppText.mono.copyWith(fontSize: 11, color: AppColors.ink)),
              Row(
                children: [
                  Text('${state.span.toStringAsFixed(1)}s / ${state.maxSpan.toStringAsFixed(1)}s',
                      style: AppText.mono.copyWith(fontSize: 11, color: AppColors.ink)),
                  if (maxed)
                    Container(
                      margin: const EdgeInsets.only(left: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      color: const Color(0xFFF5D6E8),
                      child: Text('MAX', style: AppText.mono.copyWith(fontSize: 9, color: AppColors.live)),
                    ),
                ],
              ),
            ],
          ),
          _Timeline(state: state),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i <= 4; i++)
                Text(_rulerLabel(state.sourceLen * i / 4),
                    style: AppText.mono.copyWith(fontSize: 9)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(width: 26, height: 36, child: StillBackdrop(state: state)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Lock Screen still',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    Text('Key frame ${fmtTime(state.key).substring(3)}', style: AppText.mono.copyWith(color: AppColors.live)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: state.setKeyAtPlayhead,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.line),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Set at playhead',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LOOP STYLE', style: AppText.mono),
              Text('0.25S CROSSFADE', style: AppText.mono),
            ],
          ),
          const SizedBox(height: 6),
          Seg(
            square: true,
            labels: const ['Play once', 'Loop', 'Bounce'],
            index: state.loop.index,
            onChanged: (i) => state.setLoop(LoopStyle.values[i]),
          ),
        ],
      ),
    );
  }
}

String _rulerLabel(double v) =>
    '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}s';

/// One filmstrip cell: a real video frame once it is extracted, else a placeholder.
class _Frame extends StatelessWidget {
  const _Frame({required this.state, required this.index});

  final StudioState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (state.media.asset == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          SceneView(scene: state.scene),
          ColoredBox(color: Colors.black.withOpacity(((index * 37) % 25) / 250)),
        ],
      );
    }
    final b = index < state.strip.length ? state.strip[index] : null;
    if (b == null) return const ColoredBox(color: Color(0xFFCFCBDD));
    return SizedBox.expand(
      child: Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        double px(double t) => t / state.sourceLen * w;
        double toSec(double dx) => dx / w * state.sourceLen;
        final dimColor = Colors.white.withOpacity(0.62);

        Widget handle({required double left, required bool isStart}) {
          return Positioned(
            left: left,
            top: -2,
            bottom: -2,
            width: 16,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => isStart
                  ? state.dragStart(toSec(d.delta.dx))
                  : state.dragEnd(toSec(d.delta.dx)),
              child: Center(
                child: Container(
                  width: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14111F),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(isStart ? 5 : 0),
                      right: Radius.circular(isStart ? 0 : 5),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Container(width: 2, height: 16, color: Colors.white),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: SizedBox(
            height: 46,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        for (var i = 0; i < 12; i++)
                          Expanded(child: _Frame(state: state, index: i)),
                      ],
                    ),
                  ),
                ),
                Positioned(left: 0, top: 0, bottom: 0, width: px(state.start), child: ColoredBox(color: dimColor)),
                Positioned(left: px(state.end), right: 0, top: 0, bottom: 0, child: ColoredBox(color: dimColor)),
                Positioned(
                  left: px(state.start),
                  width: px(state.end) - px(state.start),
                  top: -2,
                  bottom: -2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => state.moveWindow(toSec(d.delta.dx)),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF14111F), width: 2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
                handle(left: px(state.start) - 10, isStart: true),
                handle(left: px(state.end) - 6, isStart: false),
                Positioned(
                  left: px(state.playhead) - 1,
                  width: 2,
                  top: -4,
                  bottom: -4,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), spreadRadius: 1)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: px(state.key),
                  top: -30,
                  child: IgnorePointer(
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.live,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text('KEY ${fmtSec(state.key)}',
                                style: AppText.mono.copyWith(fontSize: 9, color: Colors.white)),
                          ),
                          Container(width: 2, height: 22, color: AppColors.live),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
