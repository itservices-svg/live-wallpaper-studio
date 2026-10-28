import 'dart:io';

import 'package:flutter/material.dart';

import '../services/library_store.dart';

/// Picture for a My Work item: the wallpaper image, the live clip's poster, or the GIF.
class WorkThumb extends StatelessWidget {
  const WorkThumb(this.item, {super.key, this.cacheWidth = 320});

  final SavedTheme item;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final path = item.kind == SavedTheme.live ? item.thumb : item.file;
    if (path == null) {
      return const ColoredBox(
        color: Color(0xFF1E1B2E),
        child: Center(child: Icon(Icons.videocam_rounded, color: Colors.white54)),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFFEEEDF5),
        child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.black26)),
      ),
    );
  }
}
