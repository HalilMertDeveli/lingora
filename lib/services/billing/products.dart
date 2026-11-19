import '../../core/emoji_compat.dart';

/// Dilmaç Premium subscription products.
///
/// The ids must match the subscription product ids created in Google Play
/// Console (Monetize > Products > Subscriptions); each one has a single,
/// auto-renewing base plan. Real prices are set in Play Console; the values
/// below are only the suggested Turkish prices documented in docs/abonelik.md
/// and are never shown to the user as an offer.

enum PremiumPlan {
  monthly(id: 'lingora_premium_monthly', label: 'Aylık', period: 'ay', suggestedPriceTl: 129.99, days: 31),
  yearly(id: 'lingora_premium_yearly', label: 'Yıllık', period: 'yıl', suggestedPriceTl: 799.99, days: 366),

  /// Family plan: the buyer plus up to [familySeats] - 1 people they invite
  /// with a code (needs the Firebase backend, see docs/abonelik.md).
  familyYearly(
    id: 'lingora_premium_family_yearly',
    label: 'Aile',
    period: 'yıl',
    suggestedPriceTl: 1199.99,
    days: 366,
  );

  const PremiumPlan({
    required this.id,
    required this.label,
    required this.period,
    required this.suggestedPriceTl,
    required this.days,
  });

  /// Play Console product id.
  final String id;

  /// Turkish plan name shown on the paywall.
  final String label;

  /// Billing period word: "ay" / "yıl".
  final String period;

  /// Suggested price in TL (documentation only).
  final double suggestedPriceTl;

  /// Length of one billing period, used to bound the offline cache.
  final int days;

  static PremiumPlan? byId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }

  static Set<String> get ids => {for (final p in values) p.id};

  /// Personal plans shown as choices on the paywall, in order (the family
  /// plan has its own card). Yearly comes first and is preselected: the
  /// subscription is Dilmaç's main revenue and yearly is the best value.
  static const personal = [yearly, monthly];

  /// Preselected on the paywall.
  static const recommended = yearly;

  bool get isFamily => this == familyYearly;
}

/// People in a family plan, the buyer included.
const familySeats = 5;

/// One-time exam packs (Google Play in-app products, non-consumable).
/// Owning one unlocks the full-length mock exams of that exam for good;
/// Premium unlocks them too.
enum ExamPack {
  yds(
    id: 'lingora_pack_yds_full',
    examId: 'yds',
    title: 'YDS/YÖKDİL Tam Deneme Paketi',
    summary: '8 tam deneme · 80 soru · 180 dakika',
    suggestedPriceTl: 149.99,
  ),
  lgs(
    id: 'lingora_pack_lgs_full',
    examId: 'lgs',
    title: 'LGS İngilizce Tam Deneme Paketi',
    summary: '4 tam deneme · 10 soru · 15 dakika',
    suggestedPriceTl: 99.99,
  );

  const ExamPack({
    required this.id,
    required this.examId,
    required this.title,
    required this.summary,
    required this.suggestedPriceTl,
  });

  /// Play Console product id.
  final String id;

  /// Exam track (`assets/exams/<examId>.json`) and key in the server
  /// entitlement's `packs` map.
  final String examId;
  final String title;
  final String summary;

  /// Suggested price in TL (documentation only).
  final double suggestedPriceTl;

  /// Content asset with the full mock exams.
  String get asset => 'assets/exam_packs/${examId}_full.json';

  static ExamPack? byId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ExamPack? forExam(String examId) {
    for (final p in values) {
      if (p.examId == examId) return p;
    }
    return null;
  }

  static Set<String> get ids => {for (final p in values) p.id};
}

/// What Premium unlocks. Everything else in the app is free (cloud backup
/// included: every signed-in user's progress is synced, see `freeItems`).
enum PremiumFeature {
  aiConversation(
    'Yapay zekâ sohbet partneri',
    'Gerçek bir yapay zekâyla, her senaryoda sınırsız ve serbest konuşma; anında Türkçe düzeltme.',
    '🤖',
  ),
  interviewRehearsal(
    'Mülakat provası',
    'Kendi cevabından günlük çalışma, hiç sorulmamış sorularla yeni mülakatlar ve ilk ↔ son kaydını yan yana dinleme. İlk provan ücretsiz.',
    '💼',
  ),
  whyWrong(
    '"Neden yanlış?" açıklamaları',
    'Her yanlış cevabın açıklaması: şıkların Türkçesi ve neden olmadıkları. Ücretsiz sürümde günde 3.',
    '💡',
  ),
  unlimitedMockExams(
    'Sınırsız deneme',
    'Sınırsız mini deneme ve tüm tam deneme paketleri (YDS/YÖKDİL 8×80, LGS 4×10 soru).',
    '📝',
  ),
  errorAnalytics(
    'Detaylı hata analizi ve tahmini puan',
    'Zayıf konuların ve soru tiplerin, haftalık gidişatın, kendi cümlelerinle Türk hata kalıpların, '
        'ısı haritası, tahmini sınav puanı ve tek dokunuşla hedefli alıştırmalı çalışma planı.',
    '📊',
  ),
  streakFreezes(
    'Ayda 2 seri dondurma',
    'Her ay cüzdanına kendiliğinden 2 seri dondurma eklenir; bir gün çalışamazsan serin korunur.',
    '🧊',
  ),
  doubleGold('2 kat altın', 'Ders, görev, lig ve seri ödüllerinde kazandığın her altın iki katı.', '🪙'),
  premiumAvatars(
    'Premium avatarlar',
    "Mağaza'da yalnızca Premium'a özel avatar ve hareketli çerçeveler.",
    '🦅',
  ),
  levelReport(
    'Aylık seviye karnesi',
    'Ay ay seviye grafiğin, beceri gidişatın ve sonraki ay için mevcut derslerden çalışma önerileri.',
    '📈',
  );

  const PremiumFeature(this.title, this.description, this._emoji);
  final String title;
  final String description;
  final String _emoji;

  /// Safe on Android 7–9 (see emoji_compat.dart).
  String get emoji => legacyEmoji(_emoji);
}

/// Free mini mock exams per day (all exams together) without Premium.
const freeMockExamsPerDay = 1;

/// `productId` of an entitlement granted by the invite programme
/// (functions/src/referral.ts), not a store product.
const referralProductId = 'referral';
