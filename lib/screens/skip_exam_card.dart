import '../data/practice.dart';
import '../data/skip_exam.dart';
import '../models/course.dart';
import '../theme.dart';
import 'lesson_screen.dart';

/// "Bu üniteyi atla": the unit's skip exam, [skipHearts] hearts. [unit] must
/// be the unit with its lessons (not the outline). Null when the unit has
/// too few questions for a fair exam.
LessonScreen? unitSkipScreen(Unit unit) {
  if (unitSkipItems(unit).length < skipMinQuestions) return null;
  LessonScreen build() => LessonScreen(
    nodeId: unitSkipId(unit),
    title: unit.title,
    items: unitSkipItems(unit),
    color: Brand.tone(unit.color),
    mode: LessonMode.test,
    rewardXp: unitSkipXp,
    hearts: skipHearts,
    retry: build,
    badge: 'ÜNİTEYİ ATLA',
    passHeadline: 'Üniteyi atladın!',
  );
  return build();
}

/// What the skip exam rules are, in one friendly paragraph.
String skipRules({required bool unit}) =>
    '$skipHearts canın var; her yanlış cevap bir can götürür. Canların bitmeden sona ulaşırsan '
    '${unit ? 'ünitenin' : 'bölümün'} tüm adımları bitmiş sayılır ve sıradaki açılır. '
    'Olmazsa hiçbir şey kaybetmezsin, istediğin zaman yeniden denersin.';
