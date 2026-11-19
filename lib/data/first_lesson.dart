import '../models/course.dart';
import 'practice.dart';

/// The first lesson, right after the goal is chosen (~2–3 minutes): a few
/// greetings, then the moment that makes Dilmaç different: a mistake Turkish
/// speakers make ("I am agree") and why it is wrong, in Turkish.
///
/// It lives in code, not in the course files: it is part of the first run,
/// not of a unit, and finishing it does not move the path.
const firstLessonId = 'first_lesson';

const firstLessonTitle = 'İlk ders';

/// The "I am agree" explanation (the same reasoning as the hata dedektörü's
/// be_agree rule in lib/core/tr_errors.dart).
const firstLessonAgreeWhy =
    'Türkçede "katılıyorum" derken sondaki "-um" ekini İngilizcede "am" ile karşılamak isteriz. '
    'Ama "agree" zaten bir fiil: "katılmak". O yüzden "I agree" yeterli, "I am agree" yanlış. '
    'Dilmaç bu tür Türkçe düşünmekten gelen hataları yakalar ve böyle açıklar.';

final List<Exercise> _exercises = [
  const Exercise(
    type: ExerciseType.select,
    prompt: 'merhaba',
    answer: 'hello',
    choices: [
      Choice('hello', '👋'),
      Choice('thank you', '🙏'),
      Choice('good night', '🌙'),
      Choice('coffee', '☕'),
    ],
  ),
  const Exercise(
    type: ExerciseType.fillBlank,
    text: 'Good ___!',
    translation: 'Günaydın!',
    answer: 'morning',
    wordChoices: ['morning', 'hello', 'thanks'],
  ),
  const Exercise(
    type: ExerciseType.select,
    prompt: 'teşekkürler',
    answer: 'thank you',
    choices: [
      Choice('good morning', '🌅'),
      Choice('thank you', '🙏'),
      Choice('hello', '👋'),
      Choice('goodbye', '🚶'),
    ],
  ),
  // The Turkish-speaker mistake, with its explanation shown after answering.
  const Exercise(
    type: ExerciseType.choice,
    question: '"Sana katılıyorum." İngilizcesi hangisi?',
    options: ['I am agree with you.', 'I agree with you.'],
    answerIndex: 1,
    explanation: firstLessonAgreeWhy,
  ),
  // Now the learner builds it; "am" is in the word bank on purpose, so
  // "I am agree" gets the "Neden yanlış?" explanation.
  const Exercise(
    type: ExerciseType.translate,
    text: 'Sana katılıyorum.',
    lang: 'tr',
    answers: ['I agree with you', 'I agree'],
    tokens: ['I', 'am', 'agree', 'with', 'you', 'is'],
  ),
  const Exercise(
    type: ExerciseType.match,
    pairs: [
      ('merhaba', 'hello'),
      ('günaydın', 'good morning'),
      ('teşekkürler', 'thank you'),
      ('katılıyorum', 'I agree'),
    ],
  ),
];

/// The first lesson's questions ("first_lesson#0"…).
List<LessonItem> firstLessonItems() => [
  for (var i = 0; i < _exercises.length; i++) (key: itemKey(firstLessonId, i), ex: _exercises[i]),
];
