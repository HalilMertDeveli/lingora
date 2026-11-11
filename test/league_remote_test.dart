import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/screens/league_screen.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/league_remote.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLeagueApi implements LeagueApi {
  FakeLeagueApi(this.rows, {this.failJoin = false});
  final List<RemoteMember> rows;
  final bool failJoin;
  final joins = <({String name, int? tier})>[];
  final added = <int>[];

  @override
  Future<LeagueSeat> join({required String name, required String avatar, int? tier}) async {
    joins.add((name: name, tier: tier));
    if (failJoin) throw Exception('offline');
    return const LeagueSeat(groupId: '2026-11-09_2_0', weekKey: '2026-11-09', tier: 2);
  }

  @override
  Future<int> addXp(int xp) async {
    added.add(xp);
    return xp;
  }

  @override
  Stream<List<RemoteMember>> members(String groupId) => Stream.value(rows);
}

// Tuesday of the week starting Monday 2026-11-09.
final now = DateTime(2026, 11, 10, 12);

Future<ProviderContainer> container({LeagueApi? api, Progress progress = const Progress()}) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(progress.toJson())});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => now),
      if (api != null) ...[
        leagueApiProvider.overrideWithValue(api),
        currentUidProvider.overrideWithValue('me'),
        authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'me', displayName: 'Mert Develi'))),
      ],
    ],
  );
}

const rows = [
  RemoteMember(uid: 'a', name: 'Ayşe', avatar: '🦊', xp: 120),
  RemoteMember(uid: 'me', name: 'Mert', avatar: '⭐', xp: 40),
  RemoteMember(uid: 'b', name: 'Burak', avatar: '🐼', xp: 300),
];

void main() {
  test('leagueDisplayName shows only the first name', () {
    expect(leagueDisplayName('Mert Develi'), 'Mert');
    expect(leagueDisplayName('  '), 'Dilbaz öğrencisi');
    expect(leagueDisplayName(null), 'Dilbaz öğrencisi');
  });

  test('no Firebase means no remote league', () async {
    final c = await container();
    addTearDown(c.dispose);
    expect(c.read(leagueApiProvider), isNull);
    expect(await remoteOf(c), isNull);
  });

  test('joins with the offline tier, sorts members and uploads missing XP', () async {
    final api = FakeLeagueApi(rows);
    final c = await container(
      api: api,
      progress: const Progress(leagueTier: 1, xpByDay: {'2026-11-09': 50, '2026-11-10': 60}),
    );
    addTearDown(c.dispose);
    final league = (await remoteOf(c))!;
    expect(api.joins.single, (name: 'Mert', tier: 1));
    expect(league.tier, 2);
    expect(league.table.map((e) => e.name), ['Burak', 'Ayşe', 'Sen']);
    expect(league.table.last.isUser, isTrue);
    // 110 XP this week on the device, 40 on the server.
    expect(api.added, [70]);
  });

  test('a failed join falls back to the simulated league', () async {
    final c = await container(api: FakeLeagueApi(rows, failJoin: true));
    addTearDown(c.dispose);
    expect(await remoteOf(c), isNull);
  });

  testWidgets('league screen shows real members when available', (tester) async {
    final api = FakeLeagueApi(rows);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          leagueApiProvider.overrideWithValue(api),
          currentUidProvider.overrideWithValue('me'),
          authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'me'))),
        ],
        child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Burak'), findsOneWidget);
    expect(find.text('Altın Ligi'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('gerçek Dilbaz'), 200);
    expect(find.textContaining('gerçek Dilbaz'), findsOneWidget);
  });

  testWidgets('league screen stays simulated without Firebase', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
        child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bronz Ligi'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Çevrimdışı mod'), 200);
    expect(find.textContaining('Çevrimdışı mod'), findsOneWidget);
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
Future<RemoteLeague?> remoteOf(ProviderContainer c) {
  final sub = c.listen(remoteLeagueProvider, (_, _) {});
  return c.read(remoteLeagueProvider.future).whenComplete(sub.close);
}
