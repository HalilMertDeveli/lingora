import 'admin_api.dart';

/// Members report as CSV for Excel in Turkish locale: `;` separated, with a
/// UTF-8 BOM so "ş, ğ, ı" show correctly. Only learning numbers, never
/// personal content (KVKK).
String membersCsv(OrgReport r) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    // Quote when needed; a leading =,+,-,@ would run as a formula in Excel.
    final safe = RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
    return RegExp('[";\n\r]').hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
  }

  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final rows = <List<Object?>>[
    [
      'Ad Soyad',
      'Rol',
      'Sınıflar',
      'Tamamlanan ders',
      'Toplam XP',
      'Son 7 gün XP',
      'Seri (gün)',
      'Son aktif gün',
      'Ödev (tamam)',
      'Ödev (geciken)',
      'Ödev (toplam)',
      'Katılım',
    ],
    for (final m in r.members)
      [
        m.displayName,
        m.role.label,
        m.classIds.map(r.className).where((n) => n.isNotEmpty).join(', '),
        m.lessonsDone,
        m.totalXp,
        m.weekXp,
        m.streak,
        m.lastActiveDay ?? '',
        m.assignmentsDone,
        m.assignmentsLate,
        m.assignments.length,
        m.joinedAt.millisecondsSinceEpoch == 0 ? '' : date(m.joinedAt),
      ],
  ];
  return '﻿${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
}
