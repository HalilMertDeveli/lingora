import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/billing/premium.dart';
import '../services/explain_more.dart';
import '../services/growth/analytics_events.dart' show PaywallPlacement;
import '../theme.dart';
import 'premium_offer.dart';

/// Under "Neden yanlış?": "Anlamadım", "Daha basit anlat" or the learner's
/// own question about this exact question, answered by the `explainMore`
/// function in short, simple Turkish. Premium only (free users get the
/// Premium card on tap); hidden in Çocuk modu, which has no AI chat.
class ExplainMoreBox extends ConsumerStatefulWidget {
  const ExplainMoreBox({super.key, required this.question});
  final ExplainQuestion question;

  @override
  ConsumerState<ExplainMoreBox> createState() => _ExplainMoreBoxState();
}

class _ExplainMoreBoxState extends ConsumerState<ExplainMoreBox> {
  final _turns = <ExplainTurn>[];
  final _text = TextEditingController();
  bool _asking = false;
  bool _typing = false;
  bool _offer = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _usedUp => _turns.length >= maxFollowUpsPerQuestion;

  Future<void> _ask(ExplainMode mode) async {
    if (_asking || _usedUp) return;
    if (!ref.read(premiumProvider)) {
      setState(() => _offer = true);
      return;
    }
    if (mode == ExplainMode.question && !_typing) {
      setState(() => _typing = true);
      return;
    }
    final text = _text.text.trim();
    if (mode == ExplainMode.question && text.isEmpty) return;
    final service = ref.read(explainMoreServiceProvider);
    if (service == null) {
      setState(() => _error = 'Ek açıklama için internet ve giriş gerekir.');
      return;
    }
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final a = await service.ask(widget.question, mode, text: text, history: List.of(_turns));
      if (!mounted) return;
      setState(() {
        _turns.add(ExplainTurn(mode == ExplainMode.question ? text : mode.label, a.text));
        _text.clear();
        _typing = false;
      });
    } on ExplainMoreException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.isKid) return const SizedBox.shrink();
    final premium = ref.watch(premiumProvider);
    final p = context.palette;
    return Container(
      key: const Key('explain-more'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 18, color: p.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Hâlâ takıldın mı?',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: p.ink),
                ),
              ),
              if (!premium) Icon(Icons.lock_rounded, size: 16, color: p.muted),
            ],
          ),
          for (final (i, t) in _turns.indexed) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  t.q,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.a,
              key: Key('explain-answer-$i'),
              style: TextStyle(color: p.ink, height: 1.4),
            ),
          ],
          if (_asking) ...[
            const SizedBox(height: 10),
            const Center(
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('explain-error'),
              style: TextStyle(color: p.error),
            ),
          ],
          if (_typing && !_usedUp) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('explain-input'),
              controller: _text,
              maxLength: maxFollowUpChars,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _ask(ExplainMode.question),
              decoration: InputDecoration(
                hintText: 'Bu soruyla ilgili ne sormak istersin?',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Gönder',
                  key: const Key('explain-send'),
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _asking ? null : () => _ask(ExplainMode.question),
                ),
              ),
            ),
          ],
          if (!_usedUp && !_asking) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in ExplainMode.followUps)
                  if (!(m == ExplainMode.question && _typing))
                    ActionChip(
                      key: Key('explain-${m.name}'),
                      avatar: Icon(switch (m) {
                        ExplainMode.confused => Icons.help_outline_rounded,
                        ExplainMode.simpler => Icons.child_care_rounded,
                        ExplainMode.question => Icons.edit_rounded,
                        ExplainMode.why => Icons.search_rounded,
                      }, size: 18),
                      label: Text(m.label),
                      onPressed: () => _ask(m),
                    ),
              ],
            ),
          ] else if (_usedUp) ...[
            const SizedBox(height: 8),
            Text(
              'Bu soru için ek açıklama hakkı bitti; Notlarım\'daki konu anlatımına da bakabilirsin.',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          ],
          if (_offer && !premium) ...[
            const SizedBox(height: 10),
            const PremiumOfferCard(
              placement: PaywallPlacement.explainMore,
              dense: true,
              icon: Icons.forum_outlined,
              title: 'Takıldığın soruyu yapay zekâya sor',
              body: "Premium'da \"Anlamadım\", \"Daha basit anlat\" ya da kendi sorun; o soruya özel, sade Türkçe cevap.",
            ),
          ],
        ],
      ),
    );
  }
}
