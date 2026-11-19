import '../data/scenarios.dart';
import '../goals/learn_goal.dart';

/// Neural voices of the Premium voice chat (Google Cloud TTS Chirp 3 HD). Ids
/// must match `VOICES` in functions/src/talk_context.ts.
class NeuralVoice {
  const NeuralVoice(this.id, this.name, this.accent, {required this.female});
  final String id;
  final String name;

  /// "ABD" or "İngiliz".
  final String accent;
  final bool female;

  String get label => '$name · $accent ${female ? 'kadın' : 'erkek'}';
  bool get british => id.startsWith('gb_');
}

const neuralVoices = [
  NeuralVoice('us_aoede', 'Aoede', 'ABD', female: true),
  NeuralVoice('us_kore', 'Kore', 'ABD', female: true),
  NeuralVoice('us_charon', 'Charon', 'ABD', female: false),
  NeuralVoice('us_puck', 'Puck', 'ABD', female: false),
  NeuralVoice('gb_leda', 'Leda', 'İngiliz', female: true),
  NeuralVoice('gb_zephyr', 'Zephyr', 'İngiliz', female: true),
  NeuralVoice('gb_fenrir', 'Fenrir', 'İngiliz', female: false),
  NeuralVoice('gb_orus', 'Orus', 'İngiliz', female: false),
];

const defaultVoiceId = 'us_aoede';

NeuralVoice voiceById(String? id) => neuralVoices.where((v) => v.id == id).firstOrNull ?? neuralVoices.first;

/// A conversation partner with their own voice, manner and opening line.
/// Original Dilmaç characters; the server keeps the prompt for each id
/// (`CHARACTERS` in functions/src/talk_context.ts).
class Character {
  const Character({
    required this.id,
    required this.name,
    required this.role,
    required this.emoji,
    required this.voice,
    required this.opening,
    required this.openingTr,
    required this.callOpening,
    this.goal,
  });
  final String id;
  final String name;

  /// Who they are, in Turkish ("Londra'da taksici").
  final String role;
  final String emoji;
  final String voice;
  final String opening;
  final String openingTr;

  /// First line when they call (phone-call mode).
  final String callOpening;

  /// The goal this character suits best (suggested first for that goal).
  final GoalKind? goal;
}

const characters = [
  Character(
    id: 'emma',
    name: 'Emma',
    role: 'Kafedeki arkadaşın',
    emoji: '☕',
    voice: 'us_aoede',
    opening: "Hey! So good to see you. How's your week been?",
    openingTr: 'Selam! Seni görmek çok güzel. Haftan nasıl geçti?',
    callOpening: "Hey, it's Emma! Do you have a few minutes to chat?",
  ),
  Character(
    id: 'taxi_london',
    name: 'Alfie',
    role: "Londra'da taksici",
    emoji: '🚕',
    voice: 'gb_fenrir',
    opening: 'Evening! Hop in, mate. Where are we heading?',
    openingTr: 'İyi akşamlar! Atla dostum. Nereye gidiyoruz?',
    callOpening: "Hello, it's Alfie from the cab company. Where can I pick you up?",
    goal: GoalKind.speaking,
  ),
  Character(
    id: 'barista_nyc',
    name: 'Maya',
    role: "New York'ta barista",
    emoji: '🗽',
    voice: 'us_kore',
    opening: 'Hey, welcome in! What can I get started for you today?',
    openingTr: 'Selam, hoş geldin! Bugün sana ne hazırlayayım?',
    callOpening: "Hi, it's Maya from the coffee shop! Do you want to order ahead?",
    goal: GoalKind.speaking,
  ),
  Character(
    id: 'hr_manager',
    name: 'Daniel Reed',
    role: 'Amerikalı İK müdürü',
    emoji: '💼',
    voice: 'us_charon',
    opening: 'Hi, thanks for coming in today. Please, have a seat. How are you doing?',
    openingTr: 'Merhaba, bugün geldiğiniz için teşekkürler. Lütfen oturun. Nasılsınız?',
    callOpening: "Hello, this is Daniel Reed from HR. Is now a good time for a quick interview?",
    goal: GoalKind.interview,
  ),
  Character(
    id: 'lecturer',
    name: 'Dr. Eleanor Hughes',
    role: 'İngiliz üniversite hocası',
    emoji: '🎓',
    voice: 'gb_leda',
    opening: "Good afternoon. I've just read a fascinating article about sleep and memory. Do you sleep well before exams?",
    openingTr:
        'İyi günler. Uyku ve hafıza üzerine çok ilginç bir makale okudum. Sınavlardan önce iyi uyur musun?',
    callOpening: 'Hello, Eleanor Hughes speaking. Have you got a moment to discuss your reading?',
    goal: GoalKind.exam,
  ),
  Character(
    id: 'hostel_zoe',
    name: 'Zoe',
    role: 'Hosteldeki gezgin',
    emoji: '🎒',
    voice: 'gb_zephyr',
    opening: "Oh hi! Are you staying here too? I've just arrived from Lisbon.",
    openingTr: 'Selam! Sen de burada mı kalıyorsun? Lizbon\'dan yeni geldim.',
    callOpening: "Hiya, it's Zoe from the hostel! Fancy grabbing dinner later?",
    goal: GoalKind.speaking,
  ),
];

Character? characterById(String? id) => characters.where((c) => c.id == id).firstOrNull;

/// The character who calls in phone-call mode by default (also the daily
/// "Emma seni arıyor" call).
const dailyCaller = 'emma';

/// A free-talk topic: what the learner sees and what the partner is told.
typedef TalkTopic = ({String emoji, String tr, String en});

const everydayTopics = <TalkTopic>[
  (emoji: '⚽', tr: 'Futbol', en: 'football'),
  (emoji: '📺', tr: 'Diziler', en: 'TV series'),
  (emoji: '🏖️', tr: 'Tatil', en: 'holidays and travel'),
  (emoji: '🍲', tr: 'Yemek', en: 'food and cooking'),
  (emoji: '🎵', tr: 'Müzik', en: 'music'),
  (emoji: '💼', tr: 'İş', en: 'work and daily routine'),
  (emoji: '🎮', tr: 'Oyunlar', en: 'video games'),
  (emoji: '📱', tr: 'Teknoloji', en: 'technology'),
];

const academicTopics = <TalkTopic>[
  (emoji: '🌍', tr: 'İklim değişikliği', en: 'climate change'),
  (emoji: '🧠', tr: 'Uyku ve hafıza', en: 'sleep and memory'),
  (emoji: '🤖', tr: 'Yapay zekâ', en: 'artificial intelligence in society'),
  (emoji: '🏫', tr: 'Eğitim', en: 'education systems'),
  (emoji: '🧬', tr: 'Sağlık ve bilim', en: 'health and medical research'),
  (emoji: '🏙️', tr: 'Şehirleşme', en: 'urbanisation'),
];

const workTopics = <TalkTopic>[
  (emoji: '🙋', tr: 'Kendini tanıt', en: 'introducing yourself in an interview'),
  (emoji: '💪', tr: 'Güçlü yönlerin', en: 'your strengths and weaknesses'),
  (emoji: '🧩', tr: 'Çözdüğün bir sorun', en: 'a problem you solved at work'),
  (emoji: '🤝', tr: 'Takım çalışması', en: 'teamwork'),
  (emoji: '🚀', tr: 'Kariyer hedeflerin', en: 'your career goals'),
  (emoji: '💬', tr: 'Maaş ve teklif', en: 'talking about a job offer'),
];

/// Topics for free talk, the learner's goal first: academic for YDS/YÖKDİL,
/// work and interview for the interview goal.
List<TalkTopic> topicsFor(GoalKind? goal) => switch (goal) {
  GoalKind.exam => [...academicTopics, ...everydayTopics.take(4)],
  GoalKind.interview => [...workTopics, ...everydayTopics.take(4)],
  _ => everydayTopics,
};

/// Characters in the order to show them: the ones that suit [goal] first.
List<Character> charactersFor(GoalKind? goal) => [
  ...characters.where((c) => goal != null && c.goal == goal),
  ...characters.where((c) => goal == null || c.goal != goal),
];

/// The server goal name for [goal] (functions/src/talk_context.ts).
String goalApiName(GoalKind? goal) => goal?.name ?? 'general';

/// A free-talk "scenario": no scene, a topic chosen by the learner.
Scenario freeTalkScenario(String topic) => Scenario(
  id: 'free',
  title: 'Serbest sohbet',
  emoji: '🗣️',
  goal: topic.isEmpty ? 'İstediğin konuda sohbet et.' : 'Konu: $topic',
  partner: 'Sam, sohbet arkadaşın',
  opening: topic.isEmpty
      ? "Hi! I'm Sam. What would you like to talk about today?"
      : "Hi! I'm Sam. So, let's talk about ${_topicEn(topic)}. What do you think about it?",
  openingTr: topic.isEmpty
      ? 'Selam! Ben Sam. Bugün ne hakkında konuşmak istersin?'
      : 'Selam! Ben Sam. Hadi bu konuyu konuşalım.',
  level: 'B1',
  apiFields: {'mode': 'free', 'topic': _topicEn(topic)},
);

/// A character "scenario" ([call]: they phone the learner).
Scenario characterScenario(Character c, {bool call = false, String topic = ''}) => Scenario(
  id: 'char_${c.id}',
  title: '${c.name} · ${c.role}',
  emoji: c.emoji,
  goal: 'Doğal bir sohbet: ${c.role} ile konuş.',
  partner: c.name,
  opening: call ? c.callOpening : c.opening,
  openingTr: c.openingTr,
  level: 'B1',
  apiFields: {'characterId': c.id, if (topic.isNotEmpty) 'topic': topic},
);

/// The English topic for a Turkish label from the lists, or the text itself.
String _topicEn(String topic) =>
    [...everydayTopics, ...academicTopics, ...workTopics].where((t) => t.tr == topic).firstOrNull?.en ??
    topic;

/// Short backchannels a listener says while thinking ("Mm-hm."). Neutral, so
/// they fit good and bad news alike.
const backchannels = ['Mm-hm.', 'Right…', 'Okay.', 'I see.', 'Hmm.', 'Ah, okay.'];

/// The backchannels for a partner: the neutral ones plus a character's own.
List<String> backchannelsFor(Character? c) => [
  ...backchannels,
  ...switch (c?.id) {
    'taxi_london' => const ['Right, mate.'],
    'hostel_zoe' => const ['Oh, right.'],
    'hr_manager' || 'lecturer' => const ['Mm, interesting.'],
    _ => const <String>[],
  },
];
