/// Role-play scenarios for conversation practice. The server keeps its own
/// prompt for each id (functions/src/scenarios.ts), so
/// the app can never change what the AI is told.
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.emoji,
    required this.goal,
    required this.partner,
    required this.opening,
    required this.openingTr,
    this.level = 'A2',
  });

  final String id;
  final String title;
  final String emoji;

  /// What the learner should achieve, in Turkish.
  final String goal;

  /// Who the AI plays, in Turkish.
  final String partner;

  /// First line from the AI partner.
  final String opening;
  final String openingTr;
  final String level;
}

const scenarios = [
  Scenario(
    id: 'cafe',
    title: 'Kafede sipariş',
    emoji: '☕',
    goal: 'Bir içecek ve bir yiyecek sipariş et, fiyatı sor.',
    partner: 'Garson',
    opening: 'Hi there! Welcome to Sunny Café. What can I get for you today?',
    openingTr: 'Merhaba! Sunny Café\'ye hoş geldiniz. Bugün size ne getireyim?',
    level: 'A1',
  ),
  Scenario(
    id: 'hotel_checkin',
    title: 'Otelde check-in',
    emoji: '🏨',
    goal: 'Resepsiyon görevlisi sensin: misafiri karşıla, pasaportunu iste, oda bilgisi ver.',
    partner: 'Otel misafiri',
    opening: 'Good evening. I have a reservation under the name Miller.',
    openingTr: 'İyi akşamlar. Miller adına bir rezervasyonum var.',
  ),
  Scenario(
    id: 'restaurant_guest',
    title: 'Restoranda misafir',
    emoji: '🍽️',
    goal: 'Garson sensin: menüyü öner, alerji sorusunu yanıtla, siparişi al.',
    partner: 'Restoran müşterisi',
    opening: 'Hello! Could we see the menu, please? And is the fish fresh today?',
    openingTr: 'Merhaba! Menüyü görebilir miyiz? Balık bugün taze mi?',
  ),
  Scenario(
    id: 'directions',
    title: 'Yol tarifi',
    emoji: '🗺️',
    goal: 'Turiste müzeye nasıl gideceğini anlat.',
    partner: 'Kaybolmuş turist',
    opening: 'Excuse me, sorry to bother you. How can I get to the museum from here?',
    openingTr: 'Affedersiniz, rahatsız ediyorum. Buradan müzeye nasıl gidebilirim?',
  ),
  Scenario(
    id: 'interview',
    title: 'İş görüşmesi',
    emoji: '💼',
    goal: 'Kendini tanıt, deneyimini anlat, bir soru sor.',
    partner: 'İşe alım uzmanı',
    opening: 'Thanks for coming in today. Could you start by telling me a little about yourself?',
    openingTr: 'Bugün geldiğiniz için teşekkürler. Bize biraz kendinizden bahseder misiniz?',
    level: 'B1',
  ),
  Scenario(
    id: 'doctor',
    title: 'Doktorda',
    emoji: '🩺',
    goal: 'Şikâyetini anlat, ne zamandır sürdüğünü söyle, ilacı sor.',
    partner: 'Doktor',
    opening: 'Hello, please have a seat. What seems to be the problem today?',
    openingTr: 'Merhaba, buyurun oturun. Bugün sorun nedir?',
  ),
];

Scenario scenarioById(String id) => scenarios.firstWhere((s) => s.id == id);
