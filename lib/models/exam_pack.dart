import 'exam.dart';

/// How a full mock exam is scored.
enum ExamScoring {
  /// YDS/YÖKDİL: 80 questions, every correct answer 1.25 points (100 total),
  /// wrong answers don't cost anything.
  yds,

  /// LGS: net = correct − wrong / 3. The LGS score itself combines all
  /// subjects, so only the English net is shown.
  lgs,
}

class PackTopic {
  const PackTopic({required this.id, required this.title});
  final String id;
  final String title;

  factory PackTopic.fromJson(Map<String, dynamic> j) =>
      PackTopic(id: j['id'] as String, title: j['title'] as String);
}

/// One full-length mock exam.
class FullMock {
  const FullMock({required this.id, required this.title, required this.minutes, required this.questions});
  final String id;
  final String title;
  final int minutes;
  final List<ExamQuestion> questions;

  factory FullMock.fromJson(Map<String, dynamic> j) => FullMock(
    id: j['id'] as String,
    title: j['title'] as String,
    minutes: j['minutes'] as int,
    questions: (j['questions'] as List).map((q) => ExamQuestion.fromJson(q as Map<String, dynamic>)).toList(),
  );
}

/// Content of a paid exam pack (`assets/exam_packs/<exam>_full.json`).
class ExamPackContent {
  const ExamPackContent({
    required this.id,
    required this.examId,
    required this.title,
    required this.description,
    required this.scoring,
    required this.optionCount,
    required this.sections,
    required this.mocks,
  });

  final String id;
  final String examId;
  final String title;
  final String description;
  final ExamScoring scoring;
  final int optionCount;
  final List<PackTopic> sections;
  final List<FullMock> mocks;

  String sectionTitle(String? id) {
    for (final s in sections) {
      if (s.id == id) return s.title;
    }
    return 'Diğer';
  }

  factory ExamPackContent.fromJson(Map<String, dynamic> j) => ExamPackContent(
    id: j['id'] as String,
    examId: j['examId'] as String,
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    scoring: ExamScoring.values.byName(j['scoring'] as String),
    optionCount: j['optionCount'] as int,
    sections: (j['sections'] as List).map((s) => PackTopic.fromJson(s as Map<String, dynamic>)).toList(),
    mocks: (j['mocks'] as List).map((m) => FullMock.fromJson(m as Map<String, dynamic>)).toList(),
  );
}

/// Result of a finished mock exam: counts, net, score estimate and topic
/// breakdown. Pure so it can be unit tested.
class MockScore {
  MockScore._(this.correct, this.wrong, this.blank, this.net, this.score, this.topics);

  final int correct;
  final int wrong;
  final int blank;
  final double net;

  /// Estimated exam score (YDS: 0–100). Null where a score can't be
  /// estimated from one subject (LGS).
  final double? score;

  /// Section id → (correct, total), in the order sections appear.
  final Map<String, ({int correct, int wrong, int total})> topics;

  int get total => correct + wrong + blank;

  factory MockScore.of(List<ExamQuestion> questions, Map<int, int> answers, ExamScoring scoring) {
    var correct = 0, wrong = 0;
    final topics = <String, ({int correct, int wrong, int total})>{};
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final a = answers[i];
      final ok = a != null && a == q.answer;
      final bad = a != null && a != q.answer;
      if (ok) correct++;
      if (bad) wrong++;
      final key = q.section ?? '';
      final t = topics[key] ?? (correct: 0, wrong: 0, total: 0);
      topics[key] = (correct: t.correct + (ok ? 1 : 0), wrong: t.wrong + (bad ? 1 : 0), total: t.total + 1);
    }
    final blank = questions.length - correct - wrong;
    return switch (scoring) {
      ExamScoring.yds => MockScore._(
        correct,
        wrong,
        blank,
        correct.toDouble(),
        questions.isEmpty ? 0 : correct * 100 / questions.length,
        topics,
      ),
      ExamScoring.lgs => MockScore._(correct, wrong, blank, correct - wrong / 3, null, topics),
    };
  }
}
