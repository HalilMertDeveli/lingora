import 'package:flutter/material.dart';

import '../theme.dart';
import 'mascot.dart';
import 'motion.dart';

/// Pieces shared by every answer-and-check session: course lessons, unit
/// tests, mistakes review and the vocabulary review (docs/arayuz-referans.md,
/// "Ders oturumu").

/// Answers in a row from which the progress bar and header celebrate.
const comboThreshold = 3;

/// Top of a session: close X, a thick progress bar and a trailing badge.
/// A run of [comboThreshold]+ correct answers lights the bar up and shows a
/// "N doğru üst üste" line under it.
class SessionHeader extends StatelessWidget {
  const SessionHeader({
    super.key,
    required this.progress,
    required this.color,
    required this.onClose,
    this.combo = 0,
    this.trailing,
    this.caption,
  });

  /// 0..1.
  final double progress;
  final Color color;
  final VoidCallback onClose;
  final int combo;
  final Widget? trailing;

  /// Shown under the bar when there is no combo (e.g. "ÜNİTE SINAVI").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final hot = combo >= comboThreshold;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('session-close'),
                tooltip: 'Kapat',
                icon: Icon(Icons.close, color: Brand.muted),
                onPressed: onClose,
              ),
              Expanded(
                child: SessionProgressBar(value: progress, color: color, combo: combo),
              ),
              if (trailing != null) ...[const SizedBox(width: 14), trailing!],
            ],
          ),
          SizedBox(
            height: 26,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: hot
                  ? PopIn(
                      key: ValueKey('combo-$combo'),
                      child: Text(
                        '${kidEmoji('🔥')}$combo DOĞRU ÜST ÜSTE',
                        key: const Key('combo-label'),
                        style: TextStyle(
                          color: Brand.streak,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    )
                  : (caption != null
                        ? Text(
                            caption!,
                            style: TextStyle(
                              color: Brand.muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          )
                        : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thick rounded session bar. The fill eases to its new length; while a
/// combo runs it turns to the streak colour and a light sweeps across it.
class SessionProgressBar extends StatefulWidget {
  const SessionProgressBar({super.key, required this.value, required this.color, this.combo = 0});
  final double value;
  final Color color;
  final int combo;

  /// How long the fill takes to reach a new value.
  static const fillDuration = Duration(milliseconds: 400);

  @override
  State<SessionProgressBar> createState() => _SessionProgressBarState();
}

class _SessionProgressBarState extends State<SessionProgressBar> with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(SessionProgressBar old) {
    super.didUpdateWidget(old);
    final hot = widget.combo >= comboThreshold;
    if (hot && widget.combo != old.combo && !MediaQuery.disableAnimationsOf(context)) {
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hot = widget.combo >= comboThreshold;
    // Warm (amber) from 3 in a row, burning (streak orange) from 5.
    final fill = widget.combo >= 5 ? p.streak : (hot ? p.accent : widget.color);
    const height = 16.0;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'İlerleme',
      value: '%${(widget.value.clamp(0.0, 1.0) * 100).round()}',
      child: TweenAnimationBuilder<double>(
        key: const Key('session-progress'),
        tween: Tween(end: widget.value.clamp(0.0, 1.0)),
        duration: reduced ? Duration.zero : SessionProgressBar.fillDuration,
        curve: Curves.easeOutBack,
        builder: (_, v, _) => Container(
          height: height,
          decoration: BoxDecoration(
            color: p.isDark ? p.surface : p.line,
            borderRadius: BorderRadius.circular(height),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            heightFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(height)),
              clipBehavior: Clip.antiAlias,
              child: v < 0.04
                  ? null
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // Glossy highlight along the top of the fill.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _sweep,
                          builder: (_, _) => !_sweep.isAnimating
                              ? const SizedBox.shrink()
                              : FractionallySizedBox(
                                  alignment: Alignment(-1.4 + 2.8 * _sweep.value, 0),
                                  widthFactor: 0.25,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0),
                                          Colors.white.withValues(alpha: 0.55),
                                          Colors.white.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom bar with the "Kontrol et" button, shown while answering.
class CheckBar extends StatelessWidget {
  const CheckBar({super.key, required this.onCheck, this.label = 'KONTROL ET', this.color});

  /// Null while there is nothing to check (button greyed out).
  final VoidCallback? onCheck;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('check-bar'),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: BoxDecoration(
      color: Brand.background,
      border: Border(top: BorderSide(color: Brand.line, width: 2)),
    ),
    child: PressableButton(label: label, color: color ?? Brand.success, onPressed: onCheck),
  );
}

/// Panel that slides up from the bottom after "Kontrol et": green for a
/// correct answer, red with the right answer for a wrong one, and a
/// "Devam" button. The mascot reacts at its side.
class AnswerFeedbackPanel extends StatefulWidget {
  const AnswerFeedbackPanel({
    super.key,
    required this.correct,
    required this.onContinue,
    this.title,
    this.answer,
    this.detail,
    this.secondary,
    this.continueKey,
  });

  final bool correct;
  final VoidCallback onContinue;

  /// Headline; "Doğru!" / "Doğru cevap:" by default.
  final String? title;

  /// The right answer (wrong answers) or the learned pair (correct ones).
  final String? answer;

  /// Extra content under the answer ("Neden yanlış?", a tip…).
  final Widget? detail;

  /// Small action left of "Devam" (e.g. "Kelimeye bak").
  final Widget? secondary;

  /// Key for the "Devam" button (tests and older call sites).
  final Key? continueKey;

  /// Slide-up time of the panel.
  static const slideDuration = Duration(milliseconds: 300);

  @override
  State<AnswerFeedbackPanel> createState() => _AnswerFeedbackPanelState();
}

class _AnswerFeedbackPanelState extends State<AnswerFeedbackPanel> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: AnswerFeedbackPanel.slideDuration);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.correct;
    final fg = ok ? Brand.success : Brand.error;
    final slide = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(slide),
      child: Container(
        key: Key(ok ? 'feedback-correct' : 'feedback-wrong'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: ok ? Brand.successBg : Brand.errorBg,
          border: Border(top: BorderSide(color: fg.withValues(alpha: 0.35), width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PopIn(
                  child: Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: fg, size: 32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title ?? (ok ? 'Doğru!' : 'Doğru cevap:'),
                        style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      if (widget.answer != null && widget.answer!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.answer!,
                            style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
                Mascot(mood: ok ? Mood.joy : Mood.sad, size: 64, react: true),
              ],
            ),
            if (widget.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(child: widget.detail),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.secondary != null) ...[widget.secondary!, const SizedBox(width: 8)],
                Expanded(
                  child: PressableButton(
                    key: widget.continueKey ?? const Key('feedback-continue'),
                    label: 'DEVAM',
                    color: fg,
                    onPressed: widget.onContinue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
