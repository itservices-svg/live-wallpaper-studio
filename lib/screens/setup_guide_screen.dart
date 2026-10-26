import 'package:flutter/material.dart';

import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_view.dart';

class _Step {
  const _Step(this.title, this.body, this.icon);
  final String title;
  final String body; // {n} is replaced by the theme name
  final IconData icon;
}

const _iosSteps = [
  _Step('Open Photos', 'Find {n} at the top of Recents. It is the one with the Live badge.', Icons.grid_view_rounded),
  _Step('Tap Share', 'The square with an arrow, bottom-left of the photo.', Icons.ios_share),
  _Step('Use as Wallpaper', 'Scroll the share sheet’s action list until you see it.', Icons.wallpaper),
  _Step('Keep Live Photo on', 'Make sure the Live button is lit, then tap Add and choose Set as Wallpaper Pair.', Icons.layers_outlined),
];

const _androidSteps = [
  _Step('Pick your scene', 'Choose a theme from Studio or Recents.', Icons.grid_view_rounded),
  _Step('Tap Set as wallpaper', 'The app opens the system live wallpaper preview.', Icons.wallpaper),
  _Step('Choose where', 'Lock screen, Home screen or both, then confirm.', Icons.layers_outlined),
];

class SetupGuideScreen extends StatelessWidget {
  const SetupGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final s = studio;
        final ios = s.isIOS;
        final steps = ios ? _iosSteps : _androidSteps;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            children: [
              AppNav(
                title: '',
                trailing: NavAction('Done', onTap: () => s.setTab(0)),
              ),
              Text(ios ? 'Setup Guide' : 'Set on Android', style: AppText.title),
              const SizedBox(height: 6),
              Text(
                ios
                    ? 'iOS doesn’t let apps set wallpapers directly. Four quick taps in Photos and your theme is live.'
                    : 'Android lets the app set a live wallpaper directly. Three taps and you are done.',
                style: AppText.small.copyWith(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 14),
              if (ios && s.saved) _SavedCard(state: s),
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Lock Screen', style: AppText.h2),
                    Text('LIVE · ${steps.length} STEPS', style: AppText.mono),
                  ],
                ),
              ),
              for (var i = 0; i < steps.length; i++)
                _StepRow(
                  index: i,
                  step: steps[i],
                  name: s.themeName,
                  done: s.stepDone(i),
                  onTap: () => s.toggleStep(i),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    Widget thumb({required bool blurred}) {
      return SizedBox(
        width: 34,
        height: 60,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: StillBackdrop(state: state),
              ),
            ),
            if (blurred)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: ColoredBox(color: Colors.black.withOpacity(0.3)),
                ),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 11),
              ),
            ),
          ],
        ),
      );
    }

    Widget kv(String k, String v) => Container(
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k, style: AppText.mono.copyWith(fontSize: 9)),
              Text(v, style: AppText.mono.copyWith(fontSize: 9, color: AppColors.ink)),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E6F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          thumb(blurred: false),
          const SizedBox(width: 6),
          thumb(blurred: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SAVED TO PHOTOS · TODAY', style: AppText.mono.copyWith(fontSize: 8.5)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(state.themeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                kv('LIVE PHOTO', fmtTime(state.span)),
                kv('HOME STILL', '1179×2556'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.step,
    required this.name,
    required this.done,
    required this.onTap,
  });

  final int index;
  final _Step step;
  final String name;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 38,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: done ? AppColors.live : const Color(0xFF3A3650),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(step.body.replaceAll('{n}', name),
                      style: AppText.small.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 42,
              height: 56,
              decoration: BoxDecoration(
                color: done ? const Color(0xFFF7D9EA) : const Color(0xFFDDD9EA),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                done ? Icons.check : step.icon,
                size: 20,
                color: done ? AppColors.live : const Color(0xFF7A74A0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
