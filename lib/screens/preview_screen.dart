import 'dart:async';

import 'package:flutter/material.dart';

import '../services/exporter.dart';
import '../services/trimmer.dart';
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

class _PreviewScreenState extends State<PreviewScreen> with WidgetsBindingObserver {
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

  // Set while we wait for the user to come back from Android's wallpaper screen.
  Completer<void>? _returned;
  bool _wentAway = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wentAway = true;
    if (state == AppLifecycleState.resumed && _wentAway) {
      final c = _returned;
      if (c != null && !c.isCompleted) c.complete();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The loop plays by itself on both screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && studio.media.isVideo) _startHold();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    studio.holdEnd();
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

  Future<void> _waitReturn(Future<bool> Function() open) async {
    _wentAway = false;
    _returned = Completer<void>();
    final ok = await open();
    if (!ok) return;
    await _returned!.future.timeout(const Duration(minutes: 3), onTimeout: () {});
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  /// Opens Android's screen for our own Lock (sharp) or Home (blurred) video service.
  Future<ApplyResult> _applyLive(ExportFiles f, {required bool lock}) async {
    final video = lock ? f.lockVideo : f.homeVideo;
    if (video == null) {
      return const ApplyResult(false, 'Could not prepare the video. Try a shorter clip.');
    }
    _toast(lock
        ? 'Choose LOCK screen only, tap Set, then come back.'
        : 'Choose HOME screen only, tap Set, then come back.');
    var opened = false;
    await _waitReturn(() async => opened = await WallpaperService.openLive(lock ? 'lock' : 'home'));
    if (!opened) return const ApplyResult(false, 'Could not open the wallpaper screen.');
    return ApplyResult(true, lock ? 'Sharp live video set for Lock' : 'Blurred live video set for Home');
  }

  /// Renders the trimmed loop (sharp, with framing) as a GIF and saves it to the gallery.
  Future<void> _saveGif() async {
    if (_busy) return;
    final s = studio;
    setState(() => _busy = true);
    ApplyResult result;
    try {
      final size = MediaQuery.of(context).size;
      final mp4 = await Trimmer.render(s,
          width: 720, height: (720 * size.height / size.width).round(), prefix: 'gifsrc');
      final gif = mp4 == null ? null : await Trimmer.toGif(mp4);
      result = gif == null
          ? const ApplyResult(false, 'Could not make the GIF. Try a shorter clip.')
          : await WallpaperService.saveGif(gif, name: s.themeName);
    } catch (e) {
      result = ApplyResult(false, 'Something went wrong: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(result.message);
  }

  /// One wallpaper for both screens: Lock plays the sharp video, Home the blurred one.
  Future<ApplyResult> _applySingle(ExportFiles f) async {
    if (f.lockVideo == null || f.homeVideo == null) {
      return const ApplyResult(false, 'Could not prepare the videos. Try a shorter clip.');
    }
    _toast('Choose "Home & lock screen" and tap Set, then come back.');
    var opened = false;
    await _waitReturn(() async => opened = await WallpaperService.openLive('studio'));
    if (!opened) return const ApplyResult(false, 'Could not open the wallpaper screen.');
    return const ApplyResult(true, 'Set. Lock should play the sharp video and Home the blurred one.');
  }

  /// Lock video first (choose "Home & lock"), then Home video (choose "Home screen"),
  /// so Lock keeps the sharp video and Home gets the blurred one.
  Future<ApplyResult> _applyGuided(ExportFiles f) async {
    if (f.lockVideo == null || f.homeVideo == null) {
      return const ApplyResult(false, 'Could not prepare the videos. Try a shorter clip.');
    }
    var opened = false;
    _toast('Step 1 of 2: choose "Home & lock screen" and tap Set, then come back.');
    await _waitReturn(() async => opened = await WallpaperService.openLive('lock'));
    if (!opened) return const ApplyResult(false, 'Could not open the wallpaper screen.');
    if (!mounted) return const ApplyResult(false, '');
    _toast('Step 2 of 2: choose "Home screen" only and tap Set.');
    await _waitReturn(() async => opened = await WallpaperService.openLive('home'));
    if (!opened) return const ApplyResult(false, 'Could not open the wallpaper screen.');
    return const ApplyResult(true, 'Done: sharp video on Lock, blurred video on Home');
  }

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
      final liveKind = target == ApplyTarget.liveLock
          ? 'lock'
          : target == ApplyTarget.liveHome
              ? 'home'
              : (target == ApplyTarget.liveGuided || target == ApplyTarget.liveSingle)
                  ? 'both'
                  : null;
      final files = await Exporter.render(s, liveKind: liveKind);
      if (liveKind == 'both') {
        result = target == ApplyTarget.liveSingle
            ? await _applySingle(files)
            : await _applyGuided(files);
      } else if (liveKind != null) {
        result = await _applyLive(files, lock: liveKind == 'lock');
      } else {
        result = s.isIOS
            ? await WallpaperService.saveToPhotos(files, name: s.themeName)
            : await WallpaperService.applyAndroid(target!, files);
      }
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
    if (mounted && (target == null || target.index < ApplyTarget.live.index)) _backToRoot(tab: s.isIOS ? 1 : 0);
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
                  onChanged: (i) => s.setSide(PreviewSide.values[i]),
                ),
                const SizedBox(height: 22),
                Center(
                  child: CropMarks(
                    inset: 6,
                    child: Builder(
                      builder: (_) => PhoneBezel(
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
                                : HomeScreenMock(
                                    background: LiveBackdrop(
                                      state: s,
                                      showVideo: _holding,
                                      animate: _holding,
                                    ),
                                    state: s,
                                  ),
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
                              ? 'Your ${fmtSec(s.span)} loop plays on both screens'
                              : 'Still photo · no motion on this wallpaper')
                          : 'Blur ${s.blur.round()} · dim ${s.dim.round()}%${s.media.isVideo ? ' · video plays blurred' : ''}',
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
                if (!_busy && s.media.isVideo && s.videoPath != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saveGif,
                    icon: const Icon(Icons.gif_box_outlined, size: 20),
                    label: const Text('Save loop as GIF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.line),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
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
      ApplyTarget.liveSingle => 'Live: Lock + Home (1 step)',
      ApplyTarget.liveGuided => 'Live: Lock + Home (2 steps)',
      ApplyTarget.liveLock => 'Live Lock screen',
      ApplyTarget.liveHome => 'Live Home screen',
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
            if (canLive) option(ApplyTarget.liveSingle, 'Sharp Lock + blurred Home · pick Home & lock'),
            if (canLive) option(ApplyTarget.liveGuided, 'Same look · 2 steps, if 1 step fails'),
            if (canLive) option(ApplyTarget.liveLock, 'Sharp video · Home & lock'),
            if (canLive) option(ApplyTarget.liveHome, 'Blurred video · Home'),
            if (canLive) option(ApplyTarget.live, 'Same video on both'),
            if (studio.media.isVideo)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Live wallpapers use your trimmed loop and Android asks you to confirm. '
                  '"Live: Lock + Home" guides you through two Android screens: first choose '
                  '"Home & lock screen", then "Home screen".',
                  style: AppText.small.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
