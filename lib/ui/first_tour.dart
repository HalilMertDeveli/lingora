import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../nav/nav_target.dart';
import '../theme.dart';

/// Set once the first tour was finished or skipped.
const tourDoneKey = 'tour_v1_done';

/// One stop of the tour: a bottom tab and a single sentence about it.
typedef TourStep = ({int tab, String title, String text});

/// At most four short stops over the bottom tabs, in tab order.
List<TourStep> tourSteps(List<AppTab> tabs) {
  String? title(AppTab t) => switch (t) {
    AppTab.learn => 'Yolun burada',
    AppTab.practice => 'Pratik',
    AppTab.league => 'Lig ve arkadaşlar',
    AppTab.profile => 'Profilin',
    AppTab.discover => 'Keşfet',
    AppTab.review => 'Tekrar',
    _ => null,
  };
  String text(AppTab t) => switch (t) {
    AppTab.learn => 'Sıradaki derse dokun ve başla. Günde birkaç dakika yeter.',
    AppTab.practice => 'Hatalarını ve tekrar kartlarını burada çalışırsın.',
    AppTab.league => 'Arkadaşını ekle, birlikte seri yapın, ligde yarışın.',
    AppTab.profile => 'Hesabın, fotoğrafın ve ayarların burada.',
    AppTab.discover => 'Yeni kelimeleri buradan öğren.',
    AppTab.review => 'Zamanı gelen kartları burada tekrar et.',
    _ => '',
  };
  return [
    for (final (i, t) in tabs.indexed)
      if (title(t) case final s?) (tab: i, title: s, text: text(t)),
  ].take(4).toList();
}

/// The short first-run tour: the screen dims, one bottom tab at a time is
/// lit up with a one-line bubble. A tap anywhere moves on; "Geç" ends it.
abstract final class FirstTour {
  /// Off in widget tests unless a test turns it on.
  static bool enabled = kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required GlobalKey barKey,
    required List<AppTab> tabs,
    required VoidCallback onDone,
  }) {
    if (_entry != null) return;
    final steps = tourSteps(tabs);
    if (steps.isEmpty) return onDone();
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => TourOverlay(
        barKey: barKey,
        tabCount: tabs.length,
        steps: steps,
        onDone: () {
          _entry?.remove();
          _entry = null;
          onDone();
        },
      ),
    );
    overlay.insert(_entry!);
  }
}

class TourOverlay extends StatefulWidget {
  const TourOverlay({
    super.key,
    required this.barKey,
    required this.tabCount,
    required this.steps,
    required this.onDone,
  });

  final GlobalKey barKey;
  final int tabCount;
  final List<TourStep> steps;
  final VoidCallback onDone;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int _i = 0;

  void _next() {
    if (_i + 1 >= widget.steps.length) return widget.onDone();
    setState(() => _i++);
  }

  /// The lit tab: NavigationBar gives every destination the same width.
  Rect? _target() {
    final box = widget.barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    final w = box.size.width / widget.tabCount;
    final tab = widget.steps[_i].tab;
    return Rect.fromLTWH(origin.dx + w * tab, origin.dy, w, box.size.height).deflate(4);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final target = _target();
    final size = MediaQuery.sizeOf(context);
    final last = _i + 1 == widget.steps.length;
    final bubbleBottom = target == null ? 120.0 : size.height - target.top + 14;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('tour-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: CustomPaint(painter: _ScrimPainter(target)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bubbleBottom,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey('tour-step-$_i'),
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                decoration: BoxDecoration(
                  color: Brand.card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(blurRadius: 18, color: Color(0x33000000))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(step.text, style: TextStyle(fontSize: 15, color: Brand.muted)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (var d = 0; d < widget.steps.length; d++)
                          Container(
                            width: d == _i ? 18 : 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: d == _i ? Brand.primary : Brand.line,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        const Spacer(),
                        if (!last)
                          TextButton(
                            key: const ValueKey('tour-skip'),
                            onPressed: widget.onDone,
                            child: const Text('Geç'),
                          ),
                        TextButton(
                          key: const ValueKey('tour-next'),
                          onPressed: _next,
                          child: Text(last ? 'Başla' : 'İleri'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? scrim
        : Path.combine(
            PathOperation.difference,
            scrim,
            Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(16))),
          );
    canvas.drawPath(path, Paint()..color = const Color(0xB3000000));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(16)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Brand.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
