import 'scenarios.dart';

/// A phrase worth using in a scenario, with its Turkish meaning.
typedef UsefulPhrase = ({String en, String tr});

/// Yazılımcı İngilizcesi scenarios: free guided writing practice with a
/// model answer and the Türk hata dedektörü, plus a live AI role-play
/// (Premium) through the same conversation service as the other scenarios.
class DevScenario {
  const DevScenario({
    required this.scenario,
    required this.task,
    required this.phrases,
    required this.checklist,
    required this.modelAnswer,
    required this.modelAnswerTr,
    this.placeholder = '',
  });

  /// Role-play data; its id is also known by the server
  /// (functions/src/scenarios.ts).
  final Scenario scenario;

  /// What to write, in Turkish.
  final String task;
  final List<UsefulPhrase> phrases;

  /// Things a good answer contains: a Turkish label and the English words
  /// (any of them, case-insensitive) that show it is there.
  final List<({String label, List<String> any})> checklist;
  final String modelAnswer;
  final String modelAnswerTr;
  final String placeholder;

  String get id => scenario.id;

  /// Checklist labels and whether [text] covers each.
  List<(String, bool)> review(String text) {
    final lower = text.toLowerCase();
    return [for (final c in checklist) (c.label, c.any.any((w) => lower.contains(w.toLowerCase())))];
  }
}

const devScenarios = [
  DevScenario(
    scenario: Scenario(
      id: 'dev_standup',
      title: 'Günlük stand-up',
      emoji: '🧍',
      goal: 'Dün ne yaptığını, bugün ne yapacağını ve bir engelin olup olmadığını kısaca anlat.',
      partner: 'Takım lideri',
      opening: "Morning, everyone! Let's keep it short today. What did you work on yesterday?",
      openingTr: 'Herkese günaydın! Bugün kısa tutalım. Dün ne üzerinde çalıştın?',
      level: 'B1',
    ),
    task: 'Stand-up için 3–4 cümlelik bir güncelleme yaz: dün, bugün, engel.',
    phrases: [
      (en: 'Yesterday I finished ...', tr: 'Dün ... bitirdim'),
      (en: 'Today I am going to work on ...', tr: 'Bugün ... üzerinde çalışacağım'),
      (en: "I'm blocked by ...", tr: '... yüzünden ilerleyemiyorum'),
      (en: 'No blockers for now.', tr: 'Şimdilik engel yok.'),
    ],
    checklist: [
      (label: 'Dün ne yaptın', any: ['yesterday']),
      (label: 'Bugünkü plan', any: ['today', 'going to', "i'll", 'i will']),
      (label: 'Engel var mı', any: ['block', 'no blockers', 'stuck', 'waiting']),
    ],
    modelAnswer:
        'Yesterday I finished the login screen and opened a pull request. '
        'Today I am going to fix the review comments and start on the password reset flow. '
        "I'm blocked by the missing API key for the email service, so I'll ping Mert after the meeting.",
    modelAnswerTr:
        'Dün giriş ekranını bitirdim ve bir pull request açtım. Bugün inceleme yorumlarını düzeltip şifre '
        'sıfırlama akışına başlayacağım. E-posta servisinin API anahtarı eksik olduğu için ilerleyemiyorum, '
        'toplantıdan sonra Mert\'e yazacağım.',
    placeholder: 'Yesterday I ...',
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_code_review',
      title: 'Kod incelemesi yorumu',
      emoji: '🔍',
      goal: 'Bir PR\'daki soruna kibarca dikkat çek, nedenini açıkla ve bir öneri sun.',
      partner: 'PR\'ı açan takım arkadaşı',
      opening: 'Hey, thanks for reviewing my PR! Did you spot anything I should change?',
      openingTr: 'Selam, PR\'ımı incelediğin için teşekkürler! Değiştirmem gereken bir şey gördün mü?',
      level: 'B1',
    ),
    task:
        'Bir arkadaşının PR\'ında her istekte veritabanına yeniden bağlanıldığını gördün. Kibar bir inceleme '
        'yorumu yaz: sorunu, nedenini ve önerini söyle.',
    phrases: [
      (en: 'Nice work overall!', tr: 'Genel olarak güzel iş!'),
      (en: 'Could we ...?', tr: '... yapabilir miyiz?'),
      (en: 'What do you think about ...?', tr: '... hakkında ne düşünüyorsun?'),
      (en: 'nit:', tr: 'küçük, önemsiz not'),
    ],
    checklist: [
      (label: 'Kibar başlangıç', any: ['thanks', 'nice', 'great', 'looks good']),
      (label: 'Sorunu söyle', any: ['connect', 'connection', 'each request', 'every request']),
      (label: 'Neden önemli', any: ['because', 'slow', 'performance', 'expensive']),
      (label: 'Öneri sun', any: ['could we', 'what do you think', 'suggest', 'maybe', 'how about']),
    ],
    modelAnswer:
        'Nice work overall! One thing: we open a new database connection on every request here. '
        'This could get slow under load because connections are expensive. '
        'Could we reuse a single connection pool instead? Happy to pair on it if you like.',
    modelAnswerTr:
        'Genel olarak güzel iş! Bir şey var: burada her istekte yeni bir veritabanı bağlantısı açıyoruz. '
        'Bağlantılar maliyetli olduğu için yük altında yavaşlayabilir. Bunun yerine tek bir bağlantı havuzunu '
        'yeniden kullanabilir miyiz? İstersen birlikte bakabiliriz.',
    placeholder: 'Nice work! One thing ...',
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_bug_ticket',
      title: 'Hatayı iş kaydında anlat',
      emoji: '🐞',
      goal: 'Hatayı adım adım tarif et: nasıl tekrar edilir, ne bekleniyordu, ne oldu.',
      partner: 'Kaydı okuyan QA mühendisi',
      opening: "Hi! I saw your new ticket about the checkout page. Can you tell me how to reproduce it?",
      openingTr:
          'Selam! Ödeme sayfasıyla ilgili yeni kaydını gördüm. Nasıl tekrar edebileceğimi anlatır mısın?',
      level: 'B1',
    ),
    task:
        'Ödeme sayfasında kupon kodu girince sepet tutarı sıfırlanıyor. Bir iş kaydı (ticket) yaz: adımlar, '
        'beklenen sonuç, gerçekleşen sonuç.',
    phrases: [
      (en: 'Steps to reproduce:', tr: 'Tekrar etme adımları:'),
      (en: 'Expected result:', tr: 'Beklenen sonuç:'),
      (en: 'Actual result:', tr: 'Gerçekleşen sonuç:'),
      (en: 'It happens every time / only sometimes.', tr: 'Her seferinde / yalnızca bazen oluyor.'),
    ],
    checklist: [
      (label: 'Adımlar', any: ['steps', '1.', 'first', 'go to', 'open']),
      (label: 'Beklenen sonuç', any: ['expected', 'should']),
      (label: 'Gerçekleşen sonuç', any: ['actual', 'instead', 'but']),
      (
        label: 'Ortam / sıklık',
        any: ['every time', 'always', 'sometimes', 'browser', 'version', 'android', 'ios'],
      ),
    ],
    modelAnswer:
        'Steps to reproduce: 1. Add two items to the cart. 2. Go to the checkout page. '
        '3. Enter the coupon code SAVE10 and tap Apply. '
        'Expected result: the total should drop by 10%. '
        'Actual result: the total becomes 0.00 and the Pay button is disabled. '
        'It happens every time on Android 14, app version 2.3.1.',
    modelAnswerTr:
        'Tekrar etme adımları: 1. Sepete iki ürün ekle. 2. Ödeme sayfasına git. 3. SAVE10 kupon kodunu gir ve '
        'Uygula\'ya dokun. Beklenen sonuç: toplam %10 düşmeli. Gerçekleşen sonuç: toplam 0,00 oluyor ve Öde '
        'düğmesi devre dışı kalıyor. Android 14, uygulama sürümü 2.3.1\'de her seferinde oluyor.',
    placeholder: 'Steps to reproduce: ...',
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_commit',
      title: 'Commit mesajı yaz',
      emoji: '📌',
      goal: 'Değişikliği kısa ve emir kipinde özetle, gerekirse nedenini açıkla.',
      partner: 'Commit geçmişini okuyan kıdemli geliştirici',
      opening: "I'm going through the git log. What does your last commit change, and why?",
      openingTr: 'Git geçmişine bakıyorum. Son commit\'in neyi değiştiriyor ve neden?',
      level: 'B1',
    ),
    task:
        'Profil fotoğrafı yüklenirken uygulamanın çökmesine yol açan null kontrolünü düzelttin. Bir commit '
        'mesajı yaz: emir kipinde kısa bir başlık (en fazla ~50 karakter) ve bir cümlelik açıklama.',
    phrases: [
      (en: 'Fix crash when ...', tr: '... olduğunda oluşan çökmeyi düzelt'),
      (en: 'Add / Remove / Update ...', tr: 'Ekle / Kaldır / Güncelle ...'),
      (en: 'Handle null ... in ...', tr: '... içindeki null ...\'ı ele al'),
    ],
    checklist: [
      (
        label: 'Emir kipiyle başla (Fix/Add…)',
        any: ['fix ', 'add ', 'handle ', 'prevent ', 'update ', 'remove '],
      ),
      (label: 'Ne düzeldi', any: ['crash', 'null']),
      (label: 'Nerede', any: ['profile', 'photo', 'upload', 'avatar']),
    ],
    modelAnswer:
        'Fix crash when uploading a profile photo\n\n'
        'The image picker returns null when the user cancels, so check the result before resizing it.',
    modelAnswerTr:
        'Profil fotoğrafı yüklerken oluşan çökmeyi düzelt\n\nKullanıcı vazgeçince görsel seçici null döndürüyor; '
        'bu yüzden yeniden boyutlandırmadan önce sonucu kontrol et.',
    placeholder: 'Fix ...',
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_pr_description',
      title: 'PR açıklaması yaz',
      emoji: '📝',
      goal: 'PR\'ın ne yaptığını, nedenini ve nasıl test edileceğini anlat.',
      partner: 'PR\'ı inceleyecek takım arkadaşı',
      opening: "I've been assigned to review your PR. Can you give me a quick summary first?",
      openingTr: 'PR\'ını incelemem istendi. Önce kısa bir özet verebilir misin?',
      level: 'B1',
    ),
    task: 'Uygulamaya karanlık mod ekleyen bir PR açtın. Açıklamasını yaz: ne değişti, neden, nasıl test edilir.',
    phrases: [
      (en: 'This PR adds ...', tr: 'Bu PR ... ekliyor'),
      (en: 'Why: ...', tr: 'Neden: ...'),
      (en: 'How to test: ...', tr: 'Nasıl test edilir: ...'),
      (en: 'Out of scope: ...', tr: 'Kapsam dışı: ...'),
    ],
    checklist: [
      (label: 'Ne değişti', any: ['this pr', 'adds', 'changes', 'introduces']),
      (label: 'Neden', any: ['why', 'because', 'users asked', 'so that']),
      (label: 'Nasıl test edilir', any: ['test', 'verify', 'check']),
    ],
    modelAnswer:
        'This PR adds dark mode to the app. '
        'Why: many users asked for it, and it saves battery on OLED screens. '
        'How to test: switch your phone to dark mode and open the home, lesson and profile screens. '
        'Out of scope: custom colour themes will come in a follow-up PR.',
    modelAnswerTr:
        'Bu PR uygulamaya karanlık mod ekliyor. Neden: birçok kullanıcı istedi ve OLED ekranlarda pil tasarrufu '
        'sağlıyor. Nasıl test edilir: telefonunu karanlık moda al, ana sayfa, ders ve profil ekranlarını aç. '
        'Kapsam dışı: özel renk temaları sonraki bir PR\'da gelecek.',
    placeholder: 'This PR adds ...',
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_team_chat',
      title: 'Takım sohbetinde soru sor',
      emoji: '💬',
      goal: 'Bağlamı ver, ne denediğini söyle ve net bir soru sor.',
      partner: 'Slack\'te yardım eden backend geliştiricisi',
      opening: 'Hey! I saw you were typing in the backend channel. What do you need?',
      openingTr: 'Selam! Backend kanalında yazdığını gördüm. Neye ihtiyacın var?',
      level: 'B1',
    ),
    task:
        'Test ortamındaki /orders uç noktası 401 döndürüyor. Backend kanalına bir mesaj yaz: bağlam, ne '
        'denedin, net soru.',
    phrases: [
      (en: 'Quick question about ...', tr: '... hakkında kısa bir soru'),
      (en: "I've already tried ...", tr: '... denedim bile'),
      (en: 'Am I missing something?', tr: 'Bir şeyi mi atlıyorum?'),
      (en: 'No rush.', tr: 'Acelesi yok.'),
    ],
    checklist: [
      (label: 'Bağlam', any: ['staging', 'endpoint', '/orders', 'quick question']),
      (label: 'Ne denedin', any: ['tried', 'checked']),
      (label: 'Net soru', any: ['?']),
    ],
    modelAnswer:
        'Hi team, quick question about the /orders endpoint on staging. It returns 401 for my test user. '
        "I've already tried a fresh token and checked the user's role. "
        'Is there a new permission I need to add? No rush, thanks!',
    modelAnswerTr:
        'Selam ekip, test ortamındaki /orders uç noktasıyla ilgili kısa bir soru. Test kullanıcım için 401 '
        'döndürüyor. Yeni bir token denedim ve kullanıcının rolünü kontrol ettim. Eklemem gereken yeni bir yetki '
        'var mı? Acelesi yok, teşekkürler!',
    placeholder: 'Hi team, quick question about ...',
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_interview_intro',
      title: 'Teknik mülakatta kendini tanıt',
      emoji: '🎤',
      goal: 'Deneyimini, teknolojilerini ve gurur duyduğun bir projeyi anlat.',
      partner: 'Mühendislik müdürü',
      opening: "Thanks for joining. To start, could you walk me through your background?",
      openingTr: 'Katıldığın için teşekkürler. Başlamak için bize geçmişini anlatır mısın?',
      level: 'B1',
    ),
    task:
        'Teknik mülakatın başında kendini 4–5 cümleyle tanıt: deneyim süresi, teknolojiler, öne çıkan bir proje, '
        'neden bu pozisyon.',
    phrases: [
      (en: "I've been working as a ... for ... years.", tr: '... yıldır ... olarak çalışıyorum.'),
      (en: 'I mostly work with ...', tr: 'Çoğunlukla ... ile çalışıyorum.'),
      (en: "One project I'm proud of is ...", tr: 'Gurur duyduğum projelerden biri ...'),
      (en: "I'm excited about this role because ...", tr: 'Bu pozisyon beni heyecanlandırıyor çünkü ...'),
    ],
    checklist: [
      (label: 'Deneyim süresi', any: ['years', 'year']),
      (label: 'Teknolojiler', any: ['work with', 'flutter', 'kotlin', 'react', 'python', 'java', 'stack']),
      (label: 'Bir proje', any: ['project', 'built', 'led']),
      (label: 'Neden bu pozisyon', any: ['because', 'excited', 'interested']),
    ],
    modelAnswer:
        "I've been working as a mobile developer for four years. "
        'I mostly work with Flutter and Kotlin, and I also write some backend code in Node.js. '
        "One project I'm proud of is a delivery app where I cut the startup time by forty percent. "
        "I'm excited about this role because I want to work on a product with millions of users.",
    modelAnswerTr:
        'Dört yıldır mobil geliştirici olarak çalışıyorum. Çoğunlukla Flutter ve Kotlin ile çalışıyorum, biraz '
        'da Node.js ile backend kodu yazıyorum. Gurur duyduğum projelerden biri, açılış süresini yüzde kırk '
        'azalttığım bir teslimat uygulaması. Bu pozisyon beni heyecanlandırıyor çünkü milyonlarca kullanıcısı '
        'olan bir ürün üzerinde çalışmak istiyorum.',
    placeholder: "I've been working as ...",
  ),
  DevScenario(
    scenario: Scenario(
      id: 'dev_estimate',
      title: 'Bir işi tahminle',
      emoji: '⏱️',
      goal: 'Süre tahmini ver, varsayımlarını ve riskleri söyle.',
      partner: 'Ürün yöneticisi',
      opening: 'We need push notifications for the next release. How long do you think it will take?',
      openingTr: 'Bir sonraki sürüm için anlık bildirimlere ihtiyacımız var. Sence ne kadar sürer?',
      level: 'B1',
    ),
    task:
        'Ürün yöneticisi anlık bildirim özelliği için süre soruyor. Bir tahmin ver, varsayımını ve en büyük '
        'riski söyle.',
    phrases: [
      (en: 'My rough estimate is ...', tr: 'Kaba tahminim ...'),
      (en: 'assuming that ...', tr: '... varsayımıyla'),
      (en: 'The main risk is ...', tr: 'Asıl risk ...'),
      (en: "I'll update you if ...", tr: '... olursa sana haber veririm'),
    ],
    checklist: [
      (label: 'Süre tahmini', any: ['day', 'days', 'week', 'weeks', 'hours', 'sprint']),
      (label: 'Varsayım', any: ['assuming', 'if ', 'as long as']),
      (label: 'Risk', any: ['risk', 'might', 'could', 'depends']),
    ],
    modelAnswer:
        'My rough estimate is about five working days, assuming the backend team can send the notifications '
        'for us. The main risk is the iOS permission flow, which might need extra testing. '
        "I'll update you on Wednesday if anything changes.",
    modelAnswerTr:
        'Kaba tahminim yaklaşık beş iş günü; backend ekibinin bildirimleri bizim için gönderebileceğini '
        'varsayıyorum. Asıl risk, ek test gerektirebilecek iOS izin akışı. Bir şey değişirse çarşamba günü '
        'sana haber veririm.',
    placeholder: 'My rough estimate is ...',
  ),
];

DevScenario devScenarioById(String id) => devScenarios.firstWhere((s) => s.id == id);
