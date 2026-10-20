import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/db.dart';
import 'package:gallerate/data/models.dart';

SetInfo makeSet({
  int id = 1,
  List<String>? ids,
  int cursor = 0,
  bool completed = false,
}) {
  return SetInfo(
    id: id,
    day: '2026-09-28',
    assetIds: ids ?? ['a', 'b', 'c'],
    cursor: cursor,
    completed: completed,
    createdAt: 0,
  );
}

void main() {
  group('SetInfo.hasPending', () {
    test('пустой набор — нечего проходить', () {
      expect(makeSet(ids: const [], cursor: 0).hasPending, isFalse);
    });

    test('cursor в середине — есть что проходить', () {
      expect(makeSet(cursor: 1).hasPending, isTrue);
    });

    test('cursor на конце — сет пройден', () {
      expect(makeSet(cursor: 3).hasPending, isFalse);
    });

    test('completed=true — сет закрыт даже при малом cursor', () {
      expect(makeSet(cursor: 0, completed: true).hasPending, isFalse);
    });

    // Регрессия: completeSet() писал cursor = -1, а hasPending считал
    // «-1 < длина» -> true, и приложение снова открывало закрытый сет.
    test('cursor = -1 (после completeSet) — сет закрыт', () {
      expect(makeSet(cursor: -1).hasPending, isFalse);
    });

    test('currentId возвращает id по курсору', () {
      expect(makeSet(cursor: 1).currentId, 'b');
    });

    test('currentId = null на закрытом сете', () {
      expect(makeSet(cursor: 3).currentId, isNull);
      expect(makeSet(cursor: -1).currentId, isNull);
    });

    test('cursor больше длины не падает', () {
      expect(makeSet(cursor: 99).hasPending, isFalse);
      expect(makeSet(cursor: 99).currentId, isNull);
    });
  });

  group('SetInfo.fromMap', () {
    test('разбирает asset_ids и флаги', () {
      final s = SetInfo.fromMap({
        'id': 7,
        'day': '2026-09-28',
        'asset_ids': 'x,y,z',
        'cursor': 0,
        'completed': 0,
        'created_at': 123,
      });
      expect(s.id, 7);
      expect(s.assetIds, ['x', 'y', 'z']);
      expect(s.completed, isFalse);
      expect(s.hasPending, isTrue);
    });

    test('пустая строка asset_ids даёт пустой список', () {
      final s = SetInfo.fromMap({
        'id': 8,
        'day': '2026-09-28',
        'asset_ids': '',
        'cursor': 0,
        'completed': 0,
        'created_at': 0,
      });
      expect(s.assetIds, isEmpty);
      expect(s.hasPending, isFalse);
    });
  });

  group('AppDb.dayKey', () {
    test('формат YYYY-MM-DD с ведущими нулями', () {
      expect(AppDb.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(AppDb.dayKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(AppDb.dayKey(DateTime(2026, 9, 28)), '2026-09-28');
    });
  });
}
