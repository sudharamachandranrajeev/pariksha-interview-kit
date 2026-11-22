/// One interview question, as the engine sees it.
///
/// This is the package seam for Udyoga's `PracticeQuestion`: plain data
/// with no database row behind it. It keeps the JSON it was made from in
/// [j], so keys the engine adds (`criteria`, `seconds`, `fixedTime`) and
/// keys an app adds for itself travel with the question and come back out
/// unchanged. Each app maps its own question type to and from this one
/// (Udyoga's `PracticeQuestion` is the same shape, so it is an alias).
library;

import 'json.dart';

/// A question the interviewer asks, with what the panel is testing and
/// what a top answer includes. The criteria in [lookFor] are fixed before
/// the candidate answers and are shown with the question (honesty rule 1).
class EngineQuestion {
  const EngineQuestion(this.j);

  /// The question's JSON: `question`, `category`, `why`, `lookFor`,
  /// `difficulty`, plus any other keys. Missing or wrongly typed fields
  /// read as empty values, never as invented ones.
  final Json j;

  /// The question as the candidate hears or reads it.
  String get question => str(j['question']);

  /// For example Behavioural, Values, Technical, Situational or Motivation.
  String get category => str(j['category']);

  /// What the panel is testing with this question.
  String get why => str(j['why']);

  /// What a top answer includes: the fixed scoring criteria.
  List<String> get lookFor => strs(j['lookFor']);

  /// `standard`, `hard` or `toughest`; empty when not given.
  String get difficulty => str(j['difficulty']);
}
