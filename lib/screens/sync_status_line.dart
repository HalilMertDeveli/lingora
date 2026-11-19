import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../services/firebase/progress_sync.dart';
import '../theme.dart';

/// Where the learner's progress is, in one honest line, from the real sync
/// state ([progressSyncProvider]):
///
/// * only on this phone (no account yet, or Firebase off);
/// * backed up to the account, with when;
/// * waiting for a connection (changes not yet confirmed by the server).
enum SyncBadge { deviceOnly, backedUp, waiting, checking }

SyncBadge syncBadgeOf(SyncStatus s) => switch (s.state) {
  SyncState.off || SyncState.signedOut || SyncState.guest => SyncBadge.deviceOnly,
  SyncState.synced => SyncBadge.backedUp,
  SyncState.pending || SyncState.error => SyncBadge.waiting,
  SyncState.syncing => SyncBadge.checking,
};

/// "az önce", "5 dk önce", "2 sa önce", "dün", "3 gün önce".
String agoTr(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'az önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  if (d.inDays == 1) return 'dün';
  return '${d.inDays} gün önce';
}

/// The line's text. [firebase] false: there is no account to back up to.
String syncStatusText(SyncStatus s, DateTime now) => switch (syncBadgeOf(s)) {
  SyncBadge.deviceOnly when s.state == SyncState.off => 'Bu telefonda kayıtlı',
  SyncBadge.deviceOnly => 'Bu telefonda kayıtlı (giriş yapınca yedeklenir)',
  SyncBadge.backedUp => 'Hesabına yedeklendi · ${agoTr(s.lastSyncedAt ?? now, now)}',
  SyncBadge.waiting => 'İnternet gelince yedeklenecek',
  SyncBadge.checking => 'Hesabınla eşitleniyor…',
};

class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key, this.center = false});

  /// Centred (lesson result) or left-aligned (Profil).
  final bool center;

  @override
  Widget build(BuildContext context) {
    // Screens shown without the app (e.g. a lesson result on its own) have
    // no sync to report.
    bool scoped;
    try {
      ProviderScope.containerOf(context, listen: false);
      scoped = true;
    } on StateError {
      scoped = false;
    }
    return scoped ? _SyncStatusRow(center: center) : const SizedBox.shrink();
  }
}

class _SyncStatusRow extends ConsumerWidget {
  const _SyncStatusRow({required this.center});
  final bool center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(progressSyncProvider);
    final now = ref.watch(clockProvider)();
    final badge = syncBadgeOf(status);
    final (icon, color) = switch (badge) {
      SyncBadge.deviceOnly => (Icons.phone_android_rounded, Brand.muted),
      SyncBadge.backedUp => (Icons.cloud_done_rounded, Brand.success),
      SyncBadge.waiting => (Icons.cloud_off_rounded, Brand.streak),
      SyncBadge.checking => (Icons.cloud_sync_rounded, Brand.muted),
    };
    return Row(
      key: Key('sync-status-${badge.name}'),
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            syncStatusText(status, now),
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
