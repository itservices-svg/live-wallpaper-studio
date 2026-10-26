import 'package:photo_manager/photo_manager.dart';

/// Reads the device gallery, newest first, one page at a time.
class MediaPager {
  MediaPager._(this._path, this.total);

  final AssetPathEntity _path;
  final int total;

  static const int pageSize = 90;

  int _page = 0;
  bool _busy = false;
  bool hasMore = true;

  static Future<PermissionState> requestAccess() => PhotoManager.requestPermissionExtend();

  /// Opens the "Recent / All" album for videos or photos. Null when it is empty.
  static Future<MediaPager?> open({required bool video}) async {
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: video ? RequestType.video : RequestType.image,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isEmpty) return null;
    final total = await paths.first.assetCountAsync;
    return MediaPager._(paths.first, total);
  }

  /// Next page of assets. Returns an empty list when done or while a page is loading.
  Future<List<AssetEntity>> next() async {
    if (_busy || !hasMore) return const [];
    _busy = true;
    try {
      final list = await _path.getAssetListPaged(page: _page, size: pageSize);
      _page++;
      if (list.length < pageSize) hasMore = false;
      return list;
    } finally {
      _busy = false;
    }
  }
}
