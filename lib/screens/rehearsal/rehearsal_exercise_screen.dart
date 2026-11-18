import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/rehearsal.dart';
import '../../theme.dart';

/// One exercise built from the learner's own sentence: fix it, fill the
/// blank or put the words in order. A wrong check or a shown answer is
/// counted, so the comparison can list the tasks done without help.
class RehearsalExerciseScreen extends ConsumerStatefulWidget {
  const RehearsalExerciseScreen({
    super.key,
    required this.taskId,
    required this.exercise,
    required this.index,
  });
  final String taskId;
  final RehearsalExercise exercise;
  final int index;

  @override
  ConsumerState<RehearsalExerciseScreen> createState() => _RehearsalExerciseScreenState();
}

class _RehearsalExerciseScreenState extends ConsumerState<RehearsalExerciseScreen> {
  final _attempt = TaskAttempt();
  late final _text = TextEditingController(
    text: widget.exercise.kind == ExerciseKind.fixSentence ? widget.exercise.prompt : '',
  );
  final _picked = <int>[];
  bool? _right;
  bool _shown = false;

  RehearsalExercise get _x => widget.exercise;

  String get _given =>
      _x.kind == ExerciseKind.reorder ? [for (final i in _picked) _x.words[i]].join(' ') : _text.text;

  void _check() {
    final ok = _x.accepts(_given);
    setState(() => _right = ok);
    if (ok) {
      ref.read(rehearsalProvider.notifier).completeTask(widget.taskId, _title, _attempt);
    } else {
      _attempt.wrong();
    }
  }

  String get _title => switch (_x.kind) {
    ExerciseKind.fixSentence => 'Düzelt: ${_x.answer}',
    ExerciseKind.fillBlank => 'Boşluk: ${_x.prompt.replaceFirst(RegExp(r'_{3,}'), _x.answer)}',
    ExerciseKind.reorder => 'Sırala: ${_x.answer}',
  };

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('Alıştırma ${widget.index + 1}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_x.instructionTr, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(grammarTagNames[_x.tag] ?? '', style: TextStyle(color: p.muted)),
          const SizedBox(height: 16),
          if (_x.kind == ExerciseKind.fillBlank) ...[
            Text(_x.prompt, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
          ],
          if (_x.kind == ExerciseKind.reorder) ...[
            Container(
              key: const Key('prova-reorder-built'),
              constraints: const BoxConstraints(minHeight: 56),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final i in _picked)
                    InputChip(
                      label: Text(_x.words[i]),
                      onPressed: () => setState(() {
                        _picked.remove(i);
                        _right = null;
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _x.words.length; i++)
                  if (!_picked.contains(i))
                    ActionChip(
                      key: Key('prova-word-$i'),
                      label: Text(_x.words[i]),
                      onPressed: () => setState(() {
                        _picked.add(i);
                        _right = null;
                      }),
                    ),
              ],
            ),
          ] else
            TextField(
              key: const Key('prova-ex-field'),
              controller: _text,
              maxLines: _x.kind == ExerciseKind.fixSentence ? 3 : 1,
              onChanged: (_) => setState(() => _right = null),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _x.kind == ExerciseKind.fixSentence ? 'Düzeltilmiş cümle' : 'Boşluğa gelen',
              ),
            ),
          const SizedBox(height: 16),
          if (_right == true)
            Text(
              _attempt.hints == 0 && _attempt.retries == 0 ? 'Doğru, hem de yardımsız!' : 'Doğru!',
              key: const Key('prova-ex-right'),
              style: TextStyle(color: p.success, fontWeight: FontWeight.w700),
            )
          else if (_right == false)
            Text('Tam değil, bir daha dene.', style: TextStyle(color: p.error)),
          if (_shown) ...[
            const SizedBox(height: 8),
            Text('Doğrusu: ${_x.answer}', key: const Key('prova-ex-answer')),
          ],
          const SizedBox(height: 16),
          if (_right == true)
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam'))
          else ...[
            FilledButton(
              key: const Key('prova-check'),
              onPressed: _given.trim().isEmpty ? null : _check,
              child: const Text('Kontrol et'),
            ),
            if (!_shown)
              TextButton(
                key: const Key('prova-show-answer'),
                onPressed: () => setState(() {
                  _attempt.hint();
                  _shown = true;
                }),
                child: const Text('Cevabı göster'),
              ),
          ],
        ],
      ),
    );
  }
}
