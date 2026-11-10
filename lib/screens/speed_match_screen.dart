import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_result_screen.dart';

const speedMatchSeconds = 60;
const _pairsPerBoard = 5;

/// XP for a speed-match run: one per two pairs, at most 20.
int speedMatchXp(int matched) => min(20, matched ~/ 2);

/// Match as many word pairs as possible before the clock runs out. A wrong
/// pair costs two seconds; clearing a board brings a fresh one.
class SpeedMatchScreen extends ConsumerStatefulWidget {
  const SpeedMatchScreen({super.key, required this.pool});
  final List<(String, String)> pool;

  @override
  ConsumerState<SpeedMatchScreen> createState() => _SpeedMatchScreenState();
}

class _SpeedMatchScreenState extends ConsumerState<SpeedMatchScreen> {
  final _rand = Random();
  final _started = DateTime.now();
  Timer? _timer;
  int _left = speedMatchSeconds * 10; // tenths of a second
  bool _running = false;

  List<(String, String)> _board = [];
  List<int> _leftOrder = [];
  List<int> _rightOrder = [];
  final Set<int> _matched = {};
  int? _selL, _selR;
  int _matchedTotal = 0;
  int _wrongTotal = 0;
  int _shake = 0;
  int _boards = 0;

  @override
  void initState() {
    super.initState();
    _newBoard();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _end();
    });
  }

  void _newBoard() {
    final pool = [...widget.pool]..shuffle(_rand);
    // Avoid two pairs with the same Turkish or English word on one board.
    final seenTr = <String>{}, seenEn = <String>{};
    final board = <(String, String)>[];
    for (final p in pool) {
      if (seenTr.add(p.$1) && seenEn.add(p.$2)) board.add(p);
      if (board.length == _pairsPerBoard) break;
    }
    _board = board;
    _leftOrder = List.generate(board.length, (i) => i)..shuffle(_rand);
    _rightOrder = List.generate(board.length, (i) => i)..shuffle(_rand);
    _matched.clear();
    _selL = _selR = null;
    _boards++;
  }

  void _tap({int? l, int? r}) {
    if (!_running) return;
    setState(() {
      if (l != null) _selL = l;
      if (r != null) _selR = r;
    });
    final a = _selL, b = _selR;
    if (a == null || b == null) return;
    setState(() {
      if (a == b) {
        _matched.add(a);
        _matchedTotal++;
        Haptics.success();
        if (_matched.length == _board.length) _newBoard();
      } else {
        _wrongTotal++;
        _shake++;
        _left = max(0, _left - 20);
        Haptics.error();
      }
      _selL = _selR = null;
    });
  }

  void _end() {
    _timer?.cancel();
    if (!_running) return;
    _running = false;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          'speed',
          xp: speedMatchXp(_matchedTotal),
          answered: _matchedTotal + _wrongTotal,
          correct: _matchedTotal,
          perfect: _wrongTotal == 0 && _matchedTotal > 0,
        );
    final total = _matchedTotal + _wrongTotal;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: total == 0 ? 0 : (_matchedTotal * 100 / total).round(),
          duration: DateTime.now().difference(_started),
          perfect: _wrongTotal == 0 && _matchedTotal > 0,
          headline: '$_matchedTotal eş buldun!',
        ),
      ),
    );
  }

  Widget _cell(String text, int i, {required bool left}) {
    final matched = _matched.contains(i);
    final sel = left ? _selL == i : _selR == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: matched ? 0 : 1,
        child: TapCard(
          selected: sel,
          onTap: matched ? null : () => left ? _tap(l: i) : _tap(r: i),
          child: SizedBox(
            height: 30,
            child: Center(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secs = (_left / 10).ceil();
    final low = secs <= 10;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Brand.muted),
                    onPressed: () {
                      _timer?.cancel();
                      Navigator.of(context).pop();
                    },
                  ),
                  Expanded(
                    child: GlossyProgress(
                      value: _left / (speedMatchSeconds * 10),
                      color: low ? Brand.error : Brand.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.timer_rounded, color: low ? Brand.error : Brand.accent),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '$secs',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: low ? Brand.error : Brand.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Hızlı eşleştirme', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  PopIn(
                    key: ValueKey(_matchedTotal),
                    from: 0.7,
                    child: Text(
                      '✓ $_matchedTotal',
                      style: const TextStyle(color: Brand.success, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: !_running
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Mascot(mood: Mood.think, size: 120),
                          const SizedBox(height: 16),
                          const Text(
                            '$speedMatchSeconds saniyede bulabildiğin kadar eş bul.\nYanlış eşleşme 2 saniye götürür.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Brand.muted, height: 1.4),
                          ),
                          const SizedBox(height: 24),
                          PressableButton(label: 'BAŞLA', color: Brand.accent, onPressed: _start),
                        ],
                      )
                    : Shake(
                        trigger: _shake,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Row(
                            key: ValueKey(_boards),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [for (final i in _leftOrder) _cell(_board[i].$1, i, left: true)],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  children: [
                                    for (final i in _rightOrder) _cell(_board[i].$2, i, left: false),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
