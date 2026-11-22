import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';

/// A brain with canned replies, as an app adapter is in tests. It keeps
/// every request so a test can read what would go to the model.
class CannedBrain extends PromptedInterviewBrain {
  CannedBrain(this.replies);
  final List<Map<String, Object?>> replies;
  final asked = <BrainRequest>[];

  @override
  Future<Map<String, Object?>> ask(BrainRequest request) async {
    asked.add(request);
    return replies.removeAt(0);
  }
}

const _question = EngineQuestion({
  'question': 'Tell us about a time you fixed a process.',
  'category': 'Behavioural',
  'why': 'Improvement mindset',
  'lookFor': ['Situation', 'Measured result'],
  'difficulty': 'hard',
  'criteria': ['c1'],
});

void main() {
  group('the question seam', () {
    test('EngineQuestion reads the AI shape and keeps every key it was given', () {
      expect(_question.category, 'Behavioural');
      expect(_question.lookFor, ['Situation', 'Measured result']);
      expect(_question.difficulty, 'hard');
      expect(criteriaOf(_question), ['c1'], reason: 'keys the engine adds travel in the JSON');
      expect(_question.j['criteria'], ['c1']);
    });

    test('missing or wrong-typed fields read as empty values, not invented ones', () {
      const q = EngineQuestion({
        'question': 7,
        'lookFor': ['ok', 3, ''],
      });
      expect(q.question, '7');
      expect(q.lookFor, ['ok', '3']);
      expect(q.difficulty, '');
      expect(q.why, '');
    });
  });

  group('the brain', () {
    test('a round plan is parsed from the reply; only the questions go', () async {
      final brain = CannedBrain([
        {
          'questions': [
            {
              'criterion': 'Improvement',
              'expected': ['ownAction', 'measure'],
              'probes': [
                {'element': 'measure', 'text': 'How did you know it worked?'},
              ],
            },
          ],
        },
      ]);
      final plans = await brain.planRound(role: 'Officer "B"', questions: const [_question]);
      expect(plans.single.expected, [AnswerElement.ownAction, AnswerElement.measure]);
      final r = brain.asked.single;
      expect(r.effort, 'low');
      expect(r.texts.first, contains('<round role="Officer \'B\'">'));
      expect(
        r.texts.first,
        contains('kind="Behavioural">Tell us about a time you fixed a process.</question>'),
      );
    });

    test('scores carry the engine version; the request holds transcripts and criteria only', () async {
      final brain = CannedBrain([
        {
          'answers': [
            {
              'question': 1,
              'scores': [
                {'criterion': 'c1', 'level': '3', 'quote': 'I moved the overflow'},
              ],
              'strength': 'A clear example.',
              'fix': 'Say how you knew it worked.',
            },
          ],
        },
      ]);
      final scores = await brain.scoreRound(
        role: 'Officer',
        framework: Framework.of('nhs_values'),
        criteria: const [Criterion(id: 'c1', text: 'Managing a diary')],
        answers: const [
          (index: 0, question: 'Q?', criteria: ['c1'], answer: 'I moved the overflow.'),
        ],
      );
      expect(scores.single.question, 0);
      expect(scores.single.engine, engineVersion);
      expect(scores.single.toJson()['engine'], engineVersion);
      expect(AnswerScore.fromJson(scores.single.toJson()).engine, engineVersion);
      expect(AnswerScore.fromJson(const {'question': 0}).engine, '', reason: 'older saves have no version');
      final r = brain.asked.single;
      expect(r.texts.join('\n'), contains('<said>\nI moved the overflow.\n</said>'));
      expect(r.schema['type'], 'object');
    });

    test('criteria come back raw for the app to check; follow-ups stay on the device', () async {
      final brain = CannedBrain([
        {'criteria': []},
      ]);
      expect(await brain.readCriteria(advert: 'Advert text', title: 'Clerk'), {'criteria': []});
      expect(brain.asked.single.texts.first, '<advert title="Clerk">\nAdvert text\n</advert>');
      final plan = templatePlan(_question);
      expect(await brain.followUp(question: _question, plan: plan, answer: 'Yes.'), isNull);
    });
  });

  group('stories and metrics', () {
    test('a practice answer drafts a story; competencies come from the app\'s list', () {
      final d = storyFromAnswer(
        title: 'Practice: clearing a double-booked diary',
        answer:
            'In my last role the clinic diary was double-booked most Mondays. I rang each patient on the list, '
            'I moved the overflow to a Tuesday session and I told the consultant. As a result the double '
            'bookings fell from nine a week to one.',
        criteria: ['Experience of managing a busy appointments diary and working with others'],
        competencies: const ['prioritising', 'teamwork'],
      );
      expect(d.situation, startsWith('In my last role'));
      expect(d.action, contains('I rang each patient'));
      expect(d.result, contains('fell from nine a week to one'));
      expect(d.competencies, [
        'teamwork',
      ], reason: '"diary" is not a prioritising word; ids not known are left out');
      expect(competenciesFor(['team work and planning'], known: const ['teamwork']), ['teamwork']);
    });

    test('answer metrics count fillers, ownership, figures and STAR', () {
      final m = AnswerMetrics.of(
        'Um, so basically we had late observations. I set up a pilot and I trained 40 staff. '
        'As a result late observations fell 30%.',
      );
      expect(m.fillers, 2);
      expect(m.iCount, 2);
      expect(m.weCount, 1);
      expect(m.figures, 2);
      expect(m.star, contains('Result'));
      expect(m.lengthVerdict, startsWith('Short'));
    });
  });

  test('engineVersion matches pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim(), engineVersion);
  });
}
