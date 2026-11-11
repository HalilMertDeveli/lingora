import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/league.dart';
import '../data/progress.dart';
import 'firebase/firebase_providers.dart';

/// Real leagues on the server (functions/src/league.ts). When Firebase is
/// off, offline or the user is signed out, [remoteLeagueProvider] is null and
/// the league screen keeps the simulated rivals from data/league.dart.

/// One row of a server league group.
class RemoteMember {
  const RemoteMember({required this.uid, required this.name, required this.avatar, required this.xp});
  final String uid;
  final String name;
  final String avatar;
  final int xp;
}

/// Where the user plays this week.
class LeagueSeat {
  const LeagueSeat({required this.groupId, required this.weekKey, required this.tier});
  final String groupId;
  final String weekKey;
  final int tier;
}

/// This week's group as the server sees it.
class RemoteLeague {
  const RemoteLeague({required this.seat, required this.uid, required this.members});
  final LeagueSeat seat;
  final String uid;
  final List<RemoteMember> members;

  int get tier => seat.tier;

  /// Sorted standings in the screen's format, the user marked as "Sen".
  List<LeagueEntry> get table {
    final sorted = [...members]..sort((a, b) => b.xp.compareTo(a.xp));
    return [
      for (final m in sorted)
        m.uid == uid ? LeagueEntry('Sen', m.avatar, m.xp, isUser: true) : LeagueEntry(m.name, m.avatar, m.xp),
    ];
  }
}

/// The server calls the league needs (mockable in tests).
abstract class LeagueApi {
  /// Joins (or returns) this week's group. [tier] is the offline tier, used
  /// by the server only the first time.
  Future<LeagueSeat> join({required String name, required String avatar, int? tier});

  /// Adds XP; returns the new weekly total.
  Future<int> addXp(int xp);

  Stream<List<RemoteMember>> members(String groupId);
}

class FirebaseLeagueApi implements LeagueApi {
  FirebaseLeagueApi(this._functions, this._db);
  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

  Future<Map<String, dynamic>> _call(String name, Map<String, Object?> data) async {
    final res = await _functions.httpsCallable(name).call<Object?>(data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<LeagueSeat> join({required String name, required String avatar, int? tier}) async {
    final r = await _call('joinLeague', {'name': name, 'avatar': avatar, 'tier': ?tier});
    return LeagueSeat(
      groupId: r['groupId'] as String,
      weekKey: r['weekKey'] as String,
      tier: (r['tier'] as num).toInt(),
    );
  }

  @override
  Future<int> addXp(int xp) async => ((await _call('addLeagueXp', {'xp': xp}))['xp'] as num).toInt();

  @override
  Stream<List<RemoteMember>> members(String groupId) => _db
      .collection('leagues/$groupId/members')
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            RemoteMember(
              uid: d.id,
              name: d.data()['name'] as String? ?? '?',
              avatar: d.data()['avatar'] as String? ?? '⭐',
              xp: (d.data()['xp'] as num?)?.toInt() ?? 0,
            ),
        ],
      );
}

/// Null unless Firebase is ready and someone is signed in.
final leagueApiProvider = Provider<LeagueApi?>((ref) {
  final functions = ref.watch(functionsProvider);
  final db = ref.watch(firestoreProvider);
  if (functions == null || db == null || ref.watch(currentUidProvider) == null) return null;
  return FirebaseLeagueApi(functions, db);
});

/// Server limit per addLeagueXp call (functions/src/league.ts).
const maxXpPerCall = 500;

/// Name shown to other league members.
String leagueDisplayName(String? displayName) {
  final first = displayName?.trim().split(RegExp(r'\s+')).first ?? '';
  return first.isEmpty ? 'Dilbaz öğrencisi' : first.substring(0, min(first.length, 24));
}

/// This week's real league, or null when it is not available (the screen
/// then shows the simulated league). Joins the group and uploads the XP the
/// app earned this week that the server has not seen yet.
final remoteLeagueProvider = StreamProvider<RemoteLeague?>((ref) async* {
  final api = ref.watch(leagueApiProvider);
  final uid = ref.watch(currentUidProvider);
  if (api == null || uid == null) {
    yield null;
    return;
  }
  // Re-runs when the user earns XP while the league is open.
  final start = weekStart(ref.read(clockProvider)());
  final localWeekXp = ref.watch(progressProvider.select((p) => p.weekXp(start)));
  final name = leagueDisplayName(ref.read(authStateProvider).value?.displayName);

  final LeagueSeat seat;
  try {
    seat = await api.join(name: name, avatar: '⭐', tier: ref.read(progressProvider).leagueTier);
  } catch (_) {
    yield null; // offline or server error: keep the simulated league
    return;
  }

  var first = true;
  await for (final members in api.members(seat.groupId)) {
    if (first) {
      first = false;
      final mine = members.where((m) => m.uid == uid).firstOrNull?.xp ?? 0;
      final missing = localWeekXp - mine;
      if (missing > 0) {
        // Best effort: rate limits or a daily cap may hold some back; the
        // rest goes up the next time the league is opened.
        unawaited(api.addXp(min(missing, maxXpPerCall)).catchError((_) => 0));
      }
    }
    yield RemoteLeague(seat: seat, uid: uid, members: members);
  }
});
