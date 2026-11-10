/// Lingora Premium subscription products.
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

  /// Personal plans shown as choices on the paywall (the family plan has its
  /// own card).
  static const personal = [monthly, yearly];

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
    summary: '3 tam deneme · 80 soru · 180 dakika',
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

/// What Premium unlocks. Everything else in the app is free.
enum PremiumFeature {
  aiConversation(
    'Yapay zekâ sohbet partneri',
    'Gerçek bir yapay zekâyla, her senaryoda sınırsız ve serbest konuşma; anında Türkçe düzeltme.',
    '🤖',
  ),
  unlimitedMockExams(
    'Sınırsız deneme sınavı',
    'Sınırsız mini deneme ve tüm tam deneme paketleri (YDS/YÖKDİL 3×80, LGS 4×10 soru).',
    '📝',
  ),
  errorAnalytics(
    'Detaylı hata analizi',
    'Türk hata dedektörünün tüm kategorileri: oranlar, sayılar ve her biri için çalışma ipucu.',
    '📊',
  ),
  cloudBackup(
    'Bulut yedekleme ve cihazlar arası senkron',
    'İlerlemen buluta yedeklenir; telefon değiştirsen de aynı hesapla kaldığın yerden devam edersin.',
    '☁️',
  );

  const PremiumFeature(this.title, this.description, this.emoji);
  final String title;
  final String description;
  final String emoji;
}

/// Free mini mock exams per day (all exams together) without Premium.
const freeMockExamsPerDay = 1;
