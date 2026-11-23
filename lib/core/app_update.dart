import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/progress.dart';
import '../services/firebase/firebase_providers.dart';
import '../theme.dart';
import 'app_resume.dart';

/// Forced and recommended updates, controlled from Firestore `config/app`
/// (docs/zorunlu-guncelleme.md):
///
///     { minVersionCode: 12, recommendedVersionCode: 14, message: "…" }
///
/// Below `minVersionCode` the app shows a blocking "Lütfen güncelle" screen;
/// below `recommendedVersionCode` a banner that can be closed. The document
/// is read from the server only: offline, a missing or broken document, or a
/// build without Firebase never block the app.

/// Play Store page of the app.
const playStorePackage = 'com.cenebaz.app';
const playStoreUrl = 'https://play.google.com/store/apps/details?id=$playStorePackage';
const _playStoreMarketUrl = 'market://details?id=$playStorePackage';

/// The default text of the blocking screen when `message` is empty.
const defaultUpdateMessage =
    'Çenebaz\'ın bu sürümü artık desteklenmiyor. Kaldığın yerden devam etmek için '
    'uygulamayı Google Play\'den güncelle. İlerlemen kaybolmaz.';

/// How often the document is read again when the app comes back to the
/// foreground.
const updateRecheckInterval = Duration(hours: 6);

/// Gives up on the config after this long (slow network = no block).
const updateFetchTimeout = Duration(seconds: 8);

/// The fields of `config/app`. Missing or invalid numbers count as 0
/// (= no minimum), so a typo in the console never locks anyone out.
class AppVersionPolicy {
  const AppVersionPolicy({this.minVersionCode = 0, this.recommendedVersionCode = 0, this.message = ''});

  factory AppVersionPolicy.fromMap(Map<String, dynamic> m) {
    int code(Object? v) => v is num && v.isFinite && v > 0 ? v.toInt() : 0;
    final msg = m['message'];
    return AppVersionPolicy(
      minVersionCode: code(m['minVersionCode']),
      recommendedVersionCode: code(m['recommendedVersionCode']),
      message: msg is String ? msg.trim() : '',
    );
  }

  final int minVersionCode;
  final int recommendedVersionCode;
  final String message;
}

enum UpdateNeed { none, recommended, required }

/// What [build] needs under [policy]. An unknown build (0 or less) never
/// needs anything.
UpdateNeed updateNeedFor(int build, AppVersionPolicy policy) {
  if (build <= 0) return UpdateNeed.none;
  if (build < policy.minVersionCode) return UpdateNeed.required;
  if (build < policy.recommendedVersionCode) return UpdateNeed.recommended;
  return UpdateNeed.none;
}

/// Reads `config/app`. Null when the document does not exist.
abstract interface class AppConfigSource {
  Future<Map<String, dynamic>?> fetch();
}

class FirestoreAppConfigSource implements AppConfigSource {
  FirestoreAppConfigSource(this._db);
  final FirebaseFirestore _db;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    // Server only: a cached copy while offline must not lock the app.
    final snap = await _db.doc('config/app').get(const GetOptions(source: Source.server));
    return snap.data();
  }
}

/// The config reader, or null when Firebase is off (tests, local builds).
final appConfigSourceProvider = Provider<AppConfigSource?>((ref) {
  final db = ref.watch(firestoreProvider);
  return db == null ? null : FirestoreAppConfigSource(db);
});

/// This build's version code (`+N` in pubspec.yaml), or null if unknown.
final buildNumberProvider = FutureProvider<int?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber);
  } catch (_) {
    return null;
  }
});

class UpdateStatus {
  const UpdateStatus({this.need = UpdateNeed.none, this.policy = const AppVersionPolicy()});
  final UpdateNeed need;
  final AppVersionPolicy policy;

  String get message => policy.message.isEmpty ? defaultUpdateMessage : policy.message;
}

/// Checks `config/app` at start and again on resume (at most every
/// [updateRecheckInterval]). Errors keep the last answer; the first answer
/// is "no update needed".
final updateStatusProvider = NotifierProvider<UpdateStatusController, UpdateStatus>(
  UpdateStatusController.new,
);

class UpdateStatusController extends Notifier<UpdateStatus> {
  DateTime? _checkedAt;
  bool _busy = false;

  @override
  UpdateStatus build() {
    final source = ref.watch(appConfigSourceProvider);
    if (source == null) return const UpdateStatus();
    final build = ref.watch(buildNumberProvider).value;
    if (build == null) return const UpdateStatus();
    _checkedAt = null;
    ref.listen(appResumeProvider, (_, _) => _check(source, build));
    Future.microtask(() => _check(source, build));
    return const UpdateStatus();
  }

  Future<void> _check(AppConfigSource source, int build) async {
    final now = ref.read(clockProvider)();
    final last = _checkedAt;
    if (_busy || (last != null && now.difference(last) < updateRecheckInterval)) return;
    _busy = true;
    try {
      final data = await source.fetch().timeout(updateFetchTimeout);
      if (!ref.mounted) return;
      _checkedAt = now;
      final policy = data == null ? const AppVersionPolicy() : AppVersionPolicy.fromMap(data);
      state = UpdateStatus(need: updateNeedFor(build, policy), policy: policy);
    } catch (e) {
      // Offline, timeout, permission: never block; try again on the next resume.
      debugPrint('update check skipped: $e');
    } finally {
      _busy = false;
    }
  }
}

/// The recommended version whose banner the user closed.
const _dismissedKey = 'update.dismissedVersion';

final _dismissedProvider = NotifierProvider<_Dismissed, int>(_Dismissed.new);

class _Dismissed extends Notifier<int> {
  @override
  int build() => ref.read(prefsProvider).getInt(_dismissedKey) ?? 0;

  void dismiss(int version) {
    state = version;
    ref.read(prefsProvider).setInt(_dismissedKey, version);
  }
}

/// Opens the app's Play Store page (the Play app if possible).
Future<void> openPlayStore(BuildContext context) async {
  for (final url in [_playStoreMarketUrl, playStoreUrl]) {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // try the next one
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Google Play açılamadı. Play Store\'da "Çenebaz" diye arat.')),
    );
  }
}

/// Wraps the whole app (MaterialApp.builder): the blocking screen when an
/// update is required, a closable banner when one is recommended.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider);
    switch (status.need) {
      case UpdateNeed.none:
        return child;
      case UpdateNeed.required:
        return ForceUpdateScreen(message: status.message);
      case UpdateNeed.recommended:
        final version = status.policy.recommendedVersionCode;
        if (ref.watch(_dismissedProvider) >= version) return child;
        return Column(
          children: [
            UpdateBanner(onClose: () => ref.read(_dismissedProvider.notifier).dismiss(version)),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
            ),
          ],
        );
    }
  }
}

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // No way back: the system back button leaves the app.
    return Scaffold(
      key: const ValueKey('force-update'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_rounded, size: 72, color: Brand.primary),
                  const SizedBox(height: 20),
                  Text('Lütfen güncelle', style: t.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(message, style: t.bodyLarge?.copyWith(height: 1.4), textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const ValueKey('force-update-store'),
                    onPressed: () => openPlayStore(context),
                    icon: const Icon(Icons.shop_rounded),
                    label: const Text('Google Play\'de güncelle'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      key: const ValueKey('update-banner'),
      color: Brand.primary.withValues(alpha: 0.12),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, top + 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.system_update_rounded, color: Brand.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('Çenebaz\'ın yeni sürümü hazır.')),
            TextButton(
              key: const ValueKey('update-banner-store'),
              onPressed: () => openPlayStore(context),
              child: const Text('Güncelle'),
            ),
            // No tooltip: the banner sits above the Navigator (no Overlay).
            IconButton(
              key: const ValueKey('update-banner-close'),
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, semanticLabel: 'Kapat'),
            ),
          ],
        ),
      ),
    );
  }
}
