/// The AI the engine talks to, injected by each app.
///
/// The engine never chooses or calls a model itself. Udyoga adapts its
/// `Ai`; Vidya adapts brahma_core's `HelpAsker` and its local Ollama
/// setting. Both go through this interface, so scoring works the same in
/// both apps and on local and cloud models (honesty rule 12).
library;

import 'question.dart';

/// One criterion's score for one answer.
///
/// A score is only kept when [quote] is found in the transcript; the engine
/// checks this itself (honesty rule 2). A brain that cannot quote returns
/// `score: null`, shown as N/O (not observed).
class QuotedScore {
  const QuotedScore({required this.criterion, required this.score, required this.quote, this.reason = ''});

  /// The criterion as it was fixed before the answer.
  final String criterion;

  /// On the panel's own scale, or null for N/O.
  final int? score;

  /// The exact words from the transcript that earned the score.
  final String quote;

  /// Why the quote meets (or misses) the criterion's anchor.
  final String reason;
}

/// What an app must provide for the engine to run an interview round.
///
/// J0 stub: the method set follows the research plan (plan a round, ask a
/// follow-up, score with quotes). Signatures may still change in J2, when
/// the engine moves out of Udyoga.
abstract interface class InterviewBrain {
  /// Plans [count] questions for a round. [criteria] come from the advert
  /// or person specification; stories and competencies are passed in as
  /// data, never read from an app database.
  Future<List<EngineQuestion>> planRound({
    required String role,
    required List<String> criteria,
    List<String> stories = const [],
    int count = 5,
  });

  /// One probing follow-up to [answer], or null when none is needed.
  Future<String?> followUp({required EngineQuestion question, required String answer});

  /// Scores [transcript] against the question's fixed criteria. Each
  /// result must quote the transcript; the engine drops any quote it
  /// cannot find.
  Future<List<QuotedScore>> score({required EngineQuestion question, required String transcript});
}
