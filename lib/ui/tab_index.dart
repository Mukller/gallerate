import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Индексы вкладок нижней навигации.
///
/// IndexedStack держит все вкладки живыми, поэтому экраны должны знать,
/// видны ли они сейчас: иначе каждая оценка порождала бы 4 лишних запроса
/// в SQLite на невидимых вкладках.
class TabIndex {
  const TabIndex._();

  static const swipe = 0;
  static const best = 1;
  static const cleanup = 2;
  static const history = 3;
  static const stats = 4;
}

extension TabVisibility on BuildContext {
  /// Видна ли сейчас вкладка [myIndex].
  bool isTabVisible(int myIndex) => watch<int>() == myIndex;
}
