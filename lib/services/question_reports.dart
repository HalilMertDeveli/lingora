import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import 'firebase/firebase_providers.dart';

/// "Bildir": what is wrong with a question, in the learner's words.
enum ReportReason {
  wrongAnswer('wrong_answer', 'Cevap hatalı'),
  otherCorrect('other_correct', 'Başka cevap da doğru'),
  unclear('unclear', 'Açıklama anlaşılmıyor');

  const ReportReason(this.code, this.label);

  /// Stored in `reports/{id}.reason` (firestore.rules lists the codes).
  final String code;
  final String label;

  static ReportReason? byCode(String? code) => values.where((r) => r.code == code).firstOrNull;
}

/// Triage state in the panel: yeni → bakıldı → düzeltildi.
enum ReportStatus {
  fresh('yeni', 'Yeni'),
  seen('bakildi', 'Bakıldı'),
  fixed('duzeltildi', 'Düzeltildi');

  const ReportStatus(this.code, this.label);
  final String code;
  final String label;

  static ReportStatus byCode(String? code) => values.where((s) => s.code == code).firstOrNull ?? fresh;
}

/// Most letters of the optional note (firestore.rules: 500).
const maxReportNote = 500;

/// Limits firestore.rules enforces on `reportLimits/{uid}`.
const reportMinGap = Duration(seconds: 10);
const reportsPerDay = 20;

/// One report. The question, lesson, answer and app version are filled in
/// by the app; the learner only picks [reason] and may add a [note].
class QuestionReport {
  const QuestionReport({
    required this.reason,
    required this.questionId,
    required this.lessonId,
    required this.appVersion,
    this.note,
    this.answer,
    this.correct,
    this.question,
    this.track,
  });

  final ReportReason reason;

  /// Item key ("u1l1#3") or exam question id.
  final String questionId;
  final String lessonId;
  final String appVersion;
  final String? note;

  /// What the learner answered, when the app knows it (typed answers).
  final String? answer;

  /// Whether the answer was right; null when it was not checked yet.
  final bool? correct;

  /// The question's text, so the panel can show it without the course.
  final String? question;
  final String? track;

  static String? _cut(String? s, int max) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length <= max ? t : t.substring(0, max);
  }

  /// The document fields (without uid, createdAt and status).
  Map<String, Object> toFields() => {
    'reason': reason.code,
    'questionId': _cut(questionId, 120) ?? '?',
    'lessonId': _cut(lessonId, 80) ?? '',
    'appVersion': _cut(appVersion, 40) ?? '?',
    'note': ?_cut(note, maxReportNote),
    'answer': ?_cut(answer, 300),
    'correct': ?correct,
    'question': ?_cut(question, 400),
    'track': ?_cut(track, 40),
  };
}

/// Why a report was not sent.
enum ReportError {
  /// Firebase is off or there is no (guest) account yet.
  unavailable('Bildirim şu an gönderilemiyor. Biraz sonra tekrar dene.'),
  tooFast('Az önce bir bildirim gönderdin. Birkaç saniye sonra tekrar dene.'),
  dailyLimit('Bugün için bildirim sınırına ulaştın. Teşekkürler, yarın yine gönderebilirsin.'),
  failed('Gönderilemedi. İnternet bağlantını kontrol edip tekrar dene.');

  const ReportError(this.message);
  final String message;
}

class ReportException implements Exception {
  const ReportException(this.error);
  final ReportError error;

  @override
  String toString() => 'ReportException(${error.name})';
}

abstract interface class QuestionReporter {
  /// Sends [report]; throws [ReportException] when it cannot.
  Future<void> send(QuestionReport report);
}

/// Writes `reports/{uid}_{n}` and `reportLimits/{uid}` in one transaction,
/// as firestore.rules requires (it checks both together).
class FirestoreQuestionReporter implements QuestionReporter {
  FirestoreQuestionReporter(this._db, this._uid, this._now);
  final FirebaseFirestore _db;
  final String? _uid;
  final DateTime Function() _now;

  @override
  Future<void> send(QuestionReport report) async {
    final uid = _uid;
    if (uid == null) throw const ReportException(ReportError.unavailable);
    final limitRef = _db.collection('reportLimits').doc(uid);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(limitRef);
        final now = _now();
        final old = snap.data();
        final n = ((old?['n'] as num?)?.toInt() ?? 0) + 1;
        final last = (old?['last'] as Timestamp?)?.toDate();
        // Kept as the stored Timestamp: rules compare it to the nanosecond.
        final windowTs = old?['windowStart'] as Timestamp?;
        final windowStart = windowTs?.toDate();
        final count = (old?['count'] as num?)?.toInt() ?? 0;
        if (last != null && now.difference(last) < reportMinGap) {
          throw const ReportException(ReportError.tooFast);
        }
        final sameWindow = windowStart != null && now.difference(windowStart) < const Duration(days: 1);
        if (sameWindow && count >= reportsPerDay) throw const ReportException(ReportError.dailyLimit);
        tx.set(limitRef, {
          'windowStart': sameWindow ? windowTs! : FieldValue.serverTimestamp(),
          'count': sameWindow ? count + 1 : 1,
          'last': FieldValue.serverTimestamp(),
          'n': n,
        });
        tx.set(_db.collection('reports').doc('${uid}_$n'), {
          ...report.toFields(),
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'status': ReportStatus.fresh.code,
        });
      });
    } on ReportException {
      rethrow;
    } catch (_) {
      throw const ReportException(ReportError.failed);
    }
  }
}

/// Null when Firebase is off (the "Bildir" sheet then says so).
final questionReporterProvider = Provider<QuestionReporter?>((ref) {
  final db = ref.watch(firestoreProvider);
  if (db == null) return null;
  return FirestoreQuestionReporter(db, ref.watch(currentUidProvider), ref.read(clockProvider));
});

/// A report as the panel lists it.
class ReportEntry {
  const ReportEntry({
    required this.id,
    required this.reason,
    required this.status,
    required this.questionId,
    required this.lessonId,
    required this.appVersion,
    this.note,
    this.answer,
    this.correct,
    this.question,
    this.track,
    this.createdAt,
  });

  factory ReportEntry.fromDoc(String id, Map<String, dynamic> d) => ReportEntry(
    id: id,
    reason: ReportReason.byCode(d['reason'] as String?) ?? ReportReason.unclear,
    status: ReportStatus.byCode(d['status'] as String?),
    questionId: d['questionId'] as String? ?? '',
    lessonId: d['lessonId'] as String? ?? '',
    appVersion: d['appVersion'] as String? ?? '',
    note: d['note'] as String?,
    answer: d['answer'] as String?,
    correct: d['correct'] as bool?,
    question: d['question'] as String?,
    track: d['track'] as String?,
    createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
  );

  final String id;
  final ReportReason reason;
  final ReportStatus status;
  final String questionId;
  final String lessonId;
  final String appVersion;
  final String? note;
  final String? answer;
  final bool? correct;
  final String? question;
  final String? track;
  final DateTime? createdAt;
}
