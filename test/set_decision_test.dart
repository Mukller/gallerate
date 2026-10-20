import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/set_decision.dart';

const today = '2026-09-28';
const yesterday = '2026-09-27';

bool gen({
  bool hasActiveSet = false,
  bool force = false,
  bool timeReached = false,
  bool poolEmpty = false,
  String? poolEmptyDay,
  String today = today,
}) {
  return SetDecision.shouldGenerate(
    hasActiveSet: hasActiveSet,
    force: force,
    timeReached: timeReached,
    poolEmpty: poolEmpty,
    poolEmptyDay: poolEmptyDay,
    today: today,
  );
}

void main() {
  group('shouldCloseStaleSet', () {
    test('сета нет — закрывать нечего', () {
      expect(SetDecision.shouldCloseStaleSet(null, today), isFalse);
    });

    test('сет за сегодня — не трогаем', () {
      expect(SetDecision.shouldCloseStaleSet(today, today), isFalse);
    });

    test('вчерашний сет — закрываем', () {
      expect(SetDecision.shouldCloseStaleSet(yesterday, today), isTrue);
    });

    test('сет из прошлого месяца — закрываем', () {
      expect(SetDecision.shouldCloseStaleSet('2026-08-01', today), isTrue);
    });
  });

  group('shouldGenerate — есть активный сет', () {
    test('не генерируем, даже если пора и force', () {
      // Регрессия: кнопка «Ещё сет» не должна подменять текущий набор.
      expect(gen(hasActiveSet: true, force: true, timeReached: true), isFalse);
    });
  });

  group('shouldGenerate — время и force', () {
    test('время ещё не наступило и force=false — ждём', () {
      expect(gen(timeReached: false), isFalse);
    });

    test('время наступило — генерируем', () {
      expect(gen(timeReached: true), isTrue);
    });

    test('force обходит ожидание времени (кнопка «Открыть сейчас»)', () {
      expect(gen(force: true, timeReached: false), isTrue);
    });
  });

  group('shouldGenerate — пустой пул', () {
    // Регрессия: минутный таймер пересканировал всю галерею,
    // когда новых фото не осталось.
    test('сегодня уже подтверждено «пусто» — не сканируем снова', () {
      expect(gen(timeReached: true, poolEmpty: true, poolEmptyDay: today),
          isFalse);
    });

    test('вчера было пусто, сегодня — можно пробовать', () {
      expect(
        gen(
          timeReached: true,
          poolEmpty: true,
          poolEmptyDay: yesterday,
          today: today,
        ),
        isTrue,
      );
    });

    test('новые сутки без отметки «пусто» — генерируем', () {
      expect(gen(timeReached: true, poolEmpty: false), isTrue);
    });

    test('force всё равно пробует даже при пустом пуле', () {
      // Пользователь мог удалить фото — шанс, что что-то появилось.
      expect(gen(force: true, poolEmpty: true, poolEmptyDay: today), isTrue);
    });

    test('poolEmpty без дня — состояние неполное, пробуем', () {
      expect(
          gen(timeReached: true, poolEmpty: true, poolEmptyDay: null), isTrue);
    });
  });

  group('isWaitingForSetTime', () {
    test('время не наступило — ждём', () {
      expect(SetDecision.isWaitingForSetTime(timeReached: false), isTrue);
    });

    test('время наступило — не ждём', () {
      expect(SetDecision.isWaitingForSetTime(timeReached: true), isFalse);
    });
  });

  group('countLeadingMissing', () {
    // Логика пропуска исчезнувших ассетов: без неё окно карточек
    // «съезжает», и оценка уходит на чужое фото.
    test('первый доступен — ничего не пропускаем', () {
      expect(SetDecision.countLeadingMissing([true, false, false]), 0);
    });

    test('первый недоступен — пропускаем один', () {
      expect(SetDecision.countLeadingMissing([false, true, true]), 1);
    });

    test('два подряд недоступны', () {
      expect(SetDecision.countLeadingMissing([false, false, true]), 2);
    });

    test('все недоступны — пропускаем всё', () {
      expect(SetDecision.countLeadingMissing([false, false, false]), 3);
    });

    test('пустой набор', () {
      expect(SetDecision.countLeadingMissing([]), 0);
    });

    test('недоступный посередине не считается — серия прерывается', () {
      expect(SetDecision.countLeadingMissing([true, false, false]), 0);
      expect(SetDecision.countLeadingMissing([false, true, false, true]), 1);
    });

    test('смешанный набор', () {
      expect(SetDecision.countLeadingMissing([false, false, false, true, true]),
          3);
    });
  });

  test('полный сценарий: утром ждём, вечером генерируем', () {
    final option = SetOption(nowReached: false);
    expect(option.waiting, isTrue);
    expect(option.generate(false), isFalse);

    option.nowReached = true;
    expect(option.waiting, isFalse);
    expect(option.generate(false), isTrue);
  });
}

/// Мини-обёртка над правилами для сценарной проверки.
class SetOption {
  SetOption({required this.nowReached});

  bool nowReached;

  bool get waiting => SetDecision.isWaitingForSetTime(timeReached: nowReached);

  bool generate(bool force) => SetDecision.shouldGenerate(
        hasActiveSet: false,
        force: force,
        timeReached: nowReached,
        poolEmpty: false,
        poolEmptyDay: null,
        today: today,
      );
}
