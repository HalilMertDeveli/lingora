import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../data/vocab_practice.dart';
import '../../exercises/common.dart';
import '../../models/vocab.dart';
import '../../theme.dart';
import '../../ui/motion.dart';
import 'review_screen.dart';
import 'vocab_home_screen.dart';

/// Words shown per "Kelime keşfet" round.
const discoverRound = 10;

/// "Kelime keşfet": sort new words into Biliyorum / Öğreneceğim / Sonra.
/// Words to learn go straight into the review queue; at the end the user
/// can review them right away.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, required this.all, this.topic});
  final List<VocabEntry> all;
  final String? topic;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final List<VocabEntry> _cards = triageQueue(
    widget.all,
    ref.read(progressProvider),
    topic: widget.topic,
  ).take(discoverRound).toList();
  int _pos = 0;
  bool _revealed = false;
  final _learn = <VocabEntry>[];
  int _known = 0;
  int _later = 0;

  void _sort(bool? known) {
    final e = _cards[_pos];
    if (known != null) ref.read(progressProvider.notifier).triageWord(e.id, known: known);
    setState(() {
      if (known == true) _known++;
      if (known == false) _learn.add(e);
      if (known == null) _later++;
      _pos++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _pos >= _cards.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelime keşfet'),
        bottom: done
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _pos / _cards.length, color: vocabColor),
              ),
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: done ? _summary(context) : _card(context)),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final e = _cards[_pos];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TapCard(
            key: ValueKey(e.id),
            onTap: _revealed ? null : () => setState(() => _revealed = true),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Text('#${e.rank} · ${e.topic}', style: TextStyle(color: Brand.muted)),
                  const SizedBox(height: 16),
                  Text(
                    e.word,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                  ),
                  Text(e.posTr, style: TextStyle(color: Brand.muted)),
                  const SizedBox(height: 12),
                  SpeakerButton(text: e.word),
                  const SizedBox(height: 16),
                  Text(
                    e.examples.first.en,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                  if (_revealed) ...[
                    Text(
                      e.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: vocabColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.examples.first.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Brand.muted),
                    ),
                    if (e.tip != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${kidEmoji('💡')}${e.tip}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ] else
                    Text('Anlamı görmek için dokun', style: TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: PressableButton(label: 'SONRA', outlined: true, onPressed: () => _sort(null)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PressableButton(
                label: 'ÖĞRENECEĞİM',
                color: Brand.accent,
                onPressed: () => _sort(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PressableButton(label: 'BİLİYORUM', color: Brand.success, onPressed: () => _sort(true)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Glyph(emoji: '🎯', icon: Icons.flag_rounded, size: 56, color: vocabColor),
      ),
      const SizedBox(height: 12),
      Text('Tur bitti!', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        '$_known biliyorum · ${_learn.length} öğreneceğim · $_later sonra',
        textAlign: TextAlign.center,
        style: TextStyle(color: Brand.muted),
      ),
      const SizedBox(height: 24),
      if (_learn.isNotEmpty)
        PressableButton(
          label: 'ŞİMDİ ÖĞREN (${_learn.length})',
          color: vocabColor,
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => VocabReviewScreen(queue: _learn, all: widget.all),
            ),
          ),
        ),
      const SizedBox(height: 8),
      PressableButton(label: 'KAPAT', outlined: true, onPressed: () => Navigator.of(context).pop()),
    ],
  );
}
