/// One interview question, as the engine sees it.
///
/// This replaces Udyoga's `PracticeQuestion` at the package seam: plain
/// data with no database row and no app schema behind it. Each app maps its
/// own question type to and from this one.
library;

/// How hard a question is meant to be.
enum Difficulty { standard, hard, toughest }

/// A question the interviewer asks, with what the panel is testing and
/// what a top answer includes. The criteria in [lookFor] are fixed before
/// the candidate answers and are shown with the question (honesty rule 1).
class EngineQuestion {
  const EngineQuestion({
    required this.question,
    this.category = '',
    this.why = '',
    this.lookFor = const [],
    this.difficulty = Difficulty.standard,
  });

  /// Reads the shape Udyoga's AI already returns: `question`, `category`,
  /// `why`, `lookFor` and `difficulty`. Unknown or missing fields fall back
  /// to empty values, never to invented ones.
  factory EngineQuestion.fromJson(Map<String, Object?> j) => EngineQuestion(
    question: j['question'] is String ? j['question'] as String : '',
    category: j['category'] is String ? j['category'] as String : '',
    why: j['why'] is String ? j['why'] as String : '',
    lookFor: [
      for (final s in (j['lookFor'] is List ? j['lookFor'] as List : const []))
        if (s is String) s,
    ],
    difficulty: Difficulty.values.firstWhere(
      (d) => d.name == j['difficulty'],
      orElse: () => Difficulty.standard,
    ),
  );

  /// The question as the candidate hears or reads it.
  final String question;

  /// For example Behavioural, Values, Technical, Situational or Motivation.
  final String category;

  /// What the panel is testing with this question.
  final String why;

  /// What a top answer includes: the fixed scoring criteria.
  final List<String> lookFor;

  final Difficulty difficulty;

  Map<String, Object?> toJson() => {
    'question': question,
    'category': category,
    'why': why,
    'lookFor': lookFor,
    'difficulty': difficulty.name,
  };
}
