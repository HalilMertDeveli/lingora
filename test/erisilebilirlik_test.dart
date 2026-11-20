// Pre-release QA (Google Core App Quality): the smallest phone (360x640 dp,
// 720x1280 at 320 dpi) with the system font at its maximum, TalkBack labels,
// touch targets, contrast and right/wrong shown by more than colour.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/exercises/choice_exercise.dart';
import 'package:lingora/exercises/common.dart';
import 'package:lingora/exercises/hands_free.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/conversation_screen.dart';
import 'package:lingora/screens/help_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/screens/profile_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/session.dart';
import 'package:lingora/voice/talk_screen.dart';
import 'package:lingora/voice/talk_service.dart';
import 'package:lingora/voice/voice_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dogal_konusma_test.dart' show FakeListener, FakeOut;
import 'premium_test.dart' show FakeBilling;
import 'ses_kocu_test.dart' show FakeChat, FakeReport;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final _course = Course.fromJson(
  jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
);
final _now = DateTime(2026, 11, 11, 9);

/// 720x1280 at 320 dpi: a 360x640 dp phone, the smallest Google's Core App
/// Quality asks for.
const _small = Size(360, 640);

/// Android 14+ "font size" at its maximum (200 %). The scale is not linear:
/// body text doubles, big headings grow less (FontScaleConverterFactory's
/// table for 2.0, which Flutter follows on Android).
class _AndroidMaxFont extends TextScaler {
  const _AndroidMaxFont();
  static const _sp = [8.0, 10.0, 12.0, 14.0, 18.0, 20.0, 24.0, 30.0, 100.0];
  static const _dp = [16.0, 20.0, 24.0, 26.0, 30.0, 34.0, 36.0, 38.0, 100.0];

  @override
  double scale(double fontSize) {
    if (fontSize <= _sp.first) return fontSize * 2;
    for (var i = 1; i < _sp.length; i++) {
      if (fontSize <= _sp[i]) {
        final t = (fontSize - _sp[i - 1]) / (_sp[i] - _sp[i - 1]);
        return _dp[i - 1] + t * (_dp[i] - _dp[i - 1]);
      }
    }
    return fontSize;
  }

  @override
  double get textScaleFactor => 2;

  @override
  bool operator ==(Object other) => other is _AndroidMaxFont;

  @override
  int get hashCode => 2;
}

/// Real glyph widths: the test font draws every letter as a wide square
/// and would wrap (and overflow) far more than the phone does.
Future<void> _loadFonts() async {
  final files = [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Inter-$w.ttf',
  ];
  for (final family in ['Inter', 'LingoraSans', 'Roboto']) {
    final loader = FontLoader(family);
    for (final path in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
}

Future<void> _setUpView(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_small);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Widget _maxFont(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: const _AndroidMaxFont()),
    child: child,
  ),
);

/// The whole app from a fresh install.
Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final p = await SharedPreferences.getInstance();
  await _setUpView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        billingServiceProvider.overrideWithValue(FakeBilling()),
        courseProvider.overrideWith((ref) async => _course),
        courseOutlineProvider.overrideWith((ref) async => _course),
        prefsProvider.overrideWithValue(p),
        clockProvider.overrideWithValue(() => _now),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
      ],
      child: _maxFont(const LingoraApp()),
    ),
  );
  await tester.pumpAndSettle();
}

/// One screen alone.
Future<void> _pumpScreen(WidgetTester tester, Widget home, {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues({'progress_v1': '{"onboarded": true}'});
  final p = await SharedPreferences.getInstance();
  await _setUpView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(p),
        clockProvider.overrideWithValue(() => _now),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
        billingServiceProvider.overrideWithValue(FakeBilling()),
        conversationServiceProvider.overrideWithValue(FakeChat()),
        conversationReportServiceProvider.overrideWithValue(FakeReport()),
        talkServiceProvider.overrideWithValue(DemoTalkService(FakeChat())),
        talkIoProvider.overrideWithValue(
          ({required bool call, required bool bargeIn}) => TalkIo(listener: FakeListener(), out: FakeOut()),
        ),
        ...overrides,
      ],
      child: _maxFont(MaterialApp(theme: buildTheme(), home: home)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Nothing overflowed, and the screen passes Flutter's Android tap-target,
/// labelled-tap-target and text-contrast checks.
Future<void> _expectAccessible(WidgetTester tester, String where) async {
  expect(tester.takeException(), isNull, reason: '$where: overflow or error');
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: where);
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: where);
  await expectLater(tester, meetsGuideline(textContrastGuideline), reason: where);
}

/// [_expectAccessible] down the whole screen: lazy lists build (and can
/// overflow) only what scrolls into view.
Future<void> _expectAccessibleScrolled(WidgetTester tester, String where) async {
  await _expectAccessible(tester, where);
  final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  if (lists.evaluate().isEmpty) return;
  final position = tester.state<ScrollableState>(lists.first).position;
  for (var i = 0; i < 20 && position.pixels < position.maxScrollExtent; i++) {
    position.jumpTo((position.pixels + 300).clamp(0, position.maxScrollExtent));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _expectAccessible(tester, '$where, scrolled to ${position.pixels.round()}');
  }
  position.jumpTo(0);
  await tester.pump();
}

/// Every line of the texts under [scope] ends between words: at the largest
/// font narrow cards broke "teşekkür / ler" and "yapacağı / m?" (QA).
void _expectWholeWords(WidgetTester tester, Finder scope, String where) {
  final paragraphs = find.descendant(of: scope, matching: find.byType(RichText));
  for (final e in paragraphs.evaluate()) {
    final rp = e.renderObject! as RenderParagraph;
    final text = rp.text.toPlainText();
    final painter = TextPainter(
      text: rp.text,
      textDirection: TextDirection.ltr,
      textScaler: rp.textScaler,
      maxLines: rp.maxLines,
    )..layout(maxWidth: rp.constraints.maxWidth);
    addTearDown(painter.dispose);
    var offset = 0;
    while (offset < text.length) {
      final line = painter.getLineBoundary(TextPosition(offset: offset));
      if (line.end >= text.length || line.end <= offset) break;
      final before = text[line.end - 1];
      final after = text[line.end];
      expect(
        before.trim().isEmpty || after.trim().isEmpty || '-/·'.contains(before),
        isTrue,
        reason: '$where: "$text" breaks inside a word at $offset..${line.end}',
      );
      offset = line.end;
    }
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('largest font, 360 dp: onboarding, the first lesson, leaving it and the tabs', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpApp(tester);
    await _expectAccessible(tester, 'welcome');
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    await _expectAccessible(tester, 'goal');
    // The step bar says where you are, not a bare "67".
    expect(find.bySemanticsLabel('Adım 2 / 3'), findsOneWidget);
    await tester.tap(find.text('Genel İngilizce'));
    await tester.pump();
    await tester.tap(find.text('İlk derse başla'));
    await tester.pumpAndSettle();
    // Every exercise of the first lesson and its feedback (the first card
    // picked: right and wrong answers both come up).
    for (var step = 0; step < 6; step++) {
      await _expectAccessible(tester, 'lesson step $step');
      _expectWholeWords(tester, find.byType(TapCard), 'lesson step $step');
      final cards = find.byType(TapCard);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      final check = find.text('Kontrol et');
      if (check.evaluate().isEmpty) break;
      await tester.tap(check, warnIfMissed: false);
      await tester.pumpAndSettle();
      await _expectAccessible(tester, 'lesson feedback $step');
      final next = find.text('Devam');
      if (next.evaluate().isEmpty) break;
      await tester.tap(next.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('session-close')));
    await tester.pumpAndSettle();
    await _expectAccessible(tester, 'quit sheet');
    // QA: the sheet was cut at 9/16 of the screen and hid both buttons.
    await tester.ensureVisible(find.text('Çık'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Çık')).bottom, lessThanOrEqualTo(_small.height));
    await tester.tap(find.text('Çık'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-start-card')), findsOneWidget);
    _expectWholeWords(tester, find.byKey(const Key('today-start-card')), 'Bugün');
    await _expectAccessibleScrolled(tester, 'Öğren with Bugün');
    for (final tab in ['Profil', 'Pratik', 'Görevler', 'Lig']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      await _expectAccessibleScrolled(tester, tab);
    }
    semantics.dispose();
  });

  for (final (name, screen) in <(String, Widget Function())>[
    ('paywall', () => const PaywallScreen()),
    ('Yardım / SSS', () => const HelpScreen()),
    ('profile', () => const ProfileScreen()),
    ('Konuş entry', () => const ConversationHomeScreen()),
    ('voice talk', () => TalkScreen(scenario: characterScenario(characterById('emma')!))),
    (
      'voice call',
      () => TalkScreen(scenario: characterScenario(characterById('emma')!, call: true), call: true),
    ),
  ]) {
    testWidgets('largest font, 360 dp: $name', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpScreen(tester, Scaffold(body: screen()));
      await _expectAccessibleScrolled(tester, name);
      semantics.dispose();
    });
  }

  const longPrompt =
      'Read the message from your new colleague and write two or three sentences that answer her '
      'question about the meeting politely and clearly.';
  for (final (name, ex) in <(String, Exercise)>[
    (
      'listen, typed',
      const Exercise(
        type: ExerciseType.listen,
        text: 'In the future I would like to live by the sea with my family.',
        answers: ['In the future I would like to live by the sea with my family.'],
      ),
    ),
    (
      'write, long task',
      const Exercise(
        type: ExerciseType.write,
        prompt: longPrompt,
        model: 'Sure, the meeting is at ten.',
        minWords: 10,
        maxWords: 40,
      ),
    ),
    (
      'speak, "Yazarak cevapla"',
      const Exercise(type: ExerciseType.speak, text: 'Excuse me, how do I get to the airport from here?'),
    ),
  ]) {
    testWidgets('largest font, 360 dp, keyboard open: $name keeps the answer box in view', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpScreen(
        tester,
        LessonScreen(nodeId: 'qa', title: 'QA', items: [(key: 'qa#0', ex: ex)], color: Brand.primary),
      );
      await tester.pumpAndSettle();
      final typing = find.text('Yazarak cevapla');
      if (typing.evaluate().isNotEmpty) {
        await tester.ensureVisible(typing);
        await tester.pumpAndSettle();
        await tester.tap(typing);
        await tester.pumpAndSettle();
      }
      final field = find.byType(TextField);
      await tester.showKeyboard(field);
      await tester.enterText(field, 'I would like to');
      const keyboard = 280.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      // The box starts above the keyboard (the caret line shows) and
      // "Kontrol et" sits on top of the keyboard.
      expect(tester.getRect(field).top, lessThan(_small.height - keyboard - 40));
      expect(tester.getRect(find.text('Kontrol et')).bottom, lessThanOrEqualTo(_small.height - keyboard));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });
  }

  group('right and wrong are not told by colour alone', () {
    testWidgets('choice options: the picked card is "selected", the checked ones carry a named ✓ / ✕', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      Widget choice({required bool locked}) => ProviderScope(
        overrides: [speechProvider.overrideWithValue(FakeSpeech())],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ChoiceExercise(
              ex: const Exercise(
                type: ExerciseType.choice,
                question: 'Hangisi doğru?',
                options: ['I am agree.', 'I agree.'],
                answerIndex: 1,
              ),
              locked: locked,
              onReady: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(choice(locked: false));
      await tester.tap(find.text('I am agree.'));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(const Key('choice-option-0'))).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      await tester.pumpWidget(choice(locked: true));
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Yanlış')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Doğru')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('feedback panel: an icon and its word, read out as it appears', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final ok in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: AnswerFeedbackPanel(
                key: ValueKey(ok),
                correct: ok,
                answer: 'hello',
                seed: 1,
                onContinue: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.byIcon(ok ? Icons.check_circle_rounded : Icons.lightbulb_circle_rounded), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(ok ? 'Doğru' : 'Yanlış')), findsWidgets);
        final live = find.descendant(
          of: find.byKey(Key(ok ? 'feedback-correct' : 'feedback-wrong')),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
        );
        expect(live, findsOneWidget);
      }
      semantics.dispose();
    });

    testWidgets('feedback panel at the largest font: a long explanation scrolls, "Devam" stays on screen', (
      tester,
    ) async {
      await _setUpView(tester);
      await tester.pumpWidget(
        _maxFont(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  // The lesson header and a sliver of the exercise above.
                  const SizedBox(height: 150),
                  const Expanded(child: SizedBox()),
                  AnswerFeedbackPanel(
                    correct: false,
                    answer: 'B) I agree with you.',
                    seed: 1,
                    detail: Text(
                      'Türkçede "katılıyorum" derken sondaki "-um" ekini İngilizcede "am" ile ' * 4,
                    ),
                    onContinue: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const Key('feedback-continue'))).bottom,
        lessThanOrEqualTo(_small.height),
      );
    });

    testWidgets('speaker buttons have a name and a 48 dp target, the small ones too', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [speechProvider.overrideWithValue(FakeSpeech())],
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SpeakerButton(text: 'hello'),
                  SpeakerButton(text: 'hello', slow: true, size: 36),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Dinle'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListeningIndicator())));
      expect(find.bySemanticsLabel('Dinliyorum'), findsOneWidget);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [speechProvider.overrideWithValue(FakeSpeech())],
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SpeakerButton(text: 'hello'),
                  SpeakerButton(text: 'hello', slow: true, size: 36),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Yavaş dinle'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });
  });

  testWidgets('whole words: a long word shrinks the scale just enough, never below normal', (tester) async {
    late TextScaler fit, fits, tiny;
    const style = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Builder(
          builder: (context) {
            fit = wholeWordScaler(context, 'teşekkürler', style, 150);
            fits = wholeWordScaler(context, 'hi', style, 150);
            tiny = wholeWordScaler(context, 'teşekkürler', style, 10);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(fits.scale(16), 32);
    expect(fit.scale(16), lessThan(32));
    expect(fit.scale(16), greaterThan(16));
    expect(tiny.scale(16), 16);
  });
}
