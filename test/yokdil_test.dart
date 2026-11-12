// YÖKDİL in the YDS plan (docs/sinav/yds-faz4-icerik.md): a YÖKDİL learner's
// mocks, YÖKDİL sections and the YÖKDİL question mix in the report and the
// score estimate.
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/study/analysis.dart';
import 'package:lingora/study/daily_plan.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/study/study_state.dart';
import 'package:lingora/study/year_plan.dart';

AnswerLog a(QType t, bool ok, {String src = 'lesson'}) =>
    AnswerLog(key: 'k', day: '2026-11-12', correct: ok, seconds: 60, type: t.name, source: src);

void main() {
  const m16 = PlanMock(kind: MockKind.full, id: 'yds_m16', size: 80, minutes: 180, yokdil: 'yokdil_m1');
  const pack = ['yds_m1', 'yds_m2', 'yds_m16', 'yokdil_m1', 'yokdil_m2'];

  test('a plan mock carries its YÖKDİL twin', () {
    final m = PlanMock.fromJson({
      'kind': 'full',
      'id': 'yds_m16',
      'size': 80,
      'minutes': 180,
      'yokdil': 'yokdil_m1',
    });
    expect((m.id, m.yokdil), ('yds_m16', 'yokdil_m1'));
  });

  test('a YÖKDİL learner gets the YÖKDİL mock; without it in the pack, the YDS one', () {
    expect(pickFullMock(packIds: pack, exam: 'yds', mock: m16), 'yds_m16');
    expect(pickFullMock(packIds: pack, exam: 'yokdil_saglik', mock: m16), 'yokdil_m1');
    expect(pickFullMock(packIds: const ['yds_m16'], exam: 'yokdil_fen', mock: m16), 'yds_m16');
    expect(pickFullMock(packIds: const ['yds_m1'], exam: 'yds', mock: m16), isNull);
  });

  test('maintenance: the next mock not taken, then a retake of the first', () {
    const any = PlanMock(kind: MockKind.full);
    expect(pickFullMock(packIds: pack, exam: 'yds', mock: any, taken: {'yds_m1'}), 'yds_m2');
    expect(pickFullMock(packIds: pack, exam: 'yokdil_fen', mock: any, taken: {'yokdil_m1'}), 'yokdil_m2');
    // All taken: the retake rotates week by week.
    final retakes = {
      for (var w = 53; w < 56; w++)
        pickFullMock(packIds: pack, exam: 'yds', mock: any, taken: pack.toSet(), week: w),
    };
    expect(retakes, hasLength(3));
    expect(retakes.every((id) => id!.startsWith('yds_m')), isTrue);
  });

  test('YÖKDİL sections read like YDS ones', () {
    expect(questionType(question: 'x', section: 'yokdil_reading'), QType.reading);
    expect(questionType(question: 'x', section: 'yokdil_translation'), QType.translation);
    expect(fullMockId.hasMatch('yokdil_m2'), isTrue);
  });

  test('the YÖKDİL mix: 80 questions, no dialogue or restatement, 72 right planned', () {
    const y = ExamMix.yokdil;
    expect(QType.values.fold(0, (s, t) => s + y.count(t)), 80);
    expect((y.count(QType.dialogue), y.count(QType.restatement), y.count(QType.reading)), (0, 0, 15));
    expect(QType.values.fold(0.0, (s, t) => s + y.target(t)), closeTo(72, 0.001));
    expect(ExamMix.of('yokdil_fen'), y);
    expect(ExamMix.of('yokdil_m1'), y);
    expect(ExamMix.of('yds'), ExamMix.yds);
  });

  test('a YÖKDİL mock report uses the YÖKDİL targets', () {
    final answers = [for (var i = 0; i < 15; i++) a(QType.reading, i < 9, src: 'mock:yokdil_m1@1')];
    final yds = MockReport(answers).rows.single;
    final yokdil = MockReport(answers, mix: ExamMix.yokdil).rows.single;
    expect(yds.target, closeTo(17 * 15 / 20, 0.001));
    expect(yokdil.target, closeTo(13.5, 0.001));
    expect(yokdil.gap, 5);
  });

  test('the practice estimate follows the learner\'s exam mix', () {
    // Dialogue is weak; YÖKDİL has none, so its estimate is higher.
    final log = [
      for (final t in QType.values.where((t) => t.inExam > 0))
        for (var i = 0; i < 10; i++) a(t, t == QType.dialogue ? false : i < 8),
    ];
    final yds = estimateScore(log)!;
    final yokdil = estimateScore(log, mix: ExamMix.yokdil)!;
    expect((yokdil.low + yokdil.high) / 2, greaterThan((yds.low + yds.high) / 2));
  });
}
