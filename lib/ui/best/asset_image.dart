import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../swipe/card_deck.dart' show AssetThumbImage;

class AssetEntityImageLoader extends StatefulWidget {
  const AssetEntityImageLoader({super.key, required this.assetId});

  final String assetId;

  @override
  State<AssetEntityImageLoader> createState() => _AssetEntityImageLoaderState();
}

class _AssetEntityImageLoaderState extends State<AssetEntityImageLoader> {
  // Кэш нужен обязательно: AssetEntity.fromId() возвращает НОВЫЙ Future
  // на каждый вызов. Создавая future прямо в build(), мы бы запускали
  // бесконечный цикл future -> setState -> build -> future ...
  static final Map<String, Future<AssetEntity?>> _cache = {};
  static const int _maxCache = 800;

  late Future<AssetEntity?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve(widget.assetId);
  }

  @override
  void didUpdateWidget(covariant AssetEntityImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _future = _resolve(widget.assetId);
    }
  }

  static Future<AssetEntity?> _resolve(String id) {
    return _cache.putIfAbsent(id, () {
      if (_cache.length >= _maxCache) _cache.clear();
      return AssetEntity.fromId(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: _future,
      builder: (context, snap) {
        final asset = snap.data;
        if (asset == null) {
          return const ColoredBox(color: Color(0x22000000));
        }
        return AssetThumbImage(asset: asset);
      },
    );
  }
}
