import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException, ProviderListenable;
import 'package:image/image.dart' as img;

import '../data/league.dart';
import '../data/progress.dart';
import '../data/showcase_data.dart';
import '../theme.dart' show Brand;
import 'firebase/firebase_providers.dart';
import 'profile.dart' show accountUidProvider, myDisplayNameProvider, profileProvider;
import 'showcase.dart' show myShowcaseProvider;

/// Dünya Ligi: weekly groups of up to 100 signed-in learners from every
/// country (functions/src/league.ts, docs/firebase-backend.md).
///
/// - Without Firebase (local builds) or in Çocuk modu the league screen
///   shows the simulated league from data/league.dart. With Firebase it is
///   never simulated: loading and errors (with a retry) have their own views.
/// - A guest sees that table as a preview and is asked to sign in.
/// - An account joins once (after reading what others will see) and is
///   then placed in a group every week automatically.

/// One row of a server league group.
class RemoteMember {
  const RemoteMember({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.xp,
    this.country,
    this.photo,
    this.look,
    this.reachedAt = 0,
  });
  final String uid;
  final String name;
  final String avatar;
  final int xp;
  final String? country;
  final Uint8List? photo;

  /// Worn Mağaza items (avatar, frame, theme, outfits), known ids only.
  final Showcase? look;

  /// Milliseconds when the member last gained XP; the earlier wins a tie.
  final int reachedAt;
}

/// Where the user plays this week.
class LeagueSeat {
  const LeagueSeat({required this.groupId, required this.weekKey, required this.tier});
  final String groupId;
  final String weekKey;
  final int tier;
}

/// `leagueState/{uid}`, written by the server.
class WorldLeagueState {
  const WorldLeagueState({
    required this.tier,
    this.groupId,
    this.weekKey,
    this.optedOut = false,
    this.lastResult,
    this.lastResultWeek,
  });

  factory WorldLeagueState.fromFirestore(Map<String, dynamic> d) {
    final r = d['lastResult'];
    return WorldLeagueState(
      tier: ((d['tier'] as num?)?.toInt() ?? 0).clamp(0, leagueTiers.length - 1),
      groupId: d['groupId'] as String?,
      weekKey: d['weekKey'] as String?,
      optedOut: d['optedOut'] == true,
      lastResult: r is Map ? LeagueResult.fromJson(Map<String, dynamic>.from(r)) : null,
      lastResultWeek: r is Map ? r['weekKey'] as String? : null,
    );
  }

  final int tier;
  final String? groupId;
  final String? weekKey;

  /// The learner left the league; nothing joins until they join again.
  final bool optedOut;
  final LeagueResult? lastResult;
  final String? lastResultWeek;
}

/// This week's group as the server sees it.
class RemoteLeague {
  const RemoteLeague({required this.seat, required this.uid, required this.members});
  final LeagueSeat seat;
  final String uid;
  final List<RemoteMember> members;

  int get tier => seat.tier;

  /// Sorted standings in the screen's format, the user marked.
  List<LeagueEntry> get table {
    final sorted = [...members]
      ..sort((a, b) {
        final byXp = b.xp.compareTo(a.xp);
        if (byXp != 0) return byXp;
        final byTime = a.reachedAt.compareTo(b.reachedAt);
        return byTime != 0 ? byTime : a.uid.compareTo(b.uid);
      });
    return [
      for (final m in sorted)
        LeagueEntry(
          m.uid == uid ? 'Sen' : m.name,
          m.avatar,
          m.xp,
          isUser: m.uid == uid,
          uid: m.uid,
          country: m.country,
          photo: m.photo,
          look: m.look,
        ),
    ];
  }

  /// How many different countries are in the group.
  int get countries => {for (final m in members) m.country}.whereType<String>().length;
}

/// What the app sent and the server answered for the weekly XP.
class XpReport {
  const XpReport({required this.xp, required this.pending});
  final int xp;
  final int pending;
}

/// The server calls the league needs (mockable in tests).
abstract class LeagueApi {
  /// Joins (or returns) this week's group and refreshes the row's name,
  /// avatar, country, photo (a small base64 JPEG) and worn Mağaza [look].
  Future<LeagueSeat> join({
    required String name,
    required String avatar,
    String? country,
    String? photo,
    Showcase? look,
  });

  /// Reports this week's XP total; the server adds what it has not seen.
  Future<XpReport> reportXp({required int weekXp, required String weekKey});

  /// Removes the row; the learner can join again any time.
  Future<void> leave();

  Stream<List<RemoteMember>> members(String groupId);

  /// `leagueState/{uid}`; null before the first join.
  Stream<WorldLeagueState?> state(String uid);
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
  Future<LeagueSeat> join({
    required String name,
    required String avatar,
    String? country,
    String? photo,
    Showcase? look,
  }) async {
    final r = await _call('joinLeague', {
      'name': name,
      'avatar': avatar,
      'country': country,
      'photo': photo,
      'look': ?_lookMap(look),
    });
    return LeagueSeat(
      groupId: r['groupId'] as String,
      weekKey: r['weekKey'] as String,
      tier: (r['tier'] as num).toInt(),
    );
  }

  @override
  Future<XpReport> reportXp({required int weekXp, required String weekKey}) async {
    final r = await _call('addLeagueXp', {'weekXp': weekXp, 'weekKey': weekKey});
    return XpReport(xp: (r['xp'] as num).toInt(), pending: (r['pending'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> leave() => _call('leaveLeague', {});

  @override
  Stream<List<RemoteMember>> members(String groupId) => _db
      .collection('leagues/$groupId/members')
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            RemoteMember(
              uid: d.id,
              name: shownName(d.data()['name'] as String? ?? '?'),
              avatar: d.data()['avatar'] as String? ?? '⭐',
              xp: (d.data()['xp'] as num?)?.toInt() ?? 0,
              country: d.data()['country'] as String?,
              photo: switch (d.data()['photo']) {
                final Blob b => b.bytes,
                _ => null,
              },
              look: Showcase.fromMap(d.data()['look']),
              reachedAt: (d.data()['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
            ),
        ],
      );

  @override
  Stream<WorldLeagueState?> state(String uid) => _db
      .doc('leagueState/$uid')
      .snapshots()
      .map((s) => s.exists ? WorldLeagueState.fromFirestore(s.data()!) : null);
}

/// Firebase is on, so the Dünya Ligi can be shown (overridden in tests).
final leagueOnlineProvider = Provider<bool>((ref) => ref.watch(firestoreProvider) != null);

/// Null unless Firebase is ready and someone with an account (not a guest)
/// is signed in.
final leagueApiProvider = Provider<LeagueApi?>((ref) {
  final functions = ref.watch(functionsProvider);
  final db = ref.watch(firestoreProvider);
  if (functions == null || db == null || ref.watch(accountUidProvider) == null) return null;
  return FirebaseLeagueApi(functions, db);
});

/// Name shown to other league members.
String leagueDisplayName(String? displayName) {
  final first = displayName?.trim().split(RegExp(r'\s+')).first ?? '';
  return first.isEmpty ? 'Çenebaz öğrencisi' : first.substring(0, min(first.length, 24));
}

/// The generic name before the app was renamed. League and friend documents
/// written earlier still carry it; [shownName] swaps it for the current one.
const legacyDefaultName = 'Dilmaç öğrencisi';

/// A stored member or friend name as shown in the app.
String shownName(String name) => name == legacyDefaultName ? leagueDisplayName(null) : name;

// ---- Country ----

/// The phone's region, e.g. "TR"; null when it has none.
String? deviceCountry() {
  final c = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
  return c != null && RegExp(r'^[A-Z]{2}$').hasMatch(c) ? c : null;
}

/// The country flag shown next to the learner in the league: the phone's
/// region until they pick another one in Profil.
class LeagueCountryNotifier extends Notifier<String?> {
  static const key = 'league_country_v1';

  @override
  String? build() => ref.read(prefsProvider).getString(key) ?? deviceCountry();

  void set(String? code) {
    state = code;
    final prefs = ref.read(prefsProvider);
    unawaited(code == null ? prefs.remove(key) : prefs.setString(key, code));
  }
}

final leagueCountryProvider = NotifierProvider<LeagueCountryNotifier, String?>(LeagueCountryNotifier.new);

// ---- Photo ----

/// Side of the league thumbnail; 100 rows of these stay around 300 KB.
const leaguePhotoSize = 64;

/// Shrinks the profile photo for the league row (base64 JPEG, a few KB).
String? leagueThumbnail(Uint8List? photo) {
  if (photo == null) return null;
  final decoded = img.decodeImage(photo);
  if (decoded == null) return null;
  final small = img.copyResize(decoded, width: leaguePhotoSize, height: leaguePhotoSize);
  final jpg = img.encodeJpg(small, quality: 70);
  return jpg.length <= 8 * 1024 ? base64Encode(jpg) : null;
}

// ---- State ----

/// `leagueState/{uid}`: null for a guest, without Firebase, or before the
/// first join.
final worldLeagueStateProvider = StreamProvider<WorldLeagueState?>((ref) {
  final api = ref.watch(leagueApiProvider);
  final uid = ref.watch(accountUidProvider);
  if (api == null || uid == null) return Stream.value(null);
  // Errors stay errors (swallowing them left the league loading for
  // ever) and show at once: the screen offers the retry.
  return api.state(uid);
}, retry: (_, _) => null);

/// What the league screen shows.
sealed class WorldLeagueView {
  const WorldLeagueView();
}

/// Simulated league: no Firebase (local builds, tests) or Çocuk modu.
class WorldOffline extends WorldLeagueView {
  const WorldOffline();
}

/// The Dünya Ligi is on its way (Firebase, sign-in, the seat or the first
/// rows still loading).
class WorldLoading extends WorldLeagueView {
  const WorldLoading();
}

/// The Dünya Ligi could not be loaded: a Turkish [message] and a retry,
/// never simulated rivals passed off as the real ones.
class WorldError extends WorldLeagueView {
  const WorldError(this.message);
  final String message;
}

/// What the league screen shows for [value]: loading (also while retrying
/// after an error) until there is a view, and an unexpected failure as
/// [WorldError].
WorldLeagueView worldLeagueViewOf(AsyncValue<WorldLeagueView> value) {
  if (value.hasError && !value.isLoading) return WorldError(leagueErrorMessage(value.error!));
  final view = value.value;
  if (view == null || (value.isLoading && view is WorldError)) return const WorldLoading();
  return view;
}

/// A league failure in Turkish for the learner.
String leagueErrorMessage(Object error) {
  // A failed leagueState read reaches the league wrapped by Riverpod.
  while (error is ProviderException) {
    error = error.exception;
  }
  final code = error is FirebaseException ? error.code : null;
  return switch (code) {
    'unavailable' ||
    'deadline-exceeded' => 'İnternet bağlantısı kurulamadı. Bağlantını kontrol edip yeniden dene.',
    'permission-denied' ||
    'unauthenticated' => 'Hesabın doğrulanamadı. Yeniden dene; sürerse çıkış yapıp tekrar giriş yap.',
    _ when error is TimeoutException => 'Sunucu yanıt vermedi. Biraz sonra yeniden dene.',
    _ => 'Dünya Ligi şu an yüklenemedi. Biraz sonra yeniden dene.',
  };
}

/// Signed out or a guest: the preview table and a sign-in button.
class WorldGuest extends WorldLeagueView {
  const WorldGuest();
}

/// An account that has not joined yet (or left): the join card.
class WorldNeedsJoin extends WorldLeagueView {
  const WorldNeedsJoin({required this.tier});
  final int tier;
}

class WorldLive extends WorldLeagueView {
  const WorldLive(this.league);
  final RemoteLeague league;
}

/// Reads a provider (`ref.read` of a Ref or a WidgetRef).
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Joins the league with the learner's current name, photo and country.
Future<LeagueSeat?> joinWorldLeague(ProviderReader read) async {
  final api = read(leagueApiProvider);
  if (api == null) return null;
  final photo = read(profileProvider).photo;
  return api.join(
    name: read(myDisplayNameProvider),
    avatar: '⭐',
    country: read(leagueCountryProvider),
    photo: photo == null ? null : await compute<Uint8List?, String?>(leagueThumbnail, photo),
    look: read(myShowcaseProvider),
  );
}

/// The league the screen shows. Live while it is on screen only, so the
/// 100 rows are read when someone looks at them.
///
/// While something is still loading nothing is emitted (the screen shows
/// [WorldLoading]); a failure becomes [WorldError].
final worldLeagueProvider = StreamProvider.autoDispose<WorldLeagueView>((ref) async* {
  if (Brand.isKid) {
    yield const WorldOffline();
    return;
  }
  if (!ref.watch(leagueOnlineProvider)) {
    // Firebase still starting up is not "offline".
    if (ref.watch(firebaseInitProvider).isLoading) return;
    yield const WorldOffline();
    return;
  }
  if (ref.watch(authStateProvider).isLoading) return;
  final api = ref.watch(leagueApiProvider);
  final uid = ref.watch(accountUidProvider);
  if (api == null || uid == null) {
    yield const WorldGuest();
    return;
  }

  // Only what decides the seat: an XP report also rewrites leagueState and
  // must not start the league over.
  final ({bool exists, bool optedOut, int tier, String? groupId, String? weekKey}) state;
  try {
    state = await ref.watch(
      worldLeagueStateProvider.selectAsync(
        (s) => (
          exists: s != null,
          optedOut: s?.optedOut ?? false,
          tier: s?.tier ?? 0,
          groupId: s?.groupId,
          weekKey: s?.weekKey,
        ),
      ),
    );
  } catch (e) {
    debugPrint('League state failed: $e');
    yield WorldError(leagueErrorMessage(e));
    return;
  }
  if (!state.exists || state.optedOut) {
    yield WorldNeedsJoin(tier: state.tier);
    return;
  }

  final LeagueSeat seat;
  final groupId = state.groupId;
  if (groupId != null && state.weekKey == trWeekKey(ref.read(clockProvider)())) {
    // Seated this week: show the group right away and refresh the row's
    // name, photo and look in the background (a cold server start takes
    // seconds).
    seat = LeagueSeat(groupId: groupId, weekKey: state.weekKey!, tier: state.tier);
    unawaited(
      joinWorldLeague(ref.read)
          .then<void>((_) {}, onError: (Object e) => debugPrint('League refresh failed: $e')),
    );
  } else {
    try {
      // Opens the new week's group after Monday.
      seat = (await joinWorldLeague(ref.read).timeout(const Duration(seconds: 30)))!;
    } catch (e) {
      debugPrint('League join failed: $e');
      yield WorldError(leagueErrorMessage(e));
      return;
    }
  }
  try {
    await for (final members in api.members(seat.groupId)) {
      yield WorldLive(RemoteLeague(seat: seat, uid: uid, members: members));
    }
  } catch (e) {
    debugPrint('League members failed: $e');
    yield WorldError(leagueErrorMessage(e));
  }
});

// ---- XP ----

/// Reports the week's XP to the Dünya Ligi whenever it grows (listened in
/// main.dart). The server takes a weekly total, so a repeated or lost call
/// never counts XP twice; what the per-minute limit holds back goes up a
/// minute later.
final leagueXpSyncProvider = Provider<void>((ref) {
  final api = ref.watch(leagueApiProvider);
  final state = ref.watch(worldLeagueStateProvider).value;
  if (Brand.isKid || api == null || state == null || state.optedOut) return;
  // The server decides the tier from now on (see HomeScreen._settleLeague).
  if (ref.read(prefsProvider).getBool(worldMemberKey) != true) {
    unawaited(ref.read(prefsProvider).setBool(worldMemberKey, true));
  }
  final clock = ref.read(clockProvider);
  final week = trWeekKey(clock());
  final weekXp = ref.watch(progressProvider.select((p) => p.weekXp(weekStart(clock()))));
  if (weekXp <= 0) return;

  Timer? retry;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    retry?.cancel();
  });
  Future<void> send() async {
    try {
      if (state.weekKey != week) {
        // First XP of a new week: take a seat; leagueState changes and
        // this provider runs again to report the XP.
        await joinWorldLeague(ref.read);
        return;
      }
      final r = await api.reportXp(weekXp: weekXp, weekKey: week);
      if (r.pending > 0 && !disposed) retry = Timer(const Duration(seconds: 61), send);
    } catch (_) {
      // Offline, too fast or the week just turned: the next lesson or
      // app start reports the total again.
    }
  }

  // Lessons often end in quick succession: wait for the last one.
  retry = Timer(const Duration(seconds: 3), send);
});

// ---- Result ----

/// Set once the learner plays in the Dünya Ligi: the simulated week then
/// no longer makes its own result.
const worldMemberKey = 'league_world_member_v1';

/// Week of the last Dünya Ligi result the learner has seen.
const leagueResultSeenKey = 'league_result_seen_v1';

/// The last finished Dünya Ligi week's result, until the learner has seen it.
final pendingWorldResultProvider = Provider<LeagueResult?>((ref) {
  final state = ref.watch(worldLeagueStateProvider).value;
  final result = state?.lastResult;
  if (result == null || state?.lastResultWeek == null) return null;
  final seen = ref.watch(_resultSeenProvider);
  return seen == state!.lastResultWeek ? null : result;
});

class _ResultSeenNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(prefsProvider).getString(leagueResultSeenKey);

  void mark(String week) {
    state = week;
    unawaited(ref.read(prefsProvider).setString(leagueResultSeenKey, week));
  }
}

final _resultSeenProvider = NotifierProvider<_ResultSeenNotifier, String?>(_ResultSeenNotifier.new);

/// Marks the pending result seen and moves the on-device tier along.
void markWorldResultSeen(ProviderReader read) {
  final state = read(worldLeagueStateProvider).value;
  final week = state?.lastResultWeek;
  if (week == null) return;
  read(_resultSeenProvider.notifier).mark(week);
  read(progressProvider.notifier).adoptLeagueTier(state!.lastResult!.newTier);
}

/// What the league row shows of the worn Mağaza items (the chosen showcase
/// items stay for friends). All nulls clear a look worn before.
Map<String, Object?>? _lookMap(Showcase? look) {
  if (look == null) return null;
  return {
    'avatar': look.avatar,
    'frame': look.frame,
    'theme': look.theme,
    'mascot': look.mascot,
    'pofuduk': look.pofuduk,
    'useAvatar': look.useAvatar,
  };
}
