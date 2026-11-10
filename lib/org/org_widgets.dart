import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/notes_repository.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../screens/exam_screen.dart';
import '../screens/grammar_path_screen.dart';
import '../screens/lesson_screen.dart';
import '../screens/story_screen.dart';
import '../theme.dart';
import 'org.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// "Kurum" card in Profil: join with a code, or the org the user is in.
/// Hidden when Firebase is off.
class OrgSection extends ConsumerWidget {
  const OrgSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(orgServiceProvider) == null) return const SizedBox.shrink();
    final org = ref.watch(myOrgProvider);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kurum', style: t.titleLarge),
          const SizedBox(height: 8),
          switch (org) {
            AsyncData(value: final MyOrg o) => _OrgCard(org: o),
            AsyncLoading() => const TapCard(child: LinearProgressIndicator()),
            _ => TapCard(
              onTap: () => showJoinOrgDialog(context, ref),
              child: Row(
                children: [
                  const IconBadge(icon: Icons.apartment_rounded, emoji: '🏢'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kurum koduyla katıl', style: TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          'Otelin, şirketin ya da okulun sana bir kod verdiyse buraya gir. '
                          'Premium kurumundan gelir.',
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Brand.muted),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }
}

class _OrgCard extends ConsumerWidget {
  const _OrgCard({required this.org});
  final MyOrg org;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${org.name} kurumundan ayrılınsın mı?'),
        content: const Text(
          'Kurumdan gelen Premium biter ve ödevlerin artık görünmez. '
          'Kendi ilerlemen, XP ve serin sende kalır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Ayrıl', style: TextStyle(color: Brand.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(orgServiceProvider)!.leave();
      ref.invalidate(myOrgProvider);
      messenger.showSnackBar(SnackBar(content: Text('${org.name} kurumundan ayrıldın.')));
    } on OrgException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => TapCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(
              icon: org.isSchool ? Icons.school_rounded : Icons.apartment_rounded,
              emoji: org.isSchool ? '🏫' : '🏢',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(org.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                    [org.role.label, if (org.classes.isNotEmpty) org.classes.join(', ')].join(' · '),
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          org.role == OrgRole.admin
              ? 'Kurumu web panelinden yönetebilirsin.'
              : 'Premium ${_date(org.planExpiresAt)} tarihine kadar kurumundan.',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Kurumun yalnızca ders, XP, seri ve ödev durumunu görür; günlüğün, notların ve '
          'sohbetlerin sende kalır.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => _leave(context, ref), child: const Text('Kurumdan ayrıl')),
        ),
      ],
    ),
  );
}

Future<void> showJoinOrgDialog(BuildContext context, WidgetRef ref) async {
  final name = await showDialog<String>(context: context, builder: (_) => const JoinOrgDialog());
  if (name == null || !context.mounted) return;
  ref.invalidate(myOrgProvider);
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$name kurumuna katıldın! ${kidEmoji('🎉')}'.trim())));
}

/// Code + name form. Pops with the org's name once joined.
class JoinOrgDialog extends ConsumerStatefulWidget {
  const JoinOrgDialog({super.key});

  @override
  ConsumerState<JoinOrgDialog> createState() => _JoinOrgDialogState();
}

class _JoinOrgDialogState extends ConsumerState<JoinOrgDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _cleanCode => _code.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  Future<void> _submit() async {
    if (_cleanCode.length != 8) {
      setState(() => _error = 'Kod 8 karakterden oluşur, örneğin K7QM-3XPA.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Kurumunun seni tanıması için adını yaz.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final org = await ref.read(orgServiceProvider)!.join(code: _cleanCode, displayName: _name.text.trim());
      if (mounted) Navigator.pop(context, org);
    } on OrgException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Kurum koduyla katıl'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('org-code'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            decoration: const InputDecoration(
              labelText: 'Kurum kodu',
              hintText: 'K7QM-3XPA',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('org-name'),
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Adın soyadın', counterText: ''),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Kurumun yalnızca ders sayını, XP, seri ve ödev durumunu görür. '
            'Günlüğün, notların ve sohbetlerin paylaşılmaz.',
            style: TextStyle(color: Brand.muted, fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Brand.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Katıl'),
      ),
    ],
  );
}

/// "Ödevlerim" card on the Öğren tab: shown only while the learner has
/// unfinished assignments.
class OrgAssignmentsCard extends ConsumerWidget {
  const OrgAssignmentsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(myOrgProvider).value;
    if (org == null || org.assignments.isEmpty) return const SizedBox.shrink();
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final pending = [
      for (final a in org.assignments)
        if (!a.isDone(p)) a,
    ];
    if (pending.isEmpty) return const SizedBox.shrink();
    final late = pending.where((a) => a.status(p, now) == AssignmentStatus.late).length;
    final next = pending.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TapCard(
        color: late > 0 ? Brand.errorBg : null,
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AssignmentsScreen())),
        child: Row(
          children: [
            IconBadge(icon: Icons.assignment_outlined, emoji: '📋', color: late > 0 ? Brand.error : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ödevlerim · ${pending.length} bekliyor',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    late > 0 ? '$late ödevin süresi geçti' : 'Sıradaki: ${next.title} · ${_date(next.dueAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: late > 0 ? Brand.error : Brand.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Brand.muted),
          ],
        ),
      ),
    );
  }
}

class AssignmentsScreen extends ConsumerWidget {
  const AssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(myOrgProvider).value;
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final list = org?.assignments ?? const <OrgAssignment>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Ödevlerim')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myOrgProvider.future),
        child: list.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Şu an ödevin yok. ${kidEmoji('🎉')}'.trim(), textAlign: TextAlign.center),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final a = list[i];
                  final status = a.status(p, now);
                  final (label, color) = switch (status) {
                    AssignmentStatus.done => ('Tamamlandı', Brand.success),
                    AssignmentStatus.late => ('Süresi geçti', Brand.error),
                    AssignmentStatus.open => ('Son gün ${_date(a.dueAt)}', Brand.muted),
                  };
                  return TapCard(
                    onTap: () => openAssignment(context, a),
                    child: Row(
                      children: [
                        Icon(
                          status == AssignmentStatus.done
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: color,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                [a.kind.label, if (a.className.isNotEmpty) a.className, label].join(' · '),
                                style: TextStyle(color: color, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.play_arrow_rounded, color: Brand.primary),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Opens the screen an assignment points to.
Future<void> openAssignment(BuildContext context, OrgAssignment a, {AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void missing() => messenger.showSnackBar(
    const SnackBar(content: Text('Bu ödev bu uygulama sürümünde açılamıyor. Uygulamayı güncelle.')),
  );
  try {
    switch (a.kind) {
      case AssignmentKind.lesson:
        final course = await loadCourse(assets, a.courseId);
        for (final unit in course.units) {
          for (final node in unit.nodes.where((n) => n.id == a.targetId)) {
            await nav.push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => node.type == NodeType.story
                    ? StoryScreen(node: node, color: unit.color)
                    : LessonScreen.forNode(node, unit.color),
              ),
            );
            return;
          }
        }
        missing();
      case AssignmentKind.grammar:
        final lesson = (await loadLessons(assets)).where((l) => l.id == a.targetId).firstOrNull;
        if (lesson == null) return missing();
        final notes = await loadNotes(assets);
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => GrammarLessonScreen(lesson: lesson, notes: notes),
          ),
        );
      case AssignmentKind.exam:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(a.title)),
              body: ExamHomeScreen(examId: a.targetId),
            ),
          ),
        );
    }
  } on Exception {
    missing();
  } on FlutterError {
    missing(); // asset not found
  }
}
