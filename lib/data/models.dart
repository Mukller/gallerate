class PhotoRow {
  PhotoRow({
    required this.id,
    required this.rating,
    required this.day,
    required this.ratedAt,
    required this.deleted,
    this.sorted = false,
  });

  final String id;
  final int rating;
  final String day;
  final int ratedAt;
  final bool deleted;
  final bool sorted;

  factory PhotoRow.fromMap(Map<String, Object?> map) => PhotoRow(
        id: map['id'] as String,
        rating: map['rating'] as int,
        day: map['day'] as String,
        ratedAt: map['rated_at'] as int,
        deleted: (map['deleted'] as int) == 1,
        sorted: (map['sorted'] as int? ?? 0) == 1,
      );
}

class SetInfo {
  SetInfo({
    required this.id,
    required this.day,
    required this.assetIds,
    required this.cursor,
    required this.completed,
    required this.createdAt,
  });

  final int id;
  final String day;
  final List<String> assetIds;
  final int cursor;
  final bool completed;
  final int createdAt;

  /// cursor == -1 означает «сет закрыт» (см. completeSet), поэтому
  /// проверяем и completed, и неотрицательность курсора.
  bool get hasPending => !completed && cursor >= 0 && cursor < assetIds.length;

  String? get currentId {
    if (!hasPending) return null;
    if (cursor >= assetIds.length) return null;
    return assetIds[cursor];
  }

  SetInfo copyWith({int? cursor, bool? completed}) => SetInfo(
        id: id,
        day: day,
        assetIds: assetIds,
        cursor: cursor ?? this.cursor,
        completed: completed ?? this.completed,
        createdAt: createdAt,
      );

  factory SetInfo.fromMap(Map<String, Object?> map) {
    final raw = map['asset_ids'] as String;
    return SetInfo(
      id: map['id'] as int,
      day: map['day'] as String,
      assetIds:
          (raw.isEmpty ? <String>[] : raw.split(',')).toList(growable: false),
      cursor: map['cursor'] as int,
      completed: (map['completed'] as int) == 1,
      createdAt: map['created_at'] as int,
    );
  }
}

class DayStat {
  DayStat({
    required this.day,
    this.likes = 0,
    this.dislikes = 0,
    this.skips = 0,
  });

  final String day;
  int likes;
  int dislikes;
  int skips;

  int get ratedTotal => likes + dislikes + skips;
}
