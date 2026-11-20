import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/league.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/screens/league_screen.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/league_remote.dart';
import 'package:lingora/services/showcase.dart';
import 'package:lingora/ui/country_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLeagueApi implements LeagueApi {
  FakeLeagueApi(this.rows, {this.failJoin = false, this.membersError, this.stateError, this.silent = false});
  final List<RemoteMember> rows;
  final bool failJoin;

  /// Thrown by the members stream (e.g. PERMISSION_DENIED).
  final Object? membersError;

  /// Thrown by the leagueState stream.
  final Object? stateError;

  /// The leagueState stream never answers (a slow first load).
  final bool silent;
  final _states = StreamController<WorldLeagueState?>.broadcast();
  WorldLeagueState? _last;
  final joins = <({String name, String? country, String? photo})>[];
  final looks = <Showcase?>[];
  final reports = <({int weekXp, String weekKey})>[];
  var left = 0;

  void emit(WorldLeagueState? s) {
    _last = s;
    _states.add(s);
  }

  @override
  Future<LeagueSeat> join({
    required String name,
    required String avatar,
    String? country,
    String? photo,
    Showcase? look,
  }) async {
    joins.add((name: name, country: country, photo: photo));
    looks.add(look);
    if (failJoin) throw Exception('offline');
    emit(joined);
    return const LeagueSeat(groupId: '2026-11-09_2_0', weekKey: '2026-11-09', tier: 2);
  }

  @override
  Future<XpReport> reportXp({required int weekXp, required String weekKey}) async {
    reports.add((weekXp: weekXp, weekKey: weekKey));
    return XpReport(xp: weekXp, pending: 0);
  }

  @override
  Future<void> leave() async => left++;

  @override
  Stream<List<RemoteMember>> members(String groupId) =>
      membersError == null ? Stream.value(rows) : Stream.error(membersError!);

  @override
  Stream<WorldLeagueState?> state(String uid) async* {
    if (stateError != null) throw stateError!;
    if (silent) await Completer<void>().future;
    yield _last;
    yield* _states.stream;
  }
}

// Tuesday 12:00 (Turkish time) of the week starting Monday 2026-11-09.
final now = DateTime.utc(2026, 11, 10, 9);
const joined = WorldLeagueState(tier: 2, groupId: '2026-11-09_2_0', weekKey: '2026-11-09');
const lastWeek = WorldLeagueState(tier: 2, groupId: '2026-11-02_2_0', weekKey: '2026-11-02');
const me = AppUser(uid: 'me', isAnonymous: false, displayName: 'Mert Develi');

List<Override> overrides(SharedPreferences prefs, {LeagueApi? api, AppUser? user = me, bool online = true}) =>
    [
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => now),
      leagueOnlineProvider.overrideWithValue(online),
      if (api != null) leagueApiProvider.overrideWithValue(api),
      if (user != null) authStateProvider.overrideWithValue(AsyncData(user)),
    ];

Future<ProviderContainer> container({
  LeagueApi? api,
  Progress progress = const Progress(),
  AppUser? user = me,
}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(progress.toJson()),
    'league_country_v1': 'TR',
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: overrides(prefs, api: api, user: user),
  );
}

/// A full group of 100 in which 'me' is 60th.
final hundred = [
  for (var i = 0; i < 100; i++)
    i == 59
        ? const RemoteMember(uid: 'me', name: 'Mert', avatar: '⭐', xp: 405, country: 'TR')
        : RemoteMember(
            uid: 'u$i',
            name: 'Üye $i',
            avatar: '🦊',
            xp: 1000 - i * 10,
            country: i.isEven ? 'DE' : 'TR',
          ),
];

const rows = [
  RemoteMember(uid: 'a', name: 'Ayşe', avatar: '🦊', xp: 120, country: 'AZ'),
  RemoteMember(uid: 'me', name: 'Mert', avatar: '⭐', xp: 40, country: 'TR'),
  RemoteMember(uid: 'b', name: 'Burak', avatar: '🐼', xp: 300, country: 'DE'),
];

Future<void> pumpLeague(WidgetTester tester, List<Override> o) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: o,
      child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('leagueDisplayName shows only the first name', () {
    expect(leagueDisplayName('Mert Develi'), 'Mert');
    expect(leagueDisplayName('  '), 'Çenebaz öğrencisi');
    expect(leagueDisplayName(null), 'Çenebaz öğrencisi');
  });

  test('the generic name stored before the rename shows the current one', () {
    expect(shownName('Dilmaç öğrencisi'), 'Çenebaz öğrencisi');
    expect(shownName('Zeynep'), 'Zeynep');
  });

  test('ten tiers and the same zones as the server', () {
    expect(leagueTiers.map((t) => t.name), [
      'Bronz',
      'Gümüş',
      'Altın',
      'Safir',
      'Yakut',
      'Zümrüt',
      'Ametist',
      'İnci',
      'Obsidyen',
      'Elmas',
    ]);
    expect(leagueZones(0), (promote: 15, demote: 0));
    expect(leagueZones(2), (promote: 15, demote: 5));
    expect(leagueZones(3), (promote: 10, demote: 5));
    expect(leagueZones(5), (promote: 10, demote: 10));
    expect(leagueZones(9), (promote: 0, demote: 10));
    expect(leagueZones(4, 3), (promote: 1, demote: 0));
    expect(leagueZones(6, 20), (promote: 2, demote: 2));
    expect(inPromotionZone(0, 15), isTrue);
    expect(inPromotionZone(0, 16), isFalse);
    expect(inDemotionZone(0, 100), isFalse);
    expect(inDemotionZone(5, 91), isTrue);
  });

  test('flags and the Turkish league week', () {
    expect(flagEmoji('TR'), '🇹🇷');
    expect(flagEmoji('de'), '');
    expect(flagEmoji(null), '');
    expect(trWeekKey(now), '2026-11-09');
    // Sunday 22:00 UTC is already Monday 01:00 in Türkiye.
    expect(trWeekKey(DateTime.utc(2026, 11, 15, 22)), '2026-11-16');
    expect(untilTrWeekEnd(DateTime.utc(2026, 11, 15, 20)), const Duration(hours: 1));
  });

  test('without Firebase the league is the simulated one', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: overrides(prefs, online: false, user: null));
    addTearDown(c.dispose);
    expect(await viewOf(c), isA<WorldOffline>());
  });

  test('a guest gets the preview', () async {
    final c = await container(user: const AppUser(uid: 'g'));
    addTearDown(c.dispose);
    expect(c.read(leagueApiProvider), isNull);
    expect(await viewOf(c), isA<WorldGuest>());
  });

  test('an account that never joined sees the join card', () async {
    final api = FakeLeagueApi(rows);
    final c = await container(api: api);
    addTearDown(c.dispose);
    expect(await viewOf(c), isA<WorldNeedsJoin>());
    expect(api.joins, isEmpty);
  });

  test('a member joins every week and sees the sorted group', () async {
    final api = FakeLeagueApi(rows)..emit(joined);
    final c = await container(api: api);
    addTearDown(c.dispose);
    final view = await viewOf(c);
    expect(view, isA<WorldLive>());
    final league = (view as WorldLive).league;
    expect(api.joins.single, (name: 'Mert', country: 'TR', photo: null));
    expect(league.tier, 2);
    expect(league.table.map((e) => e.name), ['Burak', 'Ayşe', 'Sen']);
    expect(league.table.last.isUser, isTrue);
    expect(league.table.first.country, 'DE');
    expect(league.countries, 3);
  });

  test('seated this week, a failed join still shows the live group', () async {
    final api = FakeLeagueApi(rows, failJoin: true)..emit(joined);
    final c = await container(api: api);
    addTearDown(c.dispose);
    final view = await viewOf(c);
    expect(view, isA<WorldLive>());
    expect((view as WorldLive).league.table.map((e) => e.name), ['Burak', 'Ayşe', 'Sen']);
    expect(api.joins, hasLength(1)); // the background refresh was tried
  });

  test('a failed join for a new week is an error, never simulated rivals', () async {
    final api = FakeLeagueApi(rows, failJoin: true)..emit(lastWeek);
    final c = await container(api: api);
    addTearDown(c.dispose);
    final view = await viewOf(c);
    expect(view, isA<WorldError>());
    expect((view as WorldError).message, contains('yeniden dene'));
  });

  test('a denied members read is an error with a Turkish message', () async {
    final api = FakeLeagueApi(
      rows,
      membersError: FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    )..emit(joined);
    final c = await container(api: api);
    addTearDown(c.dispose);
    final view = await viewOf(c);
    expect(view, isA<WorldError>());
    expect((view as WorldError).message, contains('Hesabın doğrulanamadı'));
  });

  test('a failing leagueState read is an error, not endless loading', () async {
    final api = FakeLeagueApi(
      rows,
      stateError: FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    final c = await container(api: api);
    addTearDown(c.dispose);
    final view = await viewOf(c);
    expect(view, isA<WorldError>());
    expect((view as WorldError).message, contains('İnternet bağlantısı'));
  });

  test('an XP report rewriting leagueState does not start the league over', () async {
    final api = FakeLeagueApi(rows)..emit(joined);
    final c = await container(api: api);
    addTearDown(c.dispose);
    final sub = c.listen(worldLeagueProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await c.read(worldLeagueProvider.future), isA<WorldLive>());
    // Same seat, a new object (addLeagueXp writes xpMinute, lastXpAt, ...).
    api.emit(WorldLeagueState(tier: 2, groupId: joined.groupId, weekKey: joined.weekKey));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(api.joins, hasLength(1));
    expect(c.read(worldLeagueProvider).isLoading, isFalse);
    expect(c.read(worldLeagueProvider).value, isA<WorldLive>());
  });

  test('loading and errors map to their own views', () {
    expect(worldLeagueViewOf(const AsyncLoading()), isA<WorldLoading>());
    expect(worldLeagueViewOf(const AsyncData(WorldGuest())), isA<WorldGuest>());
    expect(worldLeagueViewOf(AsyncError(Exception('x'), StackTrace.empty)), isA<WorldError>());
    expect(leagueErrorMessage(TimeoutException('slow')), contains('yanıt vermedi'));
    expect(
      leagueErrorMessage(FirebaseFunctionsException(code: 'internal', message: 'x')),
      contains('yüklenemedi'),
    );
  });

  testWidgets('XP sync reports the weekly total, or takes a seat in a new week', (tester) async {
    // 50 + 60 XP this week (Monday and Tuesday).
    const progress = Progress(xpByDay: {'2026-11-09': 50, '2026-11-10': 60});

    Future<FakeLeagueApi> run(WorldLeagueState state) async {
      final api = FakeLeagueApi(rows)..emit(state);
      final c = await container(api: api, progress: progress);
      final sub = c.listen(leagueXpSyncProvider, (_, _) {});
      await tester.pump(const Duration(seconds: 1)); // state arrives
      await tester.pump(const Duration(seconds: 4)); // debounce
      sub.close();
      c.dispose();
      return api;
    }

    final member = await run(joined);
    expect(member.reports.single, (weekXp: 110, weekKey: '2026-11-09'));
    expect(member.joins, isEmpty);

    // Last week's seat: the first XP of the week joins the new group.
    final returning = await run(const WorldLeagueState(tier: 3, weekKey: '2026-11-02'));
    expect(returning.joins, hasLength(1));

    final left = await run(const WorldLeagueState(tier: 3, optedOut: true));
    expect(left.joins, isEmpty);
    expect(left.reports, isEmpty);
  });

  test('the result waits until seen and moves the device tier', () async {
    final api = FakeLeagueApi(rows)
      ..emit(
        WorldLeagueState.fromFirestore({
          'tier': 3,
          'lastResult': {
            'weekKey': '2026-11-02',
            'oldTier': 2,
            'newTier': 3,
            'rank': 4,
            'size': 100,
            'xp': 820,
          },
        }),
      );
    final c = await container(api: api);
    addTearDown(c.dispose);
    final sub = c.listen(pendingWorldResultProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(worldLeagueStateProvider.future);
    await pumpEventQueue();
    final r = c.read(pendingWorldResultProvider)!;
    expect(r.promoted, isTrue);
    expect(r.size, 100);
    markWorldResultSeen(c.read);
    expect(c.read(pendingWorldResultProvider), isNull);
    expect(c.read(progressProvider).leagueTier, 3);
  });

  testWidgets('the screen shows 100 members with flags and scrolls to the user', (tester) async {
    final api = FakeLeagueApi(hundred)..emit(joined);
    SharedPreferences.setMockInitialValues({'league_country_v1': 'TR'});
    final prefs = await SharedPreferences.getInstance();
    await pumpLeague(tester, overrides(prefs, api: api));
    expect(find.text('Altın Ligi'), findsOneWidget);
    expect(find.textContaining('100 kişilik grup'), findsOneWidget);
    expect(find.byKey(const ValueKey('league-countdown')), findsOneWidget);
    // Opened at the user's row (60th) without any swiping.
    expect(find.text('Sen').hitTestable(), findsOneWidget);
    expect(find.text('Üye 0').hitTestable(), findsNothing);
    expect(find.text('🇹🇷'), findsWidgets);
    expect(find.text('🇩🇪'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('2 ülkeden 100'), 400, scrollable: vertical);
    expect(find.byKey(const ValueKey('league-leave')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('↓ ALT LİG BÖLGESİ'), -400, scrollable: vertical);
    expect(find.text('↓ ALT LİG BÖLGESİ'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('↑ YÜKSELME BÖLGESİ'), -400, scrollable: vertical);
    expect(find.text('↑ YÜKSELME BÖLGESİ'), findsOneWidget);
  });

  testWidgets('a member\'s worn Mağaza look shows on their row; the join sends mine', (tester) async {
    final api = FakeLeagueApi([
      RemoteMember(
        uid: 'a',
        name: 'Ayşe',
        avatar: '🦊',
        xp: 120,
        look: Showcase.fromMap({
          'avatar': 'av_kedi',
          'frame': 'av_yok',
          'theme': 'th_iznik',
          'useAvatar': true,
        }),
      ),
      const RemoteMember(uid: 'me', name: 'Mert', avatar: '⭐', xp: 40),
    ])..emit(joined);
    SharedPreferences.setMockInitialValues({'league_country_v1': 'TR'});
    final prefs = await SharedPreferences.getInstance();
    await pumpLeague(tester, overrides(prefs, api: api));
    expect(find.text('🐈'), findsOneWidget);
    expect(find.byKey(const ValueKey('look-theme-th_iznik')), findsOneWidget);
    expect(api.looks.last, isNotNull);
    expect(api.looks.last!.theme, isNull, reason: 'nothing worn yet');
  });

  testWidgets('the join card says what others see and joins', (tester) async {
    final api = FakeLeagueApi(rows);
    SharedPreferences.setMockInitialValues({'league_country_v1': 'DE'});
    final prefs = await SharedPreferences.getInstance();
    await pumpLeague(tester, overrides(prefs, api: api));
    expect(find.text('Dünya Ligi’ne katıl'), findsOneWidget);
    final privacy = tester.widget<Text>(find.byKey(const ValueKey('league-privacy')));
    expect(privacy.data, contains('Mert 🇩🇪'));
    expect(privacy.data, contains('ayrılabilirsin'));
    await tester.tap(find.byKey(const ValueKey('league-join')));
    await tester.pumpAndSettle();
    expect(api.joins.first.country, 'DE');
    expect(find.text('Burak'), findsOneWidget);
  });

  testWidgets('leaving asks first and calls the server', (tester) async {
    final api = FakeLeagueApi(rows)..emit(joined);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpLeague(tester, overrides(prefs, api: api));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('league-leave')), 400, scrollable: vertical);
    await tester.tap(find.byKey(const ValueKey('league-leave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('adın ve fotoğrafın artık görünmez'), findsOneWidget);
    await tester.tap(find.text('Ayrıl'));
    await tester.pumpAndSettle();
    expect(api.left, 1);
  });

  testWidgets('a guest sees the preview and a sign-in prompt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpLeague(tester, overrides(prefs, user: const AppUser(uid: 'g')));
    expect(find.textContaining('giriş yap'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Örnek tablo'), 400, scrollable: vertical);
    expect(find.textContaining('Örnek tablo'), findsOneWidget);
  });

  testWidgets('while the league loads the screen says so, not "Çevrimdışı mod"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(prefs, api: FakeLeagueApi(rows, silent: true)),
        child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('league-loading')), findsOneWidget);
    expect(find.textContaining('Çevrimdışı mod'), findsNothing);
    expect(find.text('Sen'), findsNothing); // no simulated rivals
  });

  testWidgets('Firebase still starting up is loading, not offline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(prefs, online: false, user: null),
          firebaseInitProvider.overrideWith((ref) => Completer<bool>().future),
        ],
        child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('league-loading')), findsOneWidget);
    expect(find.textContaining('Çevrimdışı mod'), findsNothing);
  });

  testWidgets('an error shows a Turkish message and retries', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = FakeLeagueApi(rows, failJoin: true)..emit(lastWeek);
    await pumpLeague(tester, overrides(prefs, api: api));
    expect(find.text('Dünya Ligi yüklenemedi'), findsOneWidget);
    expect(find.textContaining('Çevrimdışı mod'), findsNothing);
    expect(find.text('Sen'), findsNothing);
    expect(api.joins, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('league-retry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('league-loading')), findsOneWidget); // retrying
    await tester.pumpAndSettle();
    expect(api.joins, hasLength(2));
    expect(find.byKey(const ValueKey('league-error')), findsOneWidget);
  });

  testWidgets('league screen stays simulated without Firebase', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpLeague(tester, overrides(prefs, online: false, user: null));
    expect(find.text('Bronz Ligi'), findsOneWidget);
    expect(find.text('Sen'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Çevrimdışı mod'), 400, scrollable: vertical);
    expect(find.textContaining('Çevrimdışı mod'), findsOneWidget);
  });

  testWidgets('the result screen celebrates and never scolds', (tester) async {
    Future<String> textOf(LeagueResult r) async {
      await tester.pumpWidget(MaterialApp(home: LeagueResultScreen(result: r)));
      final all = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
      expect(all.toLowerCase(), isNot(contains('düştün')));
      expect(all.toLowerCase(), isNot(contains('ceza')));
      return all;
    }

    expect(
      await textOf(const LeagueResult(oldTier: 0, newTier: 1, rank: 3, size: 100, xp: 640)),
      contains('Gümüş Ligine yükseldin'),
    );
    expect(
      await textOf(const LeagueResult(oldTier: 4, newTier: 3, rank: 97, size: 100)),
      contains('Yeni hafta, yeni yarış'),
    );
    expect(
      await textOf(const LeagueResult(oldTier: 2, newTier: 2, rank: 40)),
      contains('Altın Liginde kaldın'),
    );
  });

  testWidgets('the country comes from the phone and can be changed in Profil', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(prefs),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: CountryButton())),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('profile-country')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-AZ')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Azerbaycan'), findsOneWidget);
    expect(prefs.getString('league_country_v1'), 'AZ');
  });

  group('CallableConversationService', () {
    final cafe = scenarioById('cafe');
    final history = [
      const ChatMessage(fromUser: false, text: 'Hi! What can I get you?'),
      const ChatMessage(fromUser: true, text: 'I want coffee.'),
    ];

    test('sends the scenario and history, parses the reply', () async {
      late Map<String, Object?> sent;
      final s = CallableConversationService((name, data) async {
        expect(name, 'converse');
        sent = data;
        return {'reply': 'Sure!', 'correction': 'I would like a coffee.', 'tip_tr': 'Kibar ol', 'done': true};
      });
      final turn = await s.send(cafe, history);
      expect(sent['scenarioId'], 'cafe');
      expect((sent['messages'] as List).last, {'role': 'user', 'content': 'I want coffee.'});
      expect(turn.reply, 'Sure!');
      expect(turn.correction, 'I would like a coffee.');
      expect(turn.tipTr, 'Kibar ol');
      expect(turn.done, isTrue);
      expect(s.isLive, isTrue);
    });

    test('empty correction means none', () async {
      final s = CallableConversationService(
        (_, _) async => {'reply': 'Ok', 'correction': '', 'tip_tr': ' ', 'done': false},
      );
      final turn = await s.send(cafe, history);
      expect(turn.correction, isNull);
      expect(turn.tipTr, isNull);
    });

    test('maps server errors to Turkish messages', () async {
      Future<String> errorFor(Object e) async {
        final s = CallableConversationService((_, _) async => throw e);
        try {
          await s.send(cafe, history);
        } on ConversationException catch (x) {
          return x.message;
        }
        fail('no exception');
      }

      expect(
        await errorFor(FirebaseFunctionsException(code: 'resource-exhausted', message: 'daily_quota')),
        contains('Bugünlük'),
      );
      expect(
        await errorFor(FirebaseFunctionsException(code: 'permission-denied', message: 'premium_required')),
        contains('Premium'),
      );
      expect(await errorFor(TimeoutException('slow')), contains('Bağlantı'));
    });

    test('demo is used without Firebase', () async {
      final c = await container();
      addTearDown(c.dispose);
      expect(c.read(conversationServiceProvider), isA<DemoConversationService>());
    });
  });
}

/// Riverpod pauses providers nobody listens to, so listen while waiting.
Future<WorldLeagueView> viewOf(ProviderContainer c) async {
  final sub = c.listen(worldLeagueProvider, (_, _) {});
  try {
    return await c.read(worldLeagueProvider.future);
  } finally {
    sub.close();
  }
}

/// The page's own scroll view (the tier strip scrolls sideways).
final vertical = find
    .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
    .first;
