import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';

/// A brain with canned replies, as an app adapter would be in tests.
class _CannedBrain implements InterviewBrain {
  @override
  Future<List<EngineQuestion>> planRound({
    required String role,
    required List<String> criteria,
    List<String> stories = const [],
    int count = 5,
  }) async => [
    for (var i = 0; i < count; i++)
      EngineQuestion(question: 'Q${i + 1} for $role', lookFor: criteria, category: 'Behavioural'),
  ];

  @override
  Future<String?> followUp({required EngineQuestion question, required String answer}) async =>
      answer.length < 20 ? 'Can you give a specific example?' : null;

  @override
  Future<List<QuotedScore>> score({required EngineQuestion question, required String transcript}) async => [
    for (final c in question.lookFor) QuotedScore(criterion: c, score: null, quote: ''),
  ];
}

void main() {
  test('EngineQuestion reads the AI shape and writes it back unchanged', () {
    final j = {
      'question': 'Tell us about a time you fixed a process.',
      'category': 'Behavioural',
      'why': 'Improvement mindset',
      'lookFor': ['Situation', 'Measured result'],
      'difficulty': 'hard',
    };
    final q = EngineQuestion.fromJson(j);
    expect(q.difficulty, Difficulty.hard);
    expect(q.lookFor, ['Situation', 'Measured result']);
    expect(q.toJson(), j);
  });

  test('missing or wrong-typed fields fall back to empty values, not invented ones', () {
    final q = EngineQuestion.fromJson({
      'question': 7,
      'lookFor': ['ok', 3],
      'difficulty': 'impossible',
    });
    expect(q.question, '');
    expect(q.lookFor, ['ok']);
    expect(q.difficulty, Difficulty.standard);
  });

  test('an app brain plugs in through InterviewBrain', () async {
    final InterviewBrain brain = _CannedBrain();
    final qs = await brain.planRound(role: 'Project support officer', criteria: ['Planning'], count: 2);
    expect(qs, hasLength(2));
    expect(await brain.followUp(question: qs.first, answer: 'Yes.'), isNotNull);
    final scores = await brain.score(question: qs.first, transcript: 'Yes.');
    expect(scores.single.score, isNull, reason: 'no quote means N/O');
  });
}
