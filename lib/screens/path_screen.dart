import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/startup_trace.dart';
import '../core/text.dart';
import '../data/course_repository.dart';
import '../data/exam_pack_repository.dart';
import '../data/exam_path.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../data/sections.dart';
import '../models/course.dart';
import '../models/exam.dart';
import '../nav/tab_navigator.dart';
import '../services/billing/exam_packs.dart';
import '../services/billing/products.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/flag.dart';
import '../ui/tea_art.dart';
import '../ui/theme_art.dart';
import '../data/topic_themes.dart';
import 'lesson_screen.dart';
import 'path_map.dart';
import 'reminder_settings.dart';
import 'section_header.dart';
import 'exam_screen.dart';
import 'story_screen.dart';
import 'topic_guide.dart';

export 'path_map.dart' show NodeState;

String formatWait(Duration d) => d.inMinutes >= 1 ? '${d.inMinutes} dk' : '${d.inSeconds} sn';

class PathScreen extends ConsumerWidget {
  const PathScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drawn from the outline; steps open from the full course (see _full).
    final course = ref.watch(courseOutlineProvider);
    return course.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Kurs yüklenemedi: $e')),
      data: (c) => _PathList(course: c),
    );
  }
}

class _PathList extends ConsumerStatefulWidget {
  const _PathList({required this.course});
  final Course course;

  @override
  ConsumerState<_PathList> createState() => _PathListState();
}

/// The node whose lesson card is open.
class _CardInfo {
  _CardInfo({
    required this.node,
    required this.unit,
    required this.state,
    required this.sectionOpen,
    required this.above,
    required this.dx,
    required this.width,
    required this.arrowX,
  });
  final PathNode node;
  final Unit unit;
  final NodeState state;
  final bool sectionOpen;
  final bool above;
  final double dx;
  final double width;
  final double arrowX;
}

class _PathListState extends ConsumerState<_PathList> {
  final _activeKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _scroll = ScrollController();
  final _card = OverlayPortalController();
  ValueListenable<int>? _reselected;

  /// One link per node, so the lesson card can follow its node.
  final _links = <String, LayerLink>{};

  /// Unit bands, to find which unit is under the pinned band.
  final _bandKeys = <String, GlobalKey>{};

  /// Active node the path was last scrolled to.
  String? _focusedId;

  /// Active node seen on the last build (a change means a step was finished).
  String? _seenActiveId;

  /// Scroll to the active node once the path is visible again.
  bool _focusPending = false;

  /// Newly reached node, briefly highlighted.
  String? _highlightId;
  Timer? _highlightTimer;

  /// Direction of the active node when it is off screen ("Bulunduğun yere dön").
  AxisDirection? _jump;

  /// Unit whose band is pinned to the top (scrolled past its own band).
  String? _pinnedUnit;

  /// How far the pinned band is pushed up by the next unit's band coming
  /// from below (0 or negative), so the two never overlap.
  double _pinnedShift = 0;
  final _pinnedKey = GlobalKey();

  _CardInfo? _cardInfo;

  bool get _visible => TickerMode.valuesOf(context).enabled;

  LayerLink _linkOf(String id) => _links.putIfAbsent(id, LayerLink.new);
  GlobalKey _bandKeyOf(String id) => _bandKeys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    StartupTrace.mark('path_build');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTrace.mark('path_drawn');
      // The path is on screen: now load the lessons (in a background
      // isolate), so the first tapped step opens without a wait.
      if (mounted && widget.course.outline) ref.read(courseProvider.future).ignore();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TabScope.maybeOf(context)?.reselected;
    if (next != _reselected) {
      _reselected?.removeListener(_onReselect);
      _reselected = next?..addListener(_onReselect);
    }
    // Became visible again (a lesson closed, or the tab was selected).
    if (_focusPending && _visible) _focusSoon();
  }

  @override
  void dispose() {
    _reselected?.removeListener(_onReselect);
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onReselect() {
    _hideCard();
    _focusSoon(force: true);
  }

  /// Brings the active node into view after this frame.
  void _focusSoon({bool force = false}) {
    _focusPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (!mounted || ctx == null || !ctx.mounted) {
        if (force && mounted && _scroll.hasClients) _animateTo(0);
        return;
      }
      _focusedId = _seenActiveId;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      ).then((_) => _afterScroll());
    });
  }

  void _animateTo(double offset) =>
      _scroll.animateTo(offset, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);

  /// Called on every build with the current active node.
  void _track(String? activeId, int activeIndex) {
    final previous = _seenActiveId;
    _seenActiveId = activeId;
    if (activeId == null) return;
    final first = previous == null && _focusedId == null;
    // On start only scroll once the user is past the first unit's opening steps.
    if (first && activeIndex <= 2) {
      _focusedId = activeId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterScroll());
      return;
    }
    if (activeId == _focusedId) return;
    if (!first) {
      _highlightTimer?.cancel();
      _highlightId = activeId;
      _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _highlightId = null);
      });
    }
    _focusedId = activeId;
    if (_visible) {
      _focusSoon();
    } else {
      _focusPending = true;
    }
  }

  /// Theme whose pictures were loaded ahead (the current unit's).
  String? _warmed;

  /// Loads the current unit's theme pictures once; the other units load as
  /// they come into view, and folded sections load nothing.
  void _warmTheme(Course course, PathNode? current) {
    final unit = current == null ? null : course.units.where((u) => u.nodes.contains(current)).firstOrNull;
    final theme = themeOf(unit ?? course.units.first);
    if (_warmed == theme.id) return;
    _warmed = theme.id;
    unawaited(precacheTheme(theme));
  }

  void _afterScroll() {
    _updateJump();
    _updatePinned();
  }

  RenderBox? get _viewport => _viewportKey.currentContext?.findRenderObject() as RenderBox?;

  void _updateJump() {
    if (!mounted) return;
    final tile = _activeKey.currentContext?.findRenderObject() as RenderBox?;
    final viewport = _viewport;
    AxisDirection? next;
    if (tile != null && viewport != null && tile.attached && tile.hasSize && viewport.hasSize) {
      final top = tile.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + tile.size.height;
      if (bottom < 0) next = AxisDirection.up;
      if (top > viewport.size.height) next = AxisDirection.down;
    }
    if (next != _jump) setState(() => _jump = next);
  }

  /// Pins the band of the unit being read: the last one whose own band has
  /// scrolled above the top edge.
  void _updatePinned() {
    if (!mounted) return;
    final viewport = _viewport;
    if (viewport == null || !viewport.hasSize) return;
    String? next;
    double? nextBandTop; // top of the first band below the pinned one
    for (final unit in widget.course.units) {
      final box = _bandKeys[unit.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top < -box.size.height * 0.5) {
        next = unit.id;
        nextBandTop = null;
      } else {
        nextBandTop ??= top;
      }
    }
    final pinnedBox = _pinnedKey.currentContext?.findRenderObject() as RenderBox?;
    final pinnedHeight = pinnedBox != null && pinnedBox.hasSize ? pinnedBox.size.height : 0.0;
    final shift = next == null || nextBandTop == null
        ? 0.0
        : (nextBandTop - pinnedHeight).clamp(-pinnedHeight, 0.0);
    if (next != _pinnedUnit || shift != _pinnedShift) {
      setState(() {
        _pinnedUnit = next;
        _pinnedShift = shift;
      });
    }
  }

  /// Sections the learner opened by hand ("üniteye göz at").
  final _expanded = <String>{};

  /// Sections shown unfolded without asking: the one with the current node,
  /// and open sections still in progress. Locked and finished sections start
  /// folded, so the path does not build hundreds of nodes up front.
  bool _autoExpanded(Section s, bool open, PathNode? current, Progress p) =>
      s.implicit ||
      (current != null && s.units.any((u) => u.nodes.contains(current))) ||
      (open && sectionProgress(s, p) < 1);

  bool _showUnits(Section s, bool open, PathNode? current, Progress p) =>
      _autoExpanded(s, open, current, p) || _expanded.contains(s.id);

  // ---- lesson card ------------------------------------------------------

  void _showCard(PathNode node, Unit unit, NodeState state, bool sectionOpen) {
    final viewport = _viewport;
    final ctx = _nodeContexts[node.id];
    final box = ctx != null && ctx.mounted ? ctx.findRenderObject() as RenderBox? : null;
    if (viewport == null || box == null || !box.hasSize) return;
    final center = box.localToGlobal(box.size.center(Offset.zero), ancestor: viewport);
    final w = viewport.size.width;
    final width = min(w - 32, 360.0);
    final left = (w - width) / 2;
    setState(() {
      _cardInfo = _CardInfo(
        node: node,
        unit: unit,
        state: state,
        sectionOpen: sectionOpen,
        above: center.dy > viewport.size.height * 0.55,
        dx: w / 2 - center.dx,
        width: width,
        arrowX: (center.dx - left).clamp(24.0, width - 24),
      );
    });
    _card.show();
  }

  void _hideCard() {
    if (_cardInfo == null) return;
    _card.hide();
    setState(() => _cardInfo = null);
  }

  /// Contexts of the round node buttons (to place the card).
  final _nodeContexts = <String, BuildContext>{};

  Widget _cardOverlay(BuildContext context) {
    final c = _cardInfo;
    if (c == null) return const SizedBox.shrink();
    final color = Brand.tone(c.unit.color);
    final lessons = c.unit.nodes.where((n) => n.type == NodeType.lesson).toList();
    final index = max(0, lessons.indexOf(c.node));
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('lesson-card-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: _hideCard,
          ),
        ),
        CompositedTransformFollower(
          link: _linkOf(c.node.id),
          showWhenUnlinked: false,
          targetAnchor: c.above ? Alignment.topCenter : Alignment.bottomCenter,
          followerAnchor: c.above ? Alignment.bottomCenter : Alignment.topCenter,
          offset: Offset(c.dx, c.above ? -6 : 6),
          child: SizedBox(
            width: c.width,
            child: _CardPop(
              above: c.above,
              child: LessonCard(
                node: c.node,
                state: c.state,
                color: color,
                position: index + 1,
                count: lessons.length,
                above: c.above,
                arrowX: c.arrowX,
                theme: themeOf(c.unit),
                note: c.node.type == NodeType.mock
                    ? mockSummary(
                        c.node.id,
                        ref.read(progressProvider).examBest,
                        ref.read(progressProvider).examSeconds,
                      )
                    : null,
                lockedMessage: c.sectionOpen
                    ? 'Önce önceki adımları tamamla.'
                    : 'Bu bölüm kilitli. Önceki bölümü bitir ya da "Bölüme atla" sınavını geç.',
                onStart: () {
                  _hideCard();
                  _open(c.node, c.unit, c.state);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- opening a step ----------------------------------------------------

  /// The course with its lessons: the path may be drawn from the outline
  /// (see courseOutlineProvider), which has none. Null when it failed to load.
  Future<Course?> _full() async {
    if (!widget.course.outline) return widget.course;
    try {
      final full = await ref.read(courseProvider.future);
      return full.id == widget.course.id ? full : null;
    } catch (e) {
      debugPrint('Kurs yüklenemedi: $e');
      return null;
    }
  }

  /// [unit] (and [node] in it) with their lessons, from [_full].
  Future<(Unit, PathNode?)?> _withContent(Unit unit, [PathNode? node]) async {
    final full = await _full();
    final u = full?.units.where((u) => u.id == unit.id).firstOrNull;
    if (u == null || !mounted) return null;
    if (node == null) return (u, null);
    final n = u.nodes.where((n) => n.id == node.id).firstOrNull;
    return n == null ? null : (u, n);
  }

  /// Path nodes by id, to give nodes of the full course their path state.
  late Map<String, PathNode> _pathNodes = _nodesOf(widget.course);
  static Map<String, PathNode> _nodesOf(Course c) => {for (final n in c.allNodes) n.id: n};

  @override
  void didUpdateWidget(covariant _PathList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course != widget.course) _pathNodes = _nodesOf(widget.course);
  }

  Future<void> _open(PathNode pathNode, Unit pathUnit, NodeState state) async {
    if (state == NodeState.locked) return;
    final resolved = await _withContent(pathUnit, pathNode);
    if (resolved == null || !mounted) return;
    final (unit, node!) = resolved;
    final nav = Navigator.of(context);
    final color = Brand.tone(unit.color);
    switch (node.type) {
      case NodeType.chest:
        if (state == NodeState.done) return;
        ref.read(progressProvider.notifier).completeNode(node.id, xp: node.rewardXp);
        await showDialog<void>(
          context: context,
          builder: (_) => _ChestDialog(xp: node.rewardXp, theme: themeOf(unit)),
        );
      case NodeType.story:
        await nav.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => StoryScreen(node: node, color: color),
          ),
        );
      case NodeType.test:
        LessonScreen build() => LessonScreen(
          nodeId: node.id,
          title: node.title,
          items: testItems(unit, node),
          color: color,
          mode: LessonMode.test,
          rewardXp: node.rewardXp,
          retry: build,
          // A test with its own questions is a named exam ("MİNİ LGS TESTİ").
          badge: node.exercises.isEmpty ? null : trUpper(node.title),
          passHeadline: node.exercises.isEmpty ? null : '${node.title} geçildi!',
        );
        await nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => build()));
      case NodeType.mock:
        await _openMock(node);
      case NodeType.lesson:
        if (!await _guideFirst(node, unit)) return;
        await nav.push(
          MaterialPageRoute<void>(builder: (_) => LessonScreen.forNode(node, color), fullscreenDialog: true),
        );
    }
  }

  /// Unit number inside its section ("ÜNİTE 3").
  int _numberOf(Unit unit) {
    for (final s in widget.course.sections) {
      final i = s.units.indexWhere((u) => u.id == unit.id);
      if (i >= 0) return i + 1;
    }
    return 1;
  }

  /// "Önce konuyu oku": before the first lesson of a unit with a topic guide,
  /// suggests reading it, once. Returns whether to start the lesson.
  Future<bool> _guideFirst(PathNode node, Unit unit) async {
    final p = ref.read(progressProvider);
    final first = unit.nodes.where((n) => n.type == NodeType.lesson).firstOrNull;
    if (!unit.hasGuide || node != first || p.guideSeen(unit.id) || p.isDone(node.id)) return true;
    final choice = await showGuideSuggestion(context, unit);
    if (choice == null || !mounted) return false;
    ref.read(progressProvider.notifier).markGuideSeen(unit.id);
    if (choice == GuideChoice.skip) return true;
    final start = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TopicGuideScreen(unit: unit, index: _numberOf(unit), startLabel: 'DERSE BAŞLA'),
      ),
    );
    return start == true && mounted;
  }

  /// A section mock: the exam engine (timer, blanks, answer key) on the
  /// section's questions, topped up from the exam's question bank.
  Future<void> _openMock(PathNode node) async {
    if (node.packId != null) return _openPackMock(node);
    final full = await _full();
    final section = full == null ? null : sectionOf(full, node);
    if (section == null) return;
    Exam? bank;
    if (node.examId case final id?) {
      try {
        bank = await ref.read(examProvider(id).future);
      } catch (e) {
        debugPrint('Deneme bankası yüklenemedi ($id): $e');
      }
    }
    if (!mounted) return;
    final questions = mockQuestions(section, node, bank: bank);
    if (questions.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ExamSessionScreen(
          exam: mockExam(node, bank, questions),
          questions: questions,
          mock: true,
          title: node.title,
          nodeId: node.id,
        ),
      ),
    );
  }

  /// A full mock of a paid pack (YDS Bölüm 4): opens it when the pack is
  /// unlocked, else the "Deneme sınavları" page where it can be bought.
  Future<void> _openPackMock(PathNode node) async {
    final pack = ExamPack.values.where((p) => '${p.examId}_full' == node.packId).firstOrNull;
    if (pack == null) return;
    final nav = Navigator.of(context);
    if (!ref.read(examPackUnlockedProvider(pack.examId))) {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Deneme sınavları')),
            body: ExamHomeScreen(examId: pack.examId, view: ExamHomeView.mocks),
          ),
        ),
      );
      return;
    }
    try {
      final content = await ref.read(examPackContentProvider(pack).future);
      final exam = await ref.read(examProvider(pack.examId).future);
      final full = content.mocks.where((m) => m.id == node.mockId).firstOrNull ?? content.mocks.first;
      if (!mounted) return;
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ExamSessionScreen(
            exam: exam,
            questions: full.questions,
            mock: true,
            title: full.title,
            minutes: full.minutes,
            pack: content,
            fullMock: full,
            nodeId: node.id,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Paket denemesi açılamadı (${node.packId}): $e');
    }
  }

  Future<void> _guide(Unit pathUnit, int index, NodeState Function(PathNode) stateOf) async {
    final unit = (await _withContent(pathUnit))?.$1;
    if (unit == null || !mounted) return;
    if (unit.hasGuide) ref.read(progressProvider.notifier).markGuideSeen(unit.id);
    await showUnitGuide(context, unit: unit, index: index, stateOf: (n) => stateOf(_pathNodes[n.id] ?? n));
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final p = ref.watch(progressProvider);
    final all = course.allNodes;
    // Each open section has its own next node; the path focuses on the one in
    // the furthest section (see currentNode).
    final active = {for (final n in activeNodes(course, p).values) n.id};
    final current = currentNode(course, p);
    final open = {for (final s in course.sections) s.id: sectionOpen(course, s, p)};
    _track(current?.id, current == null ? -1 : all.indexOf(current));
    _warmTheme(course, current);

    NodeState stateOf(PathNode n) {
      if (p.isDone(n.id)) return NodeState.done;
      if (n.type == NodeType.mock) return mockOpen(course, n, p) ? NodeState.active : NodeState.locked;
      return active.contains(n.id) ? NodeState.active : NodeState.locked;
    }

    final unitIndex = {for (final (i, u) in course.units.indexed) u.id: i};
    final pinned = _pinnedUnit == null ? null : course.units.where((u) => u.id == _pinnedUnit).firstOrNull;
    int numberInSection(Unit u) {
      final s = course.sections.firstWhere((s) => s.units.contains(u), orElse: () => course.sections.first);
      return s.units.indexOf(u) + 1;
    }

    return OverlayPortal(
      controller: _card,
      overlayChildBuilder: _cardOverlay,
      child: Stack(
        key: _viewportKey,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification && n.dragDetails != null) _hideCard();
              _afterScroll();
              return false;
            },
            // Not lazy: every node exists, so the active one can always be found.
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ReminderPromptCard(),
                  const _DailyGoalCard(),
                  if (ref.watch(trackProvider).id == 'pro_tourism') const GuestFlagsCard(),
                  const SizedBox(height: 20),
                  for (final section in course.sections) ...[
                    if (!section.implicit) ...[
                      SectionHeader(section: section, open: open[section.id]!),
                      const SizedBox(height: 8),
                      if (!_autoExpanded(section, open[section.id]!, current, p))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: ValueKey('section-toggle-${section.id}'),
                            icon: Icon(
                              _expanded.contains(section.id) ? Icons.expand_less : Icons.expand_more,
                            ),
                            label: Text(
                              _expanded.contains(section.id)
                                  ? 'Üniteleri gizle'
                                  : '${section.units.length} üniteye göz at',
                            ),
                            onPressed: () => setState(() {
                              if (!_expanded.remove(section.id)) _expanded.add(section.id);
                            }),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (_showUnits(section, open[section.id]!, current, p))
                      for (final unit in section.units) ...[
                        UnitBand(
                          key: _bandKeyOf(unit.id),
                          unit: unit,
                          index: section.units.indexOf(unit) + 1,
                          onGuide: () => _guide(unit, section.units.indexOf(unit) + 1, stateOf),
                        ),
                        const SizedBox(height: 18),
                        _UnitMap(
                          unit: unit,
                          mirror: unitIndex[unit.id]!.isOdd,
                          stateOf: stateOf,
                          current: current,
                          activeKey: _activeKey,
                          highlightId: _highlightId,
                          linkOf: _linkOf,
                          nodeContexts: _nodeContexts,
                          onNode: (n, st) => _showCard(n, unit, st, open[section.id]!),
                          onStart: (n, st) => _open(n, unit, st),
                        ),
                        const SizedBox(height: 24),
                      ],
                  ],
                  if (current == null)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Mascot(mood: Mood.cheer, size: 120),
                          SizedBox(height: 8),
                          Text(
                            'Tüm üniteleri bitirdin! Yeni üniteler yakında.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Sticky unit band: the unit being read stays on top with its guide.
          Positioned(
            left: 0,
            right: 0,
            top: _pinnedShift,
            child: KeyedSubtree(
              key: _pinnedKey,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: pinned == null
                    ? const SizedBox.shrink()
                    : ColoredBox(
                        key: ValueKey('pinned-${pinned.id}'),
                        color: Brand.background,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: UnitBand(
                            key: const Key('sticky-unit-band'),
                            unit: pinned,
                            index: numberInSection(pinned),
                            compact: true,
                            onGuide: () => _guide(pinned, numberInSection(pinned), stateOf),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          if (_jump != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: FloatingActionButton.extended(
                  key: const Key('back-to-current'),
                  heroTag: null,
                  onPressed: () => _focusSoon(force: true),
                  icon: Icon(
                    _jump == AxisDirection.up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  ),
                  label: const Text('Bulunduğun yere dön'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pops the lesson card in from its arrow (scale + fade, 200 ms).
class _CardPop extends StatelessWidget {
  const _CardPop({required this.above, required this.child});
  final bool above;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.85 + 0.15 * t,
          alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The nodes of one unit along a winding, dashed lane (a tea-garden walk),
/// with the host (Çaycı Dayı, or Pofuduk in Çocuk modu) beside them.
class _UnitMap extends StatelessWidget {
  const _UnitMap({
    required this.unit,
    required this.mirror,
    required this.stateOf,
    required this.current,
    required this.activeKey,
    required this.highlightId,
    required this.linkOf,
    required this.nodeContexts,
    required this.onNode,
    required this.onStart,
  });

  final Unit unit;
  final bool mirror;
  final NodeState Function(PathNode) stateOf;
  final PathNode? current;
  final GlobalKey activeKey;
  final String? highlightId;
  final LayerLink Function(String) linkOf;
  final Map<String, BuildContext> nodeContexts;
  final void Function(PathNode, NodeState) onNode;
  final void Function(PathNode, NodeState) onStart;

  /// Width of the column holding a node, its invite and its title.
  static const _colWidth = 150.0;

  /// Widest the invite bubble may be.
  static const _inviteWidth = 270.0;

  /// Height of the title under a node.
  static const _titleRoom = 34.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final p = context.palette;
      final w = box.maxWidth;
      final swing = laneSwing(w);
      final color = Brand.tone(unit.color);
      final mascotAt = mascotRow(unit);
      final unitDone = unit.nodes.every((n) => stateOf(n) == NodeState.done);
      final theme = themeOf(unit);
      // Node centres, for the lane drawn behind them.
      final centres = <Offset>[];
      var y = 0.0;
      final rows = <Widget>[];
      for (final (i, node) in unit.nodes.indexed) {
        final state = stateOf(node);
        final active = state == NodeState.active;
        final dx = laneOffset(i, mirror: mirror) * swing;
        final left = (w / 2 + dx - _colWidth / 2).clamp(0.0, max(0.0, w - _colWidth)).toDouble();
        final above = active ? balloonRoom : 0.0;
        final height = above + pathNodeHeight + _titleRoom;
        centres.add(Offset(w / 2 + dx, y + above + pathNodeHeight * 0.6));
        y += height;
        rows.add(
          SizedBox(
            key: node == current ? activeKey : ValueKey(node.id),
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (i == mascotAt)
                  Positioned(
                    top: max(0, (height - 110) / 2),
                    left: dx > 0 ? 4 : null,
                    right: dx > 0 ? null : 4,
                    child: PathMascot(mood: unitDone ? Mood.joy : Mood.calm, theme: theme),
                  ),
                // Roadside decorations on the far side of the lane, every other row.
                if (!theme.tea && i != mascotAt && i.isOdd && dx.abs() > swing * 0.3)
                  Positioned(
                    top: above + 18,
                    left: dx > 0 ? 18 : null,
                    right: dx > 0 ? null : 18,
                    child: RoadsideDecor(
                      key: Key('decor-${node.id}'),
                      theme: theme,
                      object: theme.decor[(i ~/ 2) % theme.decor.length],
                    ),
                  ),
                // The invite floats over the node, kept inside the path.
                if (active)
                  Positioned(
                    left: (w / 2 + dx - min(w, _inviteWidth) / 2).clamp(
                      0.0,
                      max(0.0, w - min(w, _inviteWidth)),
                    ),
                    width: min(w, _inviteWidth),
                    top: 0,
                    height: balloonRoom - 6,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: TeaInvite(
                        key: Key('tea-invite-${node.id}'),
                        label: nodeInvite(node.type, theme),
                        color: node.type == NodeType.chest ? Brand.accent : color,
                        onTap: () => onStart(node, state),
                      ),
                    ),
                  ),
                Positioned(
                  left: left,
                  width: _colWidth,
                  top: above,
                  child: NodeHighlight(
                    on: node.id == highlightId,
                    color: color,
                    child: Column(
                      children: [
                        Builder(
                          builder: (nodeContext) {
                            nodeContexts[node.id] = nodeContext;
                            return CompositedTransformTarget(
                              link: linkOf(node.id),
                              child: TeaNode(
                                key: Key('path-node-${node.id}'),
                                type: node.type,
                                state: state,
                                color: color,
                                semanticLabel: node.title,
                                theme: theme,
                                object: nodeObject(unit, node),
                                onTap: () => onNode(node, state),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onNode(node, state),
                          child: Text(
                            node.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              color: switch (state) {
                                NodeState.active => color,
                                NodeState.done => Brand.ink,
                                NodeState.locked => Brand.muted,
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              key: Key('lane-${unit.id}'),
              painter: LanePainter(
                points: centres,
                lane: Color.alphaBlend(color.withValues(alpha: p.isDark ? 0.12 : 0.08), p.surface),
                dash: color.withValues(alpha: 0.45),
              ),
            ),
          ),
          Column(children: rows),
        ],
      );
    },
  );
}

/// A soft glow around the node the user has just reached.
class NodeHighlight extends StatelessWidget {
  const NodeHighlight({super.key, required this.on, required this.color, required this.child});
  final bool on;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 400),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.xl),
      boxShadow: [if (on) BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 2)],
    ),
    child: child,
  );
}

class _DailyGoalCard extends ConsumerWidget {
  const _DailyGoalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final today = p.xpOn(ref.watch(clockProvider)());
    final ratio = (today / p.dailyGoal).clamp(0.0, 1.0);
    return TapCard(
      child: Row(
        children: [
          // The day's glass fills up with the daily goal.
          CustomPaint(
            key: const Key('daily-glass'),
            size: const Size(34, 44),
            painter: TeaGlassPainter(
              level: ratio,
              color: Brand.primary,
              palette: Brand.palette,
              goldRim: ratio >= 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ratio >= 1 ? 'Günlük hedef tamam!' : 'Günlük hedef',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                GlossyProgress(value: ratio, height: 12, color: ratio >= 1 ? Brand.success : Brand.accent),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$today / ${p.dailyGoal} XP',
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.muted),
          ),
        ],
      ),
    );
  }
}

/// The teapot rattles, its lid pops up and sugar cubes (the XP) tumble out.
class _ChestDialog extends StatefulWidget {
  const _ChestDialog({required this.xp, required this.theme});
  final int xp;

  /// Topic of the unit: the teapot, or the theme's surprise.
  final TopicTheme theme;

  @override
  State<_ChestDialog> createState() => _ChestDialogState();
}

class _ChestDialogState extends State<_ChestDialog> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    SessionFx.celebrate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      MediaQuery.disableAnimationsOf(context) ? _c.value = 1 : _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: TeaCelebration(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final wobble = t < 0.55 ? sin(t * pi * 14) * 0.18 * (1 - t / 0.55) : 0.0;
            final opened = t >= 0.55;
            final burst = opened ? Curves.elasticOut.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0)) : 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Transform.rotate(
                      angle: wobble,
                      child: Transform.scale(
                        scale: opened ? 0.9 + 0.3 * burst : 1,
                        child: widget.theme.tea
                            ? CustomPaint(
                                key: const Key('teapot-reward'),
                                size: const Size(110, 110),
                                painter: TeapotPainter(
                                  color: Brand.accent,
                                  palette: Brand.palette,
                                  open: opened,
                                ),
                              )
                            : ThemeObject(
                                key: const Key('theme-reward'),
                                theme: widget.theme,
                                object: widget.theme.reward,
                                size: 104,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: opened ? 1 : 0,
                  child: Column(
                    children: [
                      Text(widget.theme.rewardLine, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        widget.theme.tea
                            ? 'Çaydanlığın dibinden şeker çıktı; XP olarak hesabına geçti.'
                            : '${widget.theme.rewardName} açıldı; içinden çıkanlar XP olarak hesabına geçti.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Brand.muted),
                      ),
                      const SizedBox(height: 6),
                      CountUp(
                        value: opened ? widget.xp : 0,
                        prefix: '+',
                        suffix: ' XP',
                        style: TextStyle(color: Brand.xp, fontSize: 28, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PressableButton(
                  label: widget.theme.tea ? 'AFİYET OLSUN' : 'HARİKA',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
