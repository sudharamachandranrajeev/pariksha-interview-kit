/// The checks that keep AI scoring honest, the same in every app (honesty
/// rules 6 and 8).
///
/// - Every round is scored twice, with the criteria in a different order
///   each time ([scoreTwice]), because judges lean on position. Where the
///   two runs give a criterion different levels, the lower one is shown
///   and marked "uncertain, check yourself" ([verifyRuns]). No confidence
///   percentage is ever shown.
/// - Pushback never changes a score. A dispute re-checks the quote against
///   the transcript and the criterion against the question, nothing else
///   ([recheckScore]); the words of the pushback are not read.
library;

import 'dart:math' as math;

import '../brain.dart';
import 'interview_scoring.dart';

/// The two orders the criteria are sent in: a shuffle, and the same
/// shuffle reversed, so no criterion is in the same place twice when there
/// are two or more (the middle one of an odd count excepted).
List<List<Criterion>> shuffledOrders(List<Criterion> criteria, {math.Random? random}) {
  final first = [...criteria]..shuffle(random ?? math.Random());
  return [first, first.reversed.toList()];
}

/// Scores [round]'s answered questions twice through [brain], with the
/// criteria in the two orders of [shuffledOrders]. Returns both raw runs;
/// check them with [verifyRuns]. Only the transcripts and the criteria go
/// to the AI. If the second run fails, its error is thrown: a round is not
/// shown as checked twice when it was not.
Future<List<List<AnswerScore>>> scoreTwice({
  required InterviewBrain brain,
  required String role,
  required Framework framework,
  required DebriefRound round,
  math.Random? random,
}) async {
  final answers = [
    for (final q in round.answered)
      (index: q.index, question: q.question.question, criteria: q.criteria, answer: q.heard),
  ];
  if (answers.isEmpty) return const [];
  final runs = <List<AnswerScore>>[];
  for (final order in shuffledOrders(round.criteria, random: random)) {
    runs.add(await brain.scoreRound(role: role, framework: framework, criteria: order, answers: answers));
  }
  return runs;
}

/// Checks each run against what was said ([verifyScores]) and joins them.
/// A criterion both runs gave the same level keeps it, with the first run's
/// quote. Where they differ, the lower level stands and is marked
/// [VerifiedScore.uncertain]. One run alone is checked as it is, with no
/// uncertainty marks. The strength and fix come from the first run (the
/// second when the first has none). [Verified.dropped] is the larger count
/// of the two runs.
Verified verifyRuns(List<List<AnswerScore>> runs, ScoringScale scale, DebriefRound round) {
  final checked = [
    for (final r in runs)
      verifyScores(r, scale, heard: round.heard, asked: round.asked, situational: round.situational),
  ];
  if (checked.isEmpty) return const Verified();
  if (checked.length == 1) return checked.single;
  final a = checked[0], b = checked[1];
  String key(VerifiedScore s) => '${s.question}\u0000${s.criterionId}';
  final second = {for (final s in b.scores) key(s): s};
  final merged = <VerifiedScore>[];
  final seen = <String>{};
  VerifiedScore none(VerifiedScore like) =>
      VerifiedScore(question: like.question, criterionId: like.criterionId, level: scale.noEvidence);
  for (final s in a.scores) {
    seen.add(key(s));
    final o = second[key(s)] ?? none(s);
    if (o.level == s.level) {
      merged.add(s);
      continue;
    }
    final low = scale.rank(o.level) < scale.rank(s.level) ? o : s;
    merged.add(_uncertain(low));
  }
  for (final o in b.scores) {
    if (seen.contains(key(o))) continue;
    // Only the second run scored it: the first, in effect, said no evidence.
    merged.add(o.level == scale.noEvidence ? o : _uncertain(none(o)));
  }
  return Verified(
    scores: merged,
    dropped: math.max(a.dropped, b.dropped),
    answers: {...b.answers, ...a.answers},
  );
}

VerifiedScore _uncertain(VerifiedScore s) => VerifiedScore(
  question: s.question,
  criterionId: s.criterionId,
  level: s.level,
  quote: s.quote,
  reason: s.reason,
  uncertain: true,
);

/// What re-checking a disputed score found.
class DisputeResult {
  const DisputeResult({required this.score, required this.stands, required this.message});

  /// The score after the re-check: the same one, or "no evidence".
  final VerifiedScore score;

  /// True when the score is unchanged.
  final bool stands;

  /// What to tell the candidate, in plain words.
  final String message;
}

/// Said with every dispute result: how a score can go up.
const disputeHowToRaise =
    'Disagreeing does not change a score. To show more, answer the question again: a new take is scored '
    'fresh against the same criteria.';

/// Re-checks a disputed [score] (honesty rule 6): is its quote still in
/// the candidate's own words for that question, is the criterion one that
/// question tests, and is the quote more than a bare claim? If all hold,
/// the score stands; otherwise it becomes "no evidence". A dispute can
/// never raise a score.
///
/// [pushback] is what the candidate said in disagreement. It is accepted
/// so that screens can pass it, and deliberately not read: pushback alone
/// never changes a score, and the same dispute with or without it gives
/// the same result (tested).
DisputeResult recheckScore(
  VerifiedScore score, {
  required DebriefRound round,
  required ScoringScale scale,
  String pushback = '',
}) {
  final transcript = round.heard[score.question] ?? '';
  final asked = round.asked[score.question] ?? const [];
  final none = VerifiedScore(question: score.question, criterionId: score.criterionId, level: scale.noEvidence);
  if (score.level == scale.noEvidence) {
    return DisputeResult(
      score: score,
      stands: true,
      message:
          'No evidence for this criterion was found in your words for this question, so it stays '
          '${scale.noEvidence.code}. $disputeHowToRaise',
    );
  }
  if (!asked.contains(score.criterionId)) {
    return DisputeResult(
      score: none,
      stands: false,
      message: 'This question does not test that criterion, so the score is taken off. $disputeHowToRaise',
    );
  }
  if (!quoteInTranscript(score.quote, transcript)) {
    return DisputeResult(
      score: none,
      stands: false,
      message:
          'The line this score quoted is not in your words for this question, so it reads as '
          '${scale.noEvidence.code}. $disputeHowToRaise',
    );
  }
  if (claimWithoutExample(score.quote, transcript, situational: round.situational.contains(score.question))) {
    return DisputeResult(score: none, stands: false, message: '$claimNote $disputeHowToRaise');
  }
  final up = scale.next(score.level);
  return DisputeResult(
    score: score,
    stands: true,
    message:
        'The score stays at ${score.level.code} (${score.level.label}): "${score.quote}" is in your answer, and '
        'that level\'s anchor is: ${score.level.anchor}'
        '${up == null ? '' : ' The next level, ${up.code}, needs: ${up.anchor}'} $disputeHowToRaise',
  );
}
