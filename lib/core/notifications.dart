import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Ежедневное напоминание «появился новый сет фото».
///
/// Осознанные решения:
///  * Используем `inexactAllowWhileIdle`, а не `exactAllowWhileIdle`:
///    точные будильники требуют SCHEDULE_EXACT_ALARM, который на Android 13+
///    нужно выдавать пользователю вручную. Для «напомнить вечером» это
///    overkill, а inexact всё равно будит устройство из Doze.
///  * Уведомление — единичный daily-триггер, поэтому переживать перезапуск
///    не нужно: после перезагрузки BootReceiver восстановит его сам.
/// Когда должно сработать ежедневное напоминание.
///
/// Вынесено в чистую функцию ради тестируемости: сдвиг «сегодня или завтра»
/// легко испортить, а ошибиться в нём — значит разбудить пользователя не в
/// то время (или в UTC вместо локального).
///
/// [minutes] — минуты от полуночи локального времени.
tz.TZDateTime computeNextTrigger({
  required tz.Location location,
  required tz.TZDateTime now,
  required int minutes,
}) {
  var when = tz.TZDateTime(
    location,
    now.year,
    now.month,
    now.day,
    minutes ~/ 60,
    minutes % 60,
  );
  // Уже прошло сегодня — значит ждём завтра.
  if (!when.isAfter(now)) {
    when = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + 1,
      minutes ~/ 60,
      minutes % 60,
    );
  }
  return when;
}

class Notifications {
  Notifications._();

  static final Notifications instance = Notifications._();

  static const _dailyId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Инициализация. Метод безопасен для вызова из любого места и не бросает:
  /// на неподдерживаемых платформах (desktop/web в тестах) он просто
  /// выключает напоминания, чтобы приложение не падало.
  Future<void> init() async {
    if (_ready || !isSupported) return;
    try {
      tzdata.initializeTimeZones();
      await _applyLocalTimeZone();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications.init failed: $e');
    }
  }

  /// КРИТИЧНО: пакет timezone по умолчанию отдаёт `tz.local == UTC`
  /// (так написано в его исходниках). Без явной установки локальной зоны
  /// напоминание на «20:00» срабатывало бы в 20:00 UTC — то есть на
  /// три часа позже в Минске.
  ///
  /// Порядок важен: сначала база часовых поясов, потом поиск зоны по имени.
  static Future<void> _applyLocalTimeZone() async {
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      if (name.isEmpty) return;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // В release на некоторых конфигурациях имя зоны недоступно.
      // Тогда оставляем UTC и честно предупреждаем в лог: смещение будет
      // неверным, но напоминание всё равно придёт — лучше, чем упадёт.
      debugPrint('Notifications: не удалось определить локальную зону ($e), '
          'используется UTC');
    }
  }

  /// Android 13+ требует явного согласия на уведомления.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      await init();
      if (!_ready) return false;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
                alert: true, badge: true, sound: true) ??
            false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('Notifications.requestPermission failed: $e');
      return false;
    }
  }

  /// Ставит ежедневное напоминание на [minutes] минут от полуночи.
  Future<void> scheduleDaily({
    required int minutes,
    required String title,
    required String body,
  }) async {
    if (!isSupported) return;
    try {
      await init();
      if (!_ready) return;
      await _plugin.cancel(_dailyId);

      final now = tz.TZDateTime.now(tz.local);
      final when = computeNextTrigger(
        location: tz.local,
        now: now,
        minutes: minutes,
      );
      debugPrint('[Notifications] напоминание на ${when.toIso8601String()} '
          '(зона ${tz.local.name}, сейчас ${now.toIso8601String()})');

      await _plugin.zonedSchedule(
        _dailyId,
        title,
        body,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gallerate_daily_set',
            'Daily set',
            channelDescription:
                'Напоминание о появлении нового сета фото для оценки',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Notifications.scheduleDaily failed: $e');
    }
  }

  Future<void> cancelDaily() async {
    if (!isSupported) return;
    try {
      await init();
      if (!_ready) return;
      await _plugin.cancel(_dailyId);
    } catch (e) {
      debugPrint('Notifications.cancelDaily failed: $e');
    }
  }
}
