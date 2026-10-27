import 'package:flutter/material.dart';

import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_view.dart';
import '../widgets/mocks.dart';
import 'preview_screen.dart';

class ThemeBuilderScreen extends StatefulWidget {
  const ThemeBuilderScreen({super.key});

  @override
  State<ThemeBuilderScreen> createState() => _ThemeBuilderScreenState();
}

class _ThemeBuilderScreenState extends State<ThemeBuilderScreen> {
  late final TextEditingController _name = TextEditingController(text: studio.themeName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final s = studio;
        final pal = s.palette;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                AppNav(
                  title: 'Theme Builder',
                  back: 'Motion',
                  trailing: NavAction(
                    'Preview',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const PreviewScreen())),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('THEME NAME', style: AppText.mono),
                          TextField(
                            controller: _name,
                            maxLength: 28,
                            onChanged: s.setThemeName,
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                            decoration: const InputDecoration(
                              isDense: true,
                              counterText: '',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                                color: AppColors.live, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(s.media.isVideo ? 'LIVE ${fmtTime(s.span)}' : 'STILL',
                              style: AppText.mono),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PairedPreview(state: s),
                const SizedBox(height: 8),
                Center(child: Text('PAIRED', style: AppText.mono.copyWith(letterSpacing: 1.4))),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    s.media.isVideo
                        ? 'HOME STILL · KEY FRAME ${fmtTime(s.key)}'
                        : 'HOME STILL · YOUR PHOTO',
                    style: AppText.mono,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('SAMPLED FROM LOCK', style: AppText.mono),
                    const Text('Updates both screens',
                        style: TextStyle(fontSize: 11, color: AppColors.pri)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < pal.length; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => s.setTintIdx(i),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  color: pal[i],
                                  borderRadius: BorderRadius.circular(7),
                                  border: s.tintIdx == i
                                      ? Border.all(color: AppColors.ink, width: 2)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                pal[i].value.toRadixString(16).substring(2).toUpperCase(),
                                style: AppText.mono.copyWith(fontSize: 8.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _Slider('Blur', s.blur, 60, '${s.blur.round()}', s.setBlur),
                _Slider('Dim', s.dim, 80, '${s.dim.round()}%', s.setDim),
                _Slider('Tint', s.tint, 100, '${s.tint.round()}%', s.setTint),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tone applies to Home · Lock stays live', style: AppText.small.copyWith(fontSize: 11)),
                    GestureDetector(
                      onTap: () => s.resetTheme(),
                      child: const Text('Reset',
                          style: TextStyle(
                              color: AppColors.pri, fontWeight: FontWeight.w600, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _Slider extends StatelessWidget {
  const _Slider(this.label, this.value, this.max, this.out, this.onChanged);

  final String label;
  final double value;
  final double max;
  final String out;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.line,
              inactiveTrackColor: AppColors.line,
              thumbColor: const Color(0xFF14111F),
              overlayColor: AppColors.pri.withOpacity(0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(out, textAlign: TextAlign.right, style: AppText.mono.copyWith(fontSize: 11)),
        ),
      ],
    );
  }
}

class _PairedPreview extends StatelessWidget {
  const _PairedPreview({required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    Widget mini({required Widget child, required double h, required Widget tag, Alignment tagAlign = Alignment.bottomLeft}) {
      return Container(
        width: 142,
        height: h,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFF14111F),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x80140A32), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -10)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: child),
              Align(alignment: tagAlign, child: Padding(padding: const EdgeInsets.all(6), child: tag)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 266,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 14,
            child: Center(
              child: Transform.translate(
                offset: const Offset(60, 0),
                child: mini(
                  h: 250,
                  child: HomeScreenMock(background: StillBackdrop(state: state), state: state),
                  tag: const Pill('HOME · STILL'),
                  tagAlign: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Center(
              child: Transform.translate(
                offset: const Offset(-48, 0),
                child: mini(
                  h: 262,
                  child: LockScreenMock(background: StillBackdrop(state: state), tag: null),
                  tag: Pill(state.media.isVideo ? 'LIVE · LOCK' : 'STILL · LOCK',
                      live: state.media.isVideo),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
