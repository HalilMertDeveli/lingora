import 'package:flutter/material.dart';

import '../../study/methods.dart';
import '../../theme.dart';

/// Opens "Nasıl öğretiyoruz?", scrolled to the card [focus] (a method id).
void openMethods(BuildContext context, {String? focus}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MethodsScreen(focus: focus)));

/// "Nasıl öğretiyoruz?": each method in three lines: Ne? / Neden? /
/// Dilbaz'da nerede?
class MethodsScreen extends StatefulWidget {
  const MethodsScreen({super.key, this.focus});
  final String? focus;

  @override
  State<MethodsScreen> createState() => _MethodsScreenState();
}

class _MethodsScreenState extends State<MethodsScreen> {
  final _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _focusKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nasıl öğretiyoruz?')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dilbaz\'daki YDS programı öğrenme üzerine yapılmış araştırmalara dayanıyor. '
            'Hangi yöntemi neden ve nerede kullandığımızı kısaca anlattık.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          for (final m in studyMethods)
            _MethodCard(
              key: m.id == widget.focus ? _focusKey : null,
              method: m,
              highlighted: m.id == widget.focus,
            ),
          const SizedBox(height: 8),
          Text(
            'Ayrıntılı gerekçe ve kaynak listesi: $methodsSourceDoc',
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({super.key, required this.method, this.highlighted = false});
  final StudyMethod method;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(fontWeight: FontWeight.w900, color: Brand.tone(Brand.primary)),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TapCard(
        key: Key('method-${method.id}'),
        selected: highlighted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(method.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(child: Text(method.title, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            line('Ne?', method.what),
            line('Neden?', method.why),
            line('Nerede?', method.where),
          ],
        ),
      ),
    );
  }
}
