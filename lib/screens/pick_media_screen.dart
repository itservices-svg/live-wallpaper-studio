import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/scenes.dart';
import '../services/media_library.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_view.dart';
import 'motion_editor_screen.dart';
import 'studio_screen.dart';

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

String _dayTitle(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';
  final year = d.year == now.year ? '' : ' ${d.year}';
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}$year';
}

String _fmtInt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _Day {
  _Day(this.title);
  final String title;
  final List<MediaItem> items = [];
}

class PickMediaScreen extends StatefulWidget {
  const PickMediaScreen({super.key});

  @override
  State<PickMediaScreen> createState() => _PickMediaScreenState();
}

class _PickMediaScreenState extends State<PickMediaScreen> {
  final _scroll = ScrollController();
  final List<_Day> _days = [];

  PermissionState? _perm;
  MediaPager? _pager;
  MediaItem? _sel;
  bool _loading = true;
  bool _samples = false;
  bool _askedOnce = false;
  int _videoCount = 0;
  int _photoCount = 0;

  bool get _hasAccess => _perm?.hasAccess ?? false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    if (_askedOnce && !_hasAccess) {
      // Asked before and still no access: the OS will not ask again.
      await PhotoManager.openSetting();
    }
    _askedOnce = true;
    final p = await MediaPager.requestAccess();
    if (!mounted) return;
    _perm = p;
    if (!p.hasAccess) {
      setState(() => _loading = false);
      return;
    }
    final pagers = await Future.wait([
      MediaPager.open(video: true),
      MediaPager.open(video: false),
    ]);
    if (!mounted) return;
    _videoCount = pagers[0]?.total ?? 0;
    _photoCount = pagers[1]?.total ?? 0;
    _pager = studio.pickVideo ? pagers[0] : pagers[1];
    await _fillFirstPage();
  }

  Future<void> _openKind() async {
    setState(() {
      _loading = true;
      _days.clear();
      _sel = null;
    });
    _pager = await MediaPager.open(video: studio.pickVideo);
    if (!mounted) return;
    await _fillFirstPage();
  }

  Future<void> _fillFirstPage() async {
    _days.clear();
    _sel = null;
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    final p = _pager;
    if (p == null) return;
    final list = await p.next();
    if (!mounted || p != _pager || list.isEmpty) return;
    setState(() {
      for (final a in list) {
        final title = _dayTitle(a.createDateTime);
        if (_days.isEmpty || _days.last.title != title) _days.add(_Day(title));
        _days.last.items.add(MediaItem.fromAsset(a));
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 700) _loadMore();
  }

  void _loadSamples() {
    final groups = studio.pickVideo ? videoGroups : photoGroups;
    _days
      ..clear()
      ..addAll([for (final g in groups) _Day(g.title)..items.addAll(g.items)]);
    _sel = studio.pickVideo ? groups[0].items[1] : groups[0].items[0];
    _loading = false;
  }

  void _useSamples() => setState(() {
        _samples = true;
        _loadSamples();
      });

  void _setKind(bool video) {
    if (studio.pickVideo == video) return;
    studio.openPicker(video: video);
    if (_samples) {
      setState(_loadSamples);
    } else if (_hasAccess) {
      _openKind();
    }
  }

  void _continue() {
    final it = _sel;
    if (it == null) return;
    studio.loadMedia(it);
    if (it.isVideo) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MotionEditorScreen()));
    } else {
      goAfterEdit(context, fromVideo: false);
    }
  }

  int _total(bool video) {
    if (_samples) {
      final g = video ? videoGroups : photoGroups;
      return g.fold<int>(0, (n, x) => n + x.items.length);
    }
    return video ? _videoCount : _photoCount;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final video = studio.pickVideo;
        final sel = _sel;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    AppNav(
                      title: 'Pick Media',
                      back: 'Create',
                      trailing: const Text('Albums',
                          style: TextStyle(
                              color: AppColors.sub, fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(
                        children: [
                          _Chip('Videos', _fmtInt(_total(true)), video, () => _setKind(true)),
                          const SizedBox(width: 8),
                          _Chip('Photos', _fmtInt(_total(false)), !video, () => _setKind(false)),
                          const Spacer(),
                          Text(_samples ? 'Samples' : 'Recents ▾', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    if (!_samples && _perm == PermissionState.limited)
                      _LimitedBanner(onManage: PhotoManager.presentLimited),
                    Expanded(child: _body(video)),
                  ],
                ),
                if (sel != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 14 + MediaQuery.of(context).padding.bottom,
                    child: _SelectionBar(item: sel, onContinue: _continue),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(bool video) {
    if (_loading && _days.isEmpty) return const Center(child: CircularProgressIndicator());
    if (!_samples && !_hasAccess) {
      return _NoAccess(onAllow: _init, onSamples: _useSamples);
    }
    if (_days.isEmpty) {
      return Center(
        child: Text('No ${video ? 'videos' : 'photos'} found', style: AppText.small),
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        for (final d in _days) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(d.title, style: AppText.mono),
                  Text('${d.items.length} ${video ? 'CLIPS' : 'PHOTOS'}', style: AppText.mono),
                ],
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              childAspectRatio: 1 / 1.12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final it = d.items[i];
                return _Tile(
                  item: it,
                  selected: identical(_sel, it),
                  onTap: () => setState(() => _sel = it),
                );
              },
              childCount: d.items.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.count, this.on, this.onTap);

  final String label;
  final String count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF14111F) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? const Color(0xFF14111F) : AppColors.line),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: on ? Colors.white : AppColors.ink)),
            const SizedBox(width: 4),
            Text(count,
                style: AppText.mono.copyWith(color: on ? const Color(0xFFBDB7D8) : AppColors.sub)),
          ],
        ),
      ),
    );
  }
}

class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onManage});

  final Future<void> Function() onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E6F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Limited access: only selected items are shown.',
                style: TextStyle(fontSize: 12, color: AppColors.sub)),
          ),
          GestureDetector(
            onTap: onManage,
            child: const Text('Manage',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.pri)),
          ),
        ],
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onAllow, required this.onSamples});

  final VoidCallback onAllow;
  final VoidCallback onSamples;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 44, color: AppColors.sub),
            const SizedBox(height: 14),
            const Text('Allow access to your gallery',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Pick your own videos and photos to make wallpapers. They stay on your device.',
              textAlign: TextAlign.center,
              style: AppText.small.copyWith(fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Allow access', onTap: onAllow),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onSamples,
              child: const Text('Use sample footage',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.selected, required this.onTap});

  final MediaItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0xB3000000), blurRadius: 3)];
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaThumb(item),
          if (item.isVideo) ...[
            if (!item.isReal)
              Positioned(
                left: 5,
                right: 5,
                bottom: 16,
                child: Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, shadows: shadow)),
              ),
            Positioned(
              left: 5,
              bottom: 4,
              child: Text(item.duration,
                  style: AppText.mono.copyWith(color: Colors.white, fontSize: 10, shadows: shadow)),
            ),
          ],
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: AppColors.live, width: 2)),
              ),
            ),
          Positioned(
            right: 5,
            top: 5,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.live : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.live : Colors.white, width: 1.5),
              ),
              child: selected
                  ? const Text('1',
                      style: TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.item, required this.onContinue});

  final MediaItem item;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x7328145A), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -12),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 34, height: 46, child: MediaThumb(item)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.detail, style: AppText.mono),
                Text('1 OF 1 SELECTED', style: AppText.mono.copyWith(color: AppColors.live)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PrimaryButton(label: 'Continue', onTap: onContinue),
        ],
      ),
    );
  }
}
