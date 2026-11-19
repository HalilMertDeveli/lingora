import '../services/billing/products.dart' show PremiumFeature;
import 'learn_goal.dart';

/// Paywall hero copy that follows the learner's goal ("Hedefin ne?").

/// The value line under the hero, always shown without Premium.
const paywallValueLine =
    "Özel hoca saati 500 TL. Çenebaz'da her gün sınırsız konuşma, ayda bir ders fiyatına.";

/// Price anchor shown only while the store's real prices are not loaded
/// (the buttons always use Google Play's prices).
const paywallPriceAnchor = 'aylık 149 TL / yıllık 899 TL (ayı 75 TL)';

class GoalPaywallCopy {
  const GoalPaywallCopy({
    required this.title,
    required this.subtitle,
    required this.focus,
    this.outcomes = const [],
  });

  final String title;
  final String subtitle;

  /// Premium features this goal leans on: listed first and highlighted.
  final List<PremiumFeature> focus;

  /// What this goal gets out of Premium, as short lines under the hero.
  final List<String> outcomes;
}

/// Copy for [goal] at [now]. A null goal (or Okul / genel) keeps the
/// general headline; [variantB] is the Remote Config A/B headline.
GoalPaywallCopy goalPaywallCopy(LearnGoal? goal, DateTime now, {bool variantB = false}) {
  switch (goal?.kind) {
    case GoalKind.exam:
      final exam = goal!.exam.label;
      final left = goal.daysLeft(now);
      final title = switch (left) {
        null => "$exam'ye hazır gir, planın hazır.",
        0 => '$exam günü geldi. Başarılar!',
        < 0 => 'Sıradaki $exam için planın hazır.',
        _ => "$exam'ye $left gün kaldı, planın hazır.",
      };
      return GoalPaywallCopy(
        title: _yokdilSuffix(title, goal.exam),
        subtitle: 'Zayıf soru tiplerine göre gün gün çalışma planı, sınırsız tam deneme ve tahmini puan.',
        focus: const [
          PremiumFeature.unlimitedMockExams,
          PremiumFeature.errorAnalytics,
          PremiumFeature.whyWrong,
          PremiumFeature.explainMore,
        ],
        outcomes: const [
          'Sınava kadar her gün ne çalışacağın belli',
          'İlk tam denemen ücretsiz, sonrakiler sınırsız',
          'Her denemeden sonra tahmini puan ve konu dökümü',
        ],
      );
    case GoalKind.interview:
      return const GoalPaywallCopy(
        title: 'Mülakatına hazır gir: gerçek prova + kişisel geri bildirim',
        subtitle: 'Gerçek mülakat sorularıyla prova yap, cevapların için kişisel geri bildirim al.',
        focus: [PremiumFeature.interviewRehearsal, PremiumFeature.aiConversation, PremiumFeature.whyWrong],
        outcomes: [
          'İlk provan ücretsiz, sonra istediğin kadar prova',
          'Her cevabın için ne iyi, ne eksik: kişisel geri bildirim',
        ],
      );
    case GoalKind.speaking:
      return const GoalPaywallCopy(
        title: 'Konuşarak öğren: her gün sınırsız sohbet',
        subtitle: 'Seyahatte ve günlük hayatta rahat konuş; hatalarını anında Türkçe düzeltelim.',
        focus: [PremiumFeature.aiConversation, PremiumFeature.pronunciationScore],
        outcomes: [
          'Otelde, restoranda, yolda: her senaryoda serbest konuşma',
          'Hangi kelimeyi zor söylediğini ve doğrusunu duy',
        ],
      );
    case GoalKind.general || null:
      return GoalPaywallCopy(
        title: variantB ? 'Konuşarak öğren, sınırsız deneme çöz' : 'Daha fazla konuş, daha çok deneme çöz',
        subtitle: 'Temel öğrenme her zaman ücretsiz. Premium, maliyeti yüksek ekstraları açar.',
        focus: const [],
      );
  }
}

/// Turkish suffix after YÖKDİL is "'e" (YÖKDİL'e), not "'ye".
String _yokdilSuffix(String text, GoalExam exam) =>
    exam == GoalExam.yokdil ? text.replaceAll("YÖKDİL'ye", "YÖKDİL'e") : text;
