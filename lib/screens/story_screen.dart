import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_result_screen.dart';

/// A short dialogue revealed line by line, with comprehension questions in
/// between. Lines are read aloud; tapping a bubble shows its translation.
class StoryScreen extends ConsumerStatefulWidget {
  const StoryScreen({super.key, required this.node, required this.color});
  final PathNode node;
  final Color color;

  @override
  ConsumerState<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends ConsumerState<StoryScreen> {
  final _scroll = ScrollController();
  final _started = DateTime.now();
  final Set<int> _translated = {};
  late final SpeechService _speech = ref.read(speechProvider);

  /// Steps revealed so far (index of the last visible step).
  int _shown = 0;

  /// Answer picked for the current question and whether it was right.
  String? _picked;
  bool? _pickedRight;
  int _questions = 0;
  int _wrong = 0;
  int _shake = 0;

  List<StoryStep> get _steps => widget.node.steps;
  StoryStep get _current => _steps[_shown];
  bool get _done => _shown >= _steps.length - 1 && (!_current.isQuestion || _pickedRight == true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrent());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _speakCurrent() {
    if (!_current.isQuestion) _speech.say(_current.text!);
  }

  void _next() {
    if (_done) {
      _finish();
      return;
    }
    setState(() {
      _shown++;
      _picked = null;
      _pickedRight = null;
    });
    _speakCurrent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _answer(String choice) {
    if (_pickedRight == true) return;
    final right = choice == _current.answer;
    setState(() {
      if (_picked == null) _questions++;
      _picked = choice;
      _pickedRight = right;
      if (!right) {
        _wrong++;
        _shake++;
      }
    });
    right ? Haptics.success() : Haptics.error();
  }

  void _finish() {
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          widget.node.id,
          xp: widget.node.rewardXp,
          answered: _questions + _wrong,
          correct: _questions,
          perfect: _wrong == 0,
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: _questions + _wrong == 0 ? 100 : (_questions * 100 / (_questions + _wrong)).round(),
          duration: DateTime.now().difference(_started),
          perfect: _wrong == 0,
          headline: 'Hikâye tamamlandı!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waitingAnswer = _current.isQuestion && _pickedRight != true;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Brand.muted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: GlossyProgress(value: (_shown + 1) / _steps.length, color: widget.color),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(child: Mascot(mood: _pickedRight == false ? Mood.think : Mood.idle, size: 90)),
                  const SizedBox(height: 4),
                  Text(
                    widget.node.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i <= _shown; i++)
                    PopIn(
                      key: ValueKey(i),
                      from: 0.85,
                      child: _steps[i].isQuestion ? _question(i) : _line(i),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Brand.line, width: 2)),
              ),
              child: PressableButton(
                label: _done ? 'BİTİR' : 'DEVAM',
                color: widget.color,
                onPressed: waitingAnswer ? null : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(int i) {
    final s = _steps[i];
    // Alternate sides per speaker so it reads like a chat.
    final speakers = <String>[];
    for (final st in _steps) {
      if (!st.isQuestion && !speakers.contains(st.speaker)) speakers.add(st.speaker!);
    }
    final right = speakers.indexOf(s.speaker!).isOdd;
    final showTr = _translated.contains(i);
    final avatar = CircleAvatar(
      radius: 22,
      backgroundColor: widget.color.withValues(alpha: 0.15),
      child: Text(s.avatar!, style: const TextStyle(fontSize: 24)),
    );
    final bubble = Flexible(
      child: GestureDetector(
        onTap: () {
          setState(() => showTr ? _translated.remove(i) : _translated.add(i));
          _speech.say(s.text!);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: right ? widget.color.withValues(alpha: 0.10) : Colors.white,
            border: Border.all(color: right ? widget.color.withValues(alpha: 0.5) : Brand.line, width: 2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(right ? 18 : 4),
              bottomRight: Radius.circular(right ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.speaker!,
                style: TextStyle(color: widget.color, fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(s.text!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: showTr && s.translation != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(s.translation!, style: const TextStyle(color: Brand.muted)),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: right
            ? [const SizedBox(width: 36), bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble, const SizedBox(width: 36)],
      ),
    );
  }

  Widget _question(int i) {
    final s = _steps[i];
    final active = i == _shown;
    return Shake(
      trigger: active ? _shake : 0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.help_rounded, color: Brand.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(s.prompt!, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 10),
            for (final c in s.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TapCard(
                  selected: (active && _picked == c) || (!active && c == s.answer),
                  color: (active ? _pickedRight == true : true) ? Brand.success : Brand.error,
                  onTap: active ? () => _answer(c) : null,
                  child: Text(c, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
