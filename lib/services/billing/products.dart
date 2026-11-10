/// Lingora Premium subscription products.
///
/// The ids must match the subscription product ids created in Google Play
/// Console (Monetize > Products > Subscriptions); each one has a single,
/// auto-renewing base plan. Real prices are set in Play Console; the values
/// below are only the suggested Turkish prices documented in docs/abonelik.md
/// and are never shown to the user as an offer.
enum PremiumPlan {
  monthly(id: 'lingora_premium_monthly', label: 'Aylık', period: 'ay', suggestedPriceTl: 129.99, days: 31),
  yearly(id: 'lingora_premium_yearly', label: 'Yıllık', period: 'yıl', suggestedPriceTl: 799.99, days: 366);

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
    'Günde 1 ücretsiz denemenin ötesinde istediğin kadar süreli YDS/YÖKDİL ve LGS denemesi.',
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
