import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/billing/premium.dart';
import '../services/explain_more.dart';
import '../services/growth/analytics_events.dart' show PaywallPlacement;
import '../theme.dart';
import 'premium_offer.dart';

/// The error notebook's "İncele": with Premium the `explainMore` function
/// (mode `why`) says what kind of mistake it was and why the learner's
/// option is wrong; free learners get the Premium card (the app's own
/// rule-based reason is already on the card). When the server does not see
/// Premium (a purchase not verified yet, a test build) the app keeps its own
/// reason and says so calmly instead of showing a server error. Hidden in
/// Çocuk modu, which has no AI chat.
class MistakeInspect extends ConsumerStatefulWidget {
  const MistakeInspect({super.key, required this.question});
  final ExplainQuestion question;

  @override
  ConsumerState<MistakeInspect> createState() => _MistakeInspectState();
}

class _MistakeInspectState extends ConsumerState<MistakeInspect> {
  bool _asking = false;
  bool _offer = false;
  String? _answer;
  String? _error;

  /// The server said "not Premium": no retry, the local reason stays.
  bool _notPremium = false;

  Future<void> _inspect() async {
    if (_asking) return;
    if (!ref.read(premiumProvider)) {
      setState(() => _offer = true);
      return;
    }
    final service = ref.read(explainMoreServiceProvider);
    if (service == null) {
      setState(
        () => _error = 'Yapay zekâ incelemesi için internet ve giriş gerekir. Yukarıdaki neden uygulamanın kendi analizi.',
      );
      return;
    }
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final a = await service.ask(widget.question, ExplainMode.why);
      if (mounted) setState(() => _answer = a.text);
    } on ExplainMoreException catch (e) {
      if (mounted) {
        setState(() {
          _notPremium = e.notPremium;
          _error = e.notPremium
              ? 'Premium üyeliğin henüz doğrulanamadı, bu yüzden yapay zekâ incelemesi açılmadı. '
                    'Yukarıdaki neden uygulamanın kendi analizi.'
              : e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.isKid) return const SizedBox.shrink();
    final premium = ref.watch(premiumProvider);
    final p = context.palette;
    return Column(
      key: const Key('mistake-inspect'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_answer == null && !_notPremium)
          Align(
            alignment: Alignment.centerLeft,
            child: _asking
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : OutlinedButton.icon(
                    key: const Key('mistake-inspect-button'),
                    onPressed: _inspect,
                    icon: Icon(premium ? Icons.auto_awesome_rounded : Icons.lock_rounded, size: 18),
                    label: Text(_error == null ? 'İncele: neden yanlış yaptım?' : 'Tekrar dene'),
                  ),
          ),
        if (_answer case final a?)
          Container(
            key: const Key('mistake-inspect-answer'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18, color: p.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a, style: TextStyle(color: p.ink, height: 1.4)),
                ),
              ],
            ),
          ),
        if (_error case final e?) ...[
          const SizedBox(height: 6),
          Text(
            e,
            key: const Key('mistake-inspect-error'),
            style: TextStyle(color: _notPremium ? p.muted : p.error, fontSize: 13),
          ),
        ],
        if (_offer && !premium) ...[
          const SizedBox(height: 8),
          const PremiumOfferCard(
            placement: PaywallPlacement.explainMore,
            dense: true,
            icon: Icons.auto_awesome_rounded,
            title: 'Hatanı yapay zekâ incelesin',
            body: "Premium'da her yanlış için: hata türü, seçtiğin şıkkın neden çeldirici olduğu ve bir sonraki soruya ipucu.",
          ),
        ],
      ],
    );
  }
}
