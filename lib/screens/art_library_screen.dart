import 'dart:io';

import 'package:flutter/material.dart';

import '../services/depth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Built-in pictures drawn in code. Pops with the chosen [ArtDef] and its file path.
class ArtLibraryScreen extends StatefulWidget {
  const ArtLibraryScreen({super.key, this.only});

  /// null = all, true = front overlays only, false = back pictures only.
  final bool? only;

  @override
  State<ArtLibraryScreen> createState() => _ArtLibraryScreenState();
}

class _ArtLibraryScreenState extends State<ArtLibraryScreen> {
  int _tint = 0;

  @override
  Widget build(BuildContext context) {
    final only = widget.only;
    final items = [for (final a in DepthArt.catalog) if (only == null || a.front == only) a];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNav(title: only == true ? 'Front overlays' : (only == false ? 'Back pictures' : 'Built-in library'), back: 'Back'),
            if (items.any((a) => a.tintable))
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Text('Colour', style: AppText.small),
                    const SizedBox(width: 10),
                    for (var i = 0; i < DepthArt.tints.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(DepthArt.tints[i].$1),
                          selected: _tint == i,
                          onSelected: (_) => setState(() => _tint = i),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.5,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _Tile(
                  key: ValueKey('${items[i].id}_${items[i].tintable ? _tint : 0}'),
                  def: items[i],
                  tint: _tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({super.key, required this.def, required this.tint});

  final ArtDef def;
  final int tint;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  late final Future<String> _path = widget.def.build(widget.tint);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _path,
      builder: (context, snap) {
        final path = snap.data;
        return GestureDetector(
          onTap: path == null ? null : () => Navigator.of(context).pop<(ArtDef, String)>((widget.def, path)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    // a sunset behind, so see-through parts are easy to see
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1C3C7A), Color(0xFFC8668A), Color(0xFFF0B070)],
                      ),
                    ),
                    child: path == null
                        ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                        : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 300),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(widget.def.name, style: AppText.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }
}
