import 'dart:async';

import 'package:flutter/material.dart';

import '../services/exporter.dart';
import '../services/wallpaper_service.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_view.dart';
import '../widgets/mocks.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  bool _holding = false;
  double _clock = 0;
  Timer? _timer;

  void _startHold() {
    _timer?.cancel();
    studio.holdStart();
    setState(() {
      _holding = true;
      _clock = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      studio.holdTick();
      setState(() => _clock = (_clock + 0.05) % studio.span);
    });
  }

  void _stopHold() {
    _timer?.cancel();
    studio.holdEnd();
    if (_holding) setState(() => _holding = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ));
  }

  void _backToRoot({required int tab}) {
    studio.setTab(tab);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    final s = studio;
    ApplyTarget? target;
    if (!s.isIOS) {
      target = await showModalBottomSheet<ApplyTarget>(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (_) => _TargetSheet(canLive: s.media.isVideo && s.videoPath != null),
      );
      if (target == null || !mounted) return;
    }
    setState(() => _busy = true);
    _stopHold();
    ApplyResult result;
    try {
      final files = await Exporter.render(s);
      result = s.isIOS
          ? await WallpaperService.saveToPhotos(files, name: s.themeName)
          : await WallpaperService.applyAndroid(target!, files);
    } catch (e) {
      result = ApplyResult(false, 'Something went wrong: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(result.message);
    if (!result.ok) return;
    s.markSaved();
    await s.saveCurrent();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted && target != ApplyTarget.live) _backToRoot(tab: s.isIOS ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final s = studio;
        final lock = s.side == PreviewSide.lock;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                AppNav(
                  title: 'Preview',
                  back: 'Theme',
                  trailing: GestureDetector(
                    onTap: s.toggleDimPreview,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(Icons.dark_mode_outlined, size: 18),
                    ),
                  ),
                ),
                Seg(
                  labels: const ['Lock Screen', 'Home Screen'],
                  index: s.side.index,
                  onChanged: (i) {
                    _stopHold();
                    s.setSide(PreviewSide.values[i]);
                  },
                ),
                const SizedBox(height: 22),
                Center(
                  child: CropMarks(
                    inset: 6,
                    child: GestureDetector(
                      onTapDown: lock ? (_) => _startHold() : null,
                      onTapUp: lock ? (_) => _stopHold() : null,
                      onTapCancel: lock ? _stopHold : null,
                      onLongPressEnd: lock ? (_) => _stopHold() : null,
                      child: PhoneBezel(
                        glow: s.palette[0].withOpacity(0.45),
                        child: Stack(
                          children: [
                            lock
                                ? LockScreenMock(
                                    background: LiveBackdrop(
                                      state: s,
                                      showVideo: _holding,
                                      animate: _holding,
                                    ),
                                    clockLabel: s.media.isVideo ? fmtTime(_clock) : null,
                                    tag: s.media.isVideo ? 'LIVE' : 'STILL',
                                  )
                                : HomeScreenMock(background: StillBackdrop(state: s), state: s),
                            if (s.dimPreview)
                              Positioned.fill(
                                child: ColoredBox(color: Colors.black.withOpacity(0.45)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.live, width: 2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lock
                          ? (s.media.isVideo
                              ? 'Press and hold the screen to play · ${fmtSec(s.span)} loop'
                              : 'Still photo · no motion on this wallpaper')
                          :'Home uses the blurred still · ${s.blur.round()} blur, ${s.dim.round()}% dim',
                      style: AppText.small.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_busy)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
                    ),
                  )
                else
                  PrimaryButton(
                    wide: true,
                    label: s.isIOS ? 'Save to Photos' : 'Set as wallpaper',
                    sub: s.isIOS ? '${s.exportFiles} ${s.exportFiles == 1 ? 'file' : 'files'}' : null,
                    onTap: _save,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _targetLabel(ApplyTarget t) => switch (t) {
      ApplyTarget.lock => 'Lock screen',
      ApplyTarget.home => 'Home screen',
      ApplyTarget.both => 'Lock + Home',
      ApplyTarget.live => 'Live wallpaper',
    };

class _TargetSheet extends StatelessWidget {
  const _TargetSheet({required this.canLive});

  final bool canLive;

  @override
  Widget build(BuildContext context) {
    Widget option(ApplyTarget t, String hint) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).pop(t),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line),
            padding: const EdgeInsets.all(14),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            children: [
              Text(_targetLabel(t), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.small.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set wallpaper', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(studio.themeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
            const SizedBox(height: 6),
            option(ApplyTarget.lock, studio.media.isVideo ? 'Key frame still' : 'Photo'),
            option(ApplyTarget.home, 'Blurred, dimmed, tinted'),
            option(ApplyTarget.both, 'Theme pair'),
            if (canLive) option(ApplyTarget.live, 'Moving video · home · you confirm'),
            if (studio.media.isVideo)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Android only allows live video on the home screen, and the whole clip loops. '
                  'Lock screen always gets a still.',
                  style: AppText.small.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
