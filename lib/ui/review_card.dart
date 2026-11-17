import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../data/app_settings.dart';
import '../data/review_grade.dart';
import '../exercises/common.dart' show SpeakerButton;
import '../services/speech.dart';
import '../study/review_card_data.dart';
import '../theme.dart';
import 'mascot.dart';
import 'motion.dart';

export '../study/review_card_data.dart' show ReviewCardData;

/// How long the card takes to turn over.
const flipDuration = Duration(milliseconds: 400);

/// A soft spring: overshoots a little past the turn and settles back.
const flipCurve = Cubic(0.34, 1.32, 0.64, 1);

/// Share of the card width a drag must pass to grade the card.
const swipeThreshold = 0.3;

/// Colour of each grade button.
Color gradeColor(ReviewGrade g) => switch (g) {
  ReviewGrade.again => Brand.error,
  ReviewGrade.hard => Brand.streak,
  ReviewGrade.good => Brand.success,
  ReviewGrade.easy => Brand.info,
};

/// Icon of each grade button.
IconData gradeIcon(ReviewGrade g) => switch (g) {
  ReviewGrade.again => Icons.replay_rounded,
  ReviewGrade.hard => Icons.hourglass_bottom_rounded,
  ReviewGrade.good => Icons.check_rounded,
  ReviewGrade.easy => Icons.bolt_rounded,
};

/// One review card on top of its deck: tap to turn it over (3D, around the
/// vertical axis), then grade it with "Bilmiyordum / Zor / Bildim / Kolay"
/// or swipe it: right is "Bildim", left "Bilmiyordum". The card tilts and
/// tints while it is dragged. With reduced motion the faces cross-fade and a
/// swipe grades at once.
///
/// Give it a new key for each card so a new card starts face up.
class ReviewDeck extends ConsumerStatefulWidget {
  const ReviewDeck({
    super.key,
    required this.card,
    required this.behind,
    required this.onGrade,
    required this.intervalOf,
    required this.color,
    this.badge,
  });

  final ReviewCardData card;

  /// Cards left under this one (up to two are drawn).
  final int behind;
  final void Function(ReviewGrade grade) onGrade;

  /// "sonraki: 3 gün" under each grade button.
  final String Function(ReviewGrade grade) intervalOf;
  final Color color;

  /// "YENİ" / "TEKRAR" on the front.
  final ({String label, Color color})? badge;

  @override
  ConsumerState<ReviewDeck> createState() => _ReviewDeckState();
}

class _ReviewDeckState extends ConsumerState<ReviewDeck> with TickerProviderStateMixin {
  late final _flip = AnimationController(vsync: this, duration: flipDuration);
  late final _turn = CurvedAnimation(parent: _flip, curve: flipCurve, reverseCurve: flipCurve.flipped);
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Animation<double>? _moveTween;
  bool _flipped = false;
  double _dx = 0;
  bool _done = false;
  double _width = 320;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _move.addListener(() {
      if (_moveTween != null) setState(() => _dx = _moveTween!.value);
    });
    // The word is read out when the card opens, if sounds are on.
    if (ref.read(appSettingsProvider).sound) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(speechProvider).say(widget.card.en);
      });
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _flip.dispose();
    _move.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_done) return;
    Haptics.tap();
    setState(() => _flipped = !_flipped);
    if (_reduced) {
      _flip.value = _flipped ? 1 : 0;
    } else {
      _flipped ? _flip.forward() : _flip.reverse();
    }
  }

  void _grade(ReviewGrade g) {
    if (_done) return;
    _done = true;
    g.known ? Haptics.success() : Haptics.tap();
    widget.onGrade(g);
  }

  void _animateTo(double target, {VoidCallback? then}) {
    _moveTween = Tween(
      begin: _dx,
      end: target,
    ).animate(CurvedAnimation(parent: _move, curve: Curves.easeOut));
    _move.forward(from: 0).whenComplete(() {
      if (mounted) then?.call();
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_done) return;
    _move.stop();
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_done) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final far = _dx.abs() > _width * swipeThreshold;
    final flung = v.abs() > 900 && v.sign == _dx.sign && _dx != 0;
    if (!far && !flung) {
      _reduced ? setState(() => _dx = 0) : _animateTo(0);
      return;
    }
    final grade = _dx > 0 ? ReviewGrade.good : ReviewGrade.again;
    if (_reduced) {
      _grade(grade);
      return;
    }
    _animateTo(_dx.sign * _width * 1.6, then: () => _grade(grade));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              _width = box.maxWidth;
              final h = min(box.maxHeight - 28, 600.0).clamp(220.0, 600.0);
              final pull = (_dx.abs() / (_width * swipeThreshold)).clamp(0.0, 1.0);
              return Stack(
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                children: [
                  for (var i = min(widget.behind, 2); i >= 1; i--)
                    _Ghost(depth: i - pull, width: _width, height: h, color: widget.color),
                  Transform.translate(
                    offset: Offset(_dx, _dx.abs() * 0.06),
                    child: Transform.rotate(
                      angle: _dx / _width * 0.32,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(width: _width, height: h, child: _swipeable(pull)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: _reduced ? Duration.zero : const Duration(milliseconds: 220),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: _flipped ? _grades() : _frontActions(),
        ),
      ],
    );
  }

  Widget _swipeable(double pull) {
    final right = _dx > 0;
    final tint = right ? Brand.success : Brand.error;
    return Semantics(
      key: const Key('review-card'),
      button: true,
      label: _flipped ? widget.card.backLabel : widget.card.frontLabel,
      hint: _flipped ? 'Ön yüze dönmek için dokun' : 'Anlamını görmek için dokun',
      onTap: _toggle,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _toggle,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _turning(),
            if (_dx != 0)
              IgnorePointer(
                child: Opacity(
                  opacity: pull,
                  child: Container(
                    key: Key(right ? 'swipe-known' : 'swipe-unknown'),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(_radius),
                      border: Border.all(color: tint, width: 3),
                    ),
                    alignment: const Alignment(0, -0.58),
                    child: Transform.rotate(
                      angle: right ? -0.2 : 0.2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Brand.card,
                          border: Border.all(color: tint, width: 3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          right ? 'BİLDİM' : 'BİLMİYORDUM',
                          style: TextStyle(
                            color: tint,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The card itself: a 3D turn, or a cross-fade with reduced motion.
  Widget _turning() {
    if (_reduced) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _flipped
            ? KeyedSubtree(key: const ValueKey('back'), child: _back())
            : KeyedSubtree(key: const ValueKey('front'), child: _front()),
      );
    }
    return AnimatedBuilder(
      animation: _turn,
      builder: (_, _) {
        final angle = _turn.value * pi;
        final back = angle > pi / 2;
        // Lift the card a little at mid-turn for depth.
        final lift = 1 + 0.06 * sin(_flip.value * pi);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle)
            ..scaleByDouble(lift, lift, 1, 1),
          child: back
              ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(pi), child: _back())
              : _front(),
        );
      },
    );
  }

  double get _radius => Brand.isKid ? 32 : 26;

  BoxDecoration _face({required bool back}) {
    final c = widget.color;
    final p = context.palette;
    final border = back ? Brand.tone(c) : Brand.line;
    return BoxDecoration(
      color: back ? Color.alphaBlend(c.withValues(alpha: p.isDark ? 0.16 : 0.08), Brand.card) : Brand.card,
      gradient: back
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Brand.card,
                Color.alphaBlend(c.withValues(alpha: p.isDark ? 0.10 : 0.05), Brand.card),
              ],
            ),
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(color: border, width: Brand.isKid ? 3 : 1.5),
      boxShadow: Brand.isKid
          ? [BoxShadow(color: edgeOf(back ? c : Brand.line), offset: const Offset(0, 6))]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.4 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Brand.tone(color),
        fontWeight: FontWeight.w800,
        fontSize: 12,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _front() {
    final c = widget.card;
    return Container(
      key: const Key('card-front'),
      decoration: _face(back: false),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.badge case final b?) ...[_tag(b.label, b.color), const SizedBox(width: 8)],
              if (c.tag case final t?) Flexible(child: _tag(trUpper(t), Brand.muted)),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    c.en,
                    key: const Key('srs-front'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: Brand.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (c.sub case final s?) ...[
                  const SizedBox(height: 6),
                  Text(
                    s,
                    style: TextStyle(color: Brand.muted, fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 18),
                SpeakerButton(text: c.en, size: 52),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_rounded, size: 18, color: Brand.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Anlamını düşün, sonra kartı çevir',
                  key: const Key('srs-hint'),
                  style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600),
                ),
              ),
              // Pofuduk peeks in Çocuk modu; adults get nothing here.
              if (Brand.isKid) ...[
                const SizedBox(width: 8),
                const Mascot(mood: Mood.think, size: 44, decorative: true),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _back() {
    final c = widget.card;
    final tone = Brand.tone(widget.color);
    return Container(
      key: const Key('card-back'),
      decoration: _face(back: true),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.en,
                  style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              SpeakerButton(text: c.en, size: 38),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    c.tr,
                    key: const Key('srs-back'),
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: tone, height: 1.15),
                  ),
                  if (c.exampleEn case final ex?) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: tone, width: 3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            highlightWord(
                              ex,
                              c.highlight ?? c.en,
                              TextStyle(fontSize: 17, height: 1.35, color: Brand.ink),
                              TextStyle(fontWeight: FontWeight.w900, color: tone),
                            ),
                            key: const Key('card-example'),
                          ),
                          if (c.exampleTr case final tr?) ...[
                            const SizedBox(height: 6),
                            Text(
                              tr,
                              style: TextStyle(color: Brand.muted, fontStyle: FontStyle.italic, height: 1.3),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (c.note case final note?) ...[
                    const SizedBox(height: 16),
                    Container(
                      key: const Key('card-note'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Brand.accentBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            c.noteLabel == 'Sık hata' ? Icons.warning_amber_rounded : Icons.lightbulb_rounded,
                            size: 20,
                            color: Brand.tone(Brand.accent),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${c.noteLabel ?? 'Not'}: ',
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  TextSpan(text: note),
                                ],
                              ),
                              style: TextStyle(color: Brand.ink, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _frontActions() => Column(
    key: const ValueKey('front-actions'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '← Bilmiyordum   ·   Bildim →',
        textAlign: TextAlign.center,
        style: TextStyle(color: Brand.muted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      PressableButton(key: const Key('srs-show'), label: 'KARTI ÇEVİR', onPressed: _toggle),
    ],
  );

  Widget _grades() => Column(
    key: const ValueKey('grades'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Ne kadar hatırladın?',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800, color: Brand.ink),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final g in ReviewGrade.values) ...[
            if (g != ReviewGrade.values.first) const SizedBox(width: 8),
            Expanded(
              child: _GradeButton(
                key: Key('grade-${g.name}'),
                grade: g,
                interval: widget.intervalOf(g),
                onTap: () => _grade(g),
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

/// [text] with every case-insensitive occurrence of [word] in [strong].
TextSpan highlightWord(String text, String word, TextStyle base, TextStyle strong) {
  final w = word.trim();
  if (w.isEmpty) return TextSpan(text: text, style: base);
  final re = RegExp(RegExp.escape(w), caseSensitive: false);
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(TextSpan(text: m[0], style: strong));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: base, children: spans);
}

/// A card waiting under the top one; it rises as the top card is dragged off.
class _Ghost extends StatelessWidget {
  const _Ghost({required this.depth, required this.width, required this.height, required this.color});
  final double depth;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Transform.translate(
      offset: Offset(0, 14 * depth),
      child: Transform.scale(
        scale: 1 - 0.05 * depth,
        alignment: Alignment.bottomCenter,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withValues(alpha: 0.04 * depth), Brand.card),
            borderRadius: BorderRadius.circular(Brand.isKid ? 32 : 26),
            border: Border.all(color: Brand.line, width: Brand.isKid ? 3 : 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.3 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({super.key, required this.grade, required this.interval, required this.onTap});
  final ReviewGrade grade;
  final String interval;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = gradeColor(grade);
    // "Bildim" is the usual answer: filled, the others tinted.
    final main = grade == ReviewGrade.good;
    final fg = main ? onColor(Brand.tone(c)) : Brand.tone(c);
    return Semantics(
      button: true,
      label: '${grade.label}, sonraki tekrar $interval',
      excludeSemantics: true,
      child: Material(
        color: main ? Brand.tone(c) : c.withValues(alpha: context.palette.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Brand.tone(c).withValues(alpha: 0.5), width: 1.5),
            ),
            child: Column(
              children: [
                Icon(gradeIcon(grade), size: 20, color: fg),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    grade.label,
                    style: TextStyle(fontWeight: FontWeight.w900, color: fg, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  interval,
                  style: TextStyle(color: main ? fg.withValues(alpha: 0.85) : Brand.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// End of a review session: how many cards, how many known, gold earned.
class ReviewSummary extends StatelessWidget {
  const ReviewSummary({
    super.key,
    required this.total,
    required this.known,
    required this.gold,
    required this.color,
    this.message,
  });
  final int total;
  final int known;
  final int gold;
  final Color color;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final great = total > 0 && known * 10 >= total * 8;
    return Column(
      key: const Key('review-summary'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: PopIn(child: Mascot(mood: great ? Mood.cheer : Mood.happy, size: 120, react: true)),
        ),
        const SizedBox(height: 12),
        Text(
          great ? '${kidEmoji('🎉')}Harika tekrar!' : 'Tekrar tamam',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Brand.ink),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _Stat(key: const Key('sum-total'), value: '$total', label: 'kelime', color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                key: const Key('sum-known'),
                value: '$known',
                label: 'bildin',
                color: Brand.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                key: const Key('sum-gold'),
                value: '+$gold',
                label: 'altın',
                color: Brand.xp,
                icon: Icons.monetization_on_rounded,
              ),
            ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: 14),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, height: 1.35),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label, required this.color, this.icon});
  final String value;
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: context.palette.isDark ? 0.2 : 0.1),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: Brand.tone(color)), const SizedBox(width: 4)],
            CountUp(
              value: int.tryParse(value.replaceAll('+', '')) ?? 0,
              prefix: value.startsWith('+') ? '+' : '',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Brand.tone(color)),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
