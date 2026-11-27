// The answer checker (journey plan J6): one test per honesty rule
// (rule01 … rule12), the sycophancy probes, the rewrite-invention check,
// question ranking with and without cards, and expectations split by who
// expects them. Every role, employer, card and answer here is made up.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';
import 'package:interview_engine/testing.dart';

const criteria = [
  Criterion(id: 'c1', text: 'Plans and prioritises a busy workload', assessBy: ['A', 'I']),
  Criterion(id: 'c2', text: 'Communicates clearly with colleagues', essential: false, assessBy: ['I']),
  Criterion(id: 'c3', text: 'Keeps accurate records', assessBy: ['A']),
  Criterion(id: 'c4', text: 'Typing at 40 words a minute', assessBy: ['T']),
  Criterion(id: 'c5', text: 'Experience of a hospital patient system'),
];

const profile = RoleProfile(id: 'p1', title: 'Ward clerk', frameworkId: 'nhs_values', criteria: criteria);

const question = EngineQuestion({
  'question': 'Tell us about a time you had several deadlines at once. What did you do?',
  'category': 'Behavioural',
  'why': 'Prioritising under pressure',
  'lookFor': <String>[],
  'criteria': ['c1', 'c2', 'c3'],
});

const answer =
    'Last March I ran the weekend rota on Ward 4 while two clerks were off. I rang the bank staff and moved '
    'two shifts, and every shift was covered by Monday morning. I emailed the ward manager a list of what I '
    'changed and logged each change in the rota system.';

const quote1 = 'I rang the bank staff and moved two shifts';
const quote2 = 'I emailed the ward manager a list of what I changed';

DebriefRound roundOf(String said) =>
    DebriefRound.of(questions: const [question], answers: {0: said}, profile: profile);

final framework = Framework.of('nhs_values');
final scale = framework.scale;

List<String> orderIn(BrainRequest r) => [
  for (final m in RegExp(r'<criterion id="([^"]+)"').allMatches(r.texts.first)) m[1]!,
];

String saidIn(BrainRequest r) => RegExp(r'<said>\n([\s\S]*?)\n</said>').firstMatch(r.texts[1])![1]!;

Map<String, Object?> reply(
  List<Map<String, String>> scores, {
  String strength = 'You said what you yourself did.',
  String strengthQuote = quote1,
  String fix = 'Say how you knew it worked.',
}) => {
  'answers': [
    {'question': 1, 'scores': scores, 'strength': strength, 'strengthQuote': strengthQuote, 'fix': fix},
  ],
};

Map<String, Object?> honestScores(BrainRequest r) => reply([
  {'criterion': 'c1', 'level': '3', 'quote': quote1},
  {'criterion': 'c2', 'level': '2', 'quote': quote2},
  {'criterion': 'c3', 'level': 'N/O', 'quote': ''},
]);

/// A flatterable judge: any praise or self-description in what it is sent
/// earns a 4 for every criterion, quoting the praise; otherwise it is
/// honest.
Map<String, Object?> flatterable(BrainRequest r) {
  final said = saidIn(r).toLowerCase();
  for (final bait in ['great', 'deserves', 'natural', 'brilliant']) {
    if (said.contains(bait)) {
      return reply([
        for (final id in orderIn(r)) {'criterion': id, 'level': '4', 'quote': 'I think this is great'},
      ]);
    }
  }
  return honestScores(r);
}

Future<(Verified, List<BrainRequest>)> scoreBoth(
  String said,
  Map<String, Object?> Function(BrainRequest) judge,
) async {
  final brain = ScriptedBrain(judge);
  final round = roundOf(said);
  final runs = await scoreTwice(
    brain: brain,
    role: 'Ward clerk',
    framework: framework,
    round: round,
    random: math.Random(7),
  );
  return (verifyRuns(runs, scale, round), brain.requests);
}

String fingerprint(Verified v) =>
    [for (final s in v.scores) '${s.criterionId}:${s.level.code}:${s.quote}:${s.uncertain}'].join('|');

const cards = [
  EvidenceCard(
    id: 'k1',
    claim: 'The trust values compassion and respect for every patient.',
    quote: 'Our values are compassion, respect and working together.',
    kind: 'values',
    status: CardStatus.verified,
    sourceTitle: 'Example Health annual report',
    sourceDate: '2026-06-30',
  ),
  EvidenceCard(
    id: 'k2',
    claim: 'The trust is moving every ward to a digital patient record by 2027.',
    quote: 'Every ward will move to the digital patient record by 2027.',
    kind: 'strategy',
    status: CardStatus.userConfirmed,
    sourceTitle: 'Board papers',
    sourceDate: '2026-09-12',
  ),
  EvidenceCard(
    id: 'k3',
    claim: 'The team covers weekend rota gaps with bank staff.',
    quote: 'The ward clerks arrange bank staff cover for weekend rota gaps.',
    kind: 'team',
    status: CardStatus.verified,
    sourceTitle: 'Job description',
    sourceDate: '2026-10-01',
  ),
  EvidenceCard(
    id: 'k4',
    claim: 'The trust plans to close the outpatient wing.',
    kind: 'strategy',
    status: CardStatus.inference,
  ),
  EvidenceCard(
    id: 'k5',
    claim: 'A candidate says the panel asked about a time they handled an upset relative.',
    quote: 'They asked me: Tell us about a time you calmed an upset relative?',
    kind: 'reviews-anecdotal',
    status: CardStatus.verified,
    sourceTitle: 'Pasted review',
  ),
];

void main() {
  group('the twelve honesty rules', () {
    test(
      'rule01_criteria_fixed: only the agreed criteria are sent, and a score for any other is dropped',
      () {
        final r = scoreRequest(
          role: 'Ward clerk',
          framework: framework,
          criteria: criteria,
          answers: const [
            (index: 0, question: 'Q', criteria: ['c1'], answer: answer),
          ],
        );
        expect(orderIn(r), [for (final c in criteria) c.id]);
        expect(jsonEncode(r.schema), contains(jsonEncode([for (final c in criteria) c.id])));
        final v = verifyScores(
          [
            const AnswerScore(
              question: 0,
              scores: [
                CriterionScore(criterionId: 'c9', code: '4', quote: quote1),
                CriterionScore(criterionId: 'c1', code: '3', quote: quote1),
              ],
            ),
          ],
          scale,
          heard: {0: answer},
          asked: {
            0: ['c1'],
          },
        );
        expect(
          [for (final s in v.scores) s.criterionId],
          ['c1'],
          reason: 'no criterion is added after the answer',
        );
        expect(v.dropped, 1);
      },
    );

    test('rule02_quote_checked: a score whose quote is not in the answer reads as N/O', () {
      final v = verifyScores(
        [
          const AnswerScore(
            question: 0,
            scores: [
              CriterionScore(criterionId: 'c1', code: '4', quote: 'I rebuilt the rota system from scratch'),
            ],
          ),
        ],
        scale,
        heard: {0: answer},
        asked: {
          0: ['c1'],
        },
      );
      expect(v.scores.single.level.code, 'N/O');
      expect(v.dropped, 1);
    });

    test(
      'rule03_cards_are_sourced: only verified or user-confirmed cards feed questions, each citing its card',
      () {
        expect(CardStatus.of('verified'), CardStatus.verified);
        expect(CardStatus.of('user-confirmed'), CardStatus.userConfirmed);
        expect(CardStatus.of('anything else'), CardStatus.inference);
        final qs = rankQuestions(criteria: criteria, cards: cards, max: 30);
        final org = [
          for (final q in qs)
            if (q.tier == EvidenceTier.organisation) q,
        ];
        expect(org, isNotEmpty);
        for (final q in org) {
          final card = cards.firstWhere((c) => c.id == q.cardId);
          expect(card.usable, isTrue, reason: q.question);
          expect(q.why, contains(card.sourceTitle));
        }
        expect(qs.any((q) => q.cardId == 'k4'), isFalse, reason: 'an inference card never makes a question');
      },
    );

    test('rule04_stale_flagged: a stale card says so wherever it is cited', () {
      const stale = EvidenceCard(
        id: 's1',
        claim: 'Our values are kindness and openness.',
        quote: 'Our values are kindness and openness.',
        kind: 'values',
        status: CardStatus.verified,
        sourceTitle: 'Old values page',
        sourceDate: '2023-01-01',
        stale: true,
      );
      final qs = rankQuestions(criteria: const [], cards: const [stale]);
      expect(qs.where((q) => q.cardId == 's1'), isNotEmpty);
      for (final q in qs.where((q) => q.cardId == 's1')) {
        expect(q.why, contains('may be out of date'));
      }
    });

    test('rule05_inference_labelled: inference-only cards are named as such and never used', () {
      const onlyInference = [
        EvidenceCard(id: 'i1', claim: 'The trust values speed.', kind: 'values'),
        EvidenceCard(id: 'i2', claim: 'The team is short-staffed.', kind: 'team'),
      ];
      expect(organisationTierNote(onlyInference), onlyInferenceNote);
      final e = answerExpectations(round: roundOf(answer), framework: framework, cards: onlyInference).single;
      expect(e.of(ExpectationSource.organisation).note, onlyInferenceNote);
      expect(e.of(ExpectationSource.manager).note, onlyInferenceNote);
      expect(e.of(ExpectationSource.organisation).hits, isEmpty);
      expect(
        rankQuestions(criteria: const [], cards: onlyInference).where((q) => q.cardId.isNotEmpty),
        isEmpty,
      );
    });

    test('rule06_pushback_alone: "I think that deserves a 4" never moves a score', () {
      final round = roundOf(answer);
      final good = VerifiedScore(question: 0, criterionId: 'c1', level: scale.level('3')!, quote: quote1);
      final plain = recheckScore(good, round: round, scale: scale);
      final pushed = recheckScore(good, round: round, scale: scale, pushback: 'I think that deserves a 4.');
      expect(pushed.score.level.code, '3');
      expect(pushed.message, plain.message);
      final none = VerifiedScore(question: 0, criterionId: 'c3', level: scale.noEvidence);
      expect(
        recheckScore(none, round: round, scale: scale, pushback: 'I think that deserves a 4.').score.level,
        scale.noEvidence,
      );
    });

    test('rule07_no_model_answer_first: no rewrite before an attempt, and none that invents', () async {
      final brain = ScriptedBrain((r) => {'answer': 'I rang the bank staff and moved two shifts.'});
      final empty = await improveAnswer(brain: brain, question: question.question, answer: '');
      expect(empty.refused, isTrue);
      expect(empty.message, noAttemptNote);
      final short = await improveAnswer(brain: brain, question: question.question, answer: 'I would plan.');
      expect(short.refused, isTrue);
      expect(brain.requests, isEmpty, reason: 'nothing is asked of the AI before the candidate tries');

      final ok = await improveAnswer(brain: brain, question: question.question, answer: answer);
      expect(ok.ok, isTrue);
      expect(brain.requests.single.texts.join(), contains(quote1));

      final inventing = ScriptedBrain(
        (r) => {'answer': 'I cut overtime by 40% on Ward 4 using Lorenzo, and won an award for it.'},
      );
      final bad = await improveAnswer(brain: inventing, question: question.question, answer: answer);
      expect(bad.refused, isTrue);
      expect(bad.text, '');
      expect(bad.invented, containsAll(['40', 'lorenzo', 'won', 'award']));
    });

    test(
      'rule08_scored_twice: two runs in different orders; disagreement shows the lower level, uncertain',
      () async {
        var call = 0;
        final (v, asked) = await scoreBoth(answer, (r) {
          call++;
          return reply([
            {'criterion': 'c1', 'level': call == 1 ? '3' : '2', 'quote': quote1},
            {'criterion': 'c2', 'level': '2', 'quote': quote2},
          ]);
        });
        expect(asked, hasLength(2));
        expect(orderIn(asked[0]), isNot(orderIn(asked[1])));
        final c1 = v.scores.firstWhere((s) => s.criterionId == 'c1');
        expect(c1.level.code, '2');
        expect(c1.uncertain, isTrue);
        final d = Debrief.build(framework: framework, round: roundOf(answer), verified: v);
        final words = [
          for (final c in d.coverage) c.note,
          for (final n in d.notes) '${n.strength} ${n.fix}',
        ].join(' ');
        expect(words, isNot(contains('%')), reason: 'no confidence percentages');
        expect(words, contains(uncertainNote));
      },
    );

    test('rule09_one_strength_one_fix: praise must quote its line; exactly one fix', () {
      final round = roundOf(answer);
      final unquoted = verifyRuns(
        [
          parseScoring(
            reply(
              [
                {'criterion': 'c1', 'level': '3', 'quote': quote1},
              ],
              strength: 'Brilliant, very impressive answer.',
              strengthQuote: 'I was brilliant',
              fix: 'Say how you knew it worked. Also add more detail. And smile.',
            ),
          ),
        ],
        scale,
        round,
      );
      expect(unquoted.answers[0]!.strength, '', reason: 'praise without its line is not shown');
      expect(unquoted.answers[0]!.fix, 'Say how you knew it worked.');
      final d = Debrief.build(framework: framework, round: round, verified: unquoted);
      final note = d.notes.single;
      expect(note.strength, isNot(contains('Brilliant')));
      expect(note.strengthQuote, isNotEmpty);
      expect(quoteInTranscript(note.strengthQuote, round.heard[0]!), isTrue);
      expect(note.strengthCriterion, 'c1');
      expect(note.fix.split(RegExp(r'(?<=[.!?])\s+')), hasLength(1));

      // An answer with no quotable example gets the note, never invented praise.
      final claim = Debrief.build(
        framework: framework,
        round: roundOf('I am a very good team player and I value working together.'),
      ).notes.single;
      expect(claim.strength, noStrengthNote);
      expect(claim.strengthQuote, '');
    });

    test('rule10_not_found: no cards means "no sources yet", never a guess', () {
      final e = answerExpectations(round: roundOf(answer), framework: framework).single;
      expect(e.of(ExpectationSource.organisation).note, noSourcesNote);
      expect(e.of(ExpectationSource.manager).note, noSourcesNote);
      expect(e.of(ExpectationSource.panel).hits, isNotEmpty);
      expect(organisationTierNote(const []), notInSourcesNote);
      final qs = rankQuestions(criteria: criteria);
      expect(qs.where((q) => q.tier == EvidenceTier.organisation), isEmpty);
      expect(qs.where((q) => q.cardId.isNotEmpty), isEmpty);
    });

    test(
      'rule11_real_scales: each process template scores on its real scale, with this and the next anchor',
      () {
        expect(nhsStyle.framework.scale.codes, ['N/O', '1', '2', '3', '4']);
        expect(civilServiceStyle.framework.scale.codes, ['1', '2', '3', '4', '5', '6', '7']);
        expect(privateSectorStyle.framework.scale.codes, ['1', '2', '3', '4']);
        expect(Framework.of('hsc_ni').scale.codes, ['0', '1', '2', '3']);
        final saved = InterviewProcess.fromJson(
          jsonDecode(jsonEncode(civilServiceStyle.toJson())) as Map<String, Object?>,
        );
        expect(saved.frameworkId, 'civil_service');
        expect(InterviewProcess.fromJson({'id': 'mine', 'name': 'Mine'}).frameworkId, 'private');

        final v = verifyScores(
          [
            const AnswerScore(
              question: 0,
              scores: [
                CriterionScore(criterionId: 'c1', code: '3', quote: quote1),
                CriterionScore(criterionId: 'c2', code: '4', quote: quote2),
              ],
            ),
          ],
          scale,
          heard: roundOf(answer).heard,
          asked: roundOf(answer).asked,
        );
        final lines = Debrief.build(framework: framework, round: roundOf(answer), verified: v).scoreLines();
        final c1 = lines.firstWhere((l) => l.criterion.id == 'c1');
        expect(c1.level.anchor, scale.level('3')!.anchor);
        expect(c1.next!.anchor, scale.level('4')!.anchor);
        expect(lines.firstWhere((l) => l.criterion.id == 'c2').next, isNull, reason: 'nothing above the top');
      },
    );

    test('rule12_same_rules_everywhere: quote-less praise from a local or cloud model scores N/O', () async {
      // A model that praises and never quotes.
      Map<String, Object?> praise(BrainRequest r) => {
        'answers': [
          {
            'question': 1,
            'scores': [
              for (final id in orderIn(r)) {'criterion': id, 'level': '4', 'quote': ''},
            ],
            'strength': 'Outstanding answer, truly excellent!',
            'strengthQuote': '',
            'fix': 'Nothing to fix.',
          },
        ],
      };
      final cloud = ScriptedBrain(praise);
      final local = _TextBrain((system, text) {
        expect(system, contains('Reply with one JSON object only'));
        // A local model wraps its JSON in chat and a code fence.
        return 'Sure! Here is the scoring:\n```json\n${jsonEncode(praise(cloud.requests.last))}\n```';
      }, cloud);
      final round = roundOf(answer);
      Future<Verified> run(InterviewBrain b) async => verifyRuns(
        await scoreTwice(
          brain: b,
          role: 'Ward clerk',
          framework: framework,
          round: round,
          random: math.Random(3),
        ),
        scale,
        round,
      );
      final fromCloud = await run(cloud);
      final fromLocal = await run(local);
      expect(fingerprint(fromLocal), fingerprint(fromCloud));
      for (final s in fromCloud.scores) {
        expect(s.level, scale.noEvidence);
      }
      final note = Debrief.build(framework: framework, round: round, verified: fromLocal).notes.single;
      expect(note.strength, isNot(contains('Outstanding')));
      expect(quoteInTranscript(note.strengthQuote, round.heard[0]!), isTrue);
    });
  });

  test('rule09 in a live round: the on-device strength quotes its line, or says none was found', () {
    const said =
        'I am a hard worker. Last winter I rang each patient on the waiting list and booked them in.';
    final s = quotedStrength(said);
    expect(s.quote, isNotEmpty);
    expect(said, contains(s.quote));
    expect(s.quote, isNot(contains('hard worker')));
    expect(quotedStrength('I am a hard worker and a team player.').quote, '');
    expect(quotedStrength('I am a hard worker and a team player.').text, noStrengthNote);
    expect(const ContentNote('x', 'y', quote: 'z').quote, 'z');
  });

  group('the challenging panel keeps the twelve rules', () {
    // A vague, "we" answer that claims success without evidence.
    const vague =
        'We had a big backlog on the ward last winter. We sat down as a team and sorted it. '
        'Usually we would split the work, and it went well in the end.';
    final plan = templatePlan(question);
    final challenging = Persona.of(PersonaKind.challenging);

    /// Every follow-up the challenging panel asks after [said], replying
    /// [reply] each time, up to its limit at level 5.
    List<Probe> pressed(String said, {String reply = 'It was fine.'}) {
      final asked = <Probe>[];
      var heard = said;
      final limit = Interviewer(persona: challenging, level: Ladder.of(5), plans: const []).probeLimit;
      while (true) {
        final p = ProbePicker.next(plan: plan, heard: heard, asked: asked, limit: limit, challenge: true);
        if (p == null) return asked;
        asked.add(p);
        heard = '$heard $reply';
      }
    }

    test('rule01_criteria_fixed (challenging): it only probes the elements the plan agreed', () {
      final probes = pressed(vague);
      expect(probes, isNotEmpty);
      for (final p in probes) {
        expect(plan.expected, contains(p.element));
      }
      const none = QuestionPlan(criterion: 'Motivation', expected: []);
      expect(ProbePicker.next(plan: none, heard: vague, asked: const [], limit: 3, challenge: true), isNull);
    });

    test('rule02_quote_checked (challenging): every quote is a span of what the candidate said', () {
      final probes = pressed(vague);
      final quoted = probes.where((p) => p.text.contains('"')).toList();
      expect(quoted, isNotEmpty);
      for (final p in quoted) {
        final q = RegExp(r'"([^"]+)"').firstMatch(p.text)![1]!;
        expect(quoteInTranscript(q, vague), isTrue, reason: p.text);
      }
      expect(quotedChallenge(AnswerElement.ownAction, vague)!.text, contains('"We had a big backlog'));
      // Nothing fitting to quote: no quote at all, never a made-up one.
      expect(quotedChallenge(AnswerElement.ownAction, 'I did it.'), isNull);
      expect(quotesOnlyHeard('You said "we lost the files". Why?', vague), isFalse);
      expect(quotesOnlyHeard('What evidence shows that worked?', vague), isTrue);
    });

    test('rule03_cards_are_sourced (challenging): a challenge cites no card and no outside claim', () {
      for (final p in pressed(vague)) {
        for (final c in cards) {
          expect(p.text, isNot(contains(c.claim)));
        }
      }
    });

    test(
      'rule07_no_model_answer_first (challenging): a challenge invents no number, name or achievement',
      () {
        for (final said in [vague, answer]) {
          for (final p in pressed(said)) {
            final line = p.text.replaceAll(RegExp(r'"[^"]*"'), '');
            expect(numbersIn(line), isEmpty, reason: p.text);
            expect(achievementsIn(line), isEmpty, reason: p.text);
            final quote = RegExp(r'"([^"]+)"').firstMatch(p.text)?[1];
            if (quote != null) expect(inventedTokens(quote, answer: said), isEmpty, reason: p.text);
          }
        }
        for (final list in builtInChallengeProbes.values) {
          for (final line in list) {
            expect(numbersIn(line), isEmpty, reason: line);
            expect(achievementsIn(line), isEmpty, reason: line);
          }
        }
      },
    );

    test('rule12_same_rules_everywhere (challenging): an AI-written probe gets the same checks', () {
      final ai = QuestionPlan(
        criterion: 'Prioritising',
        expected: const [AnswerElement.ownAction, AnswerElement.measure],
        probes: const [
          Probe(AnswerElement.ownAction, 'You said "I saved the ward single-handed". Is that true?'),
          Probe(AnswerElement.ownAction, 'Seriously, what did you even do?'),
          Probe(AnswerElement.ownAction, 'At your age, how did you cope?'),
          Probe(AnswerElement.ownAction, 'So are you saying the whole team did it?'),
        ],
      );
      const said = 'We had a big backlog. The team sorted it out.';
      final p = ProbePicker.next(plan: ai, heard: said, asked: const [], limit: 3, challenge: true)!;
      // The quote of the candidate's own words comes first …
      expect(p.text, 'You said "We had a big backlog". What did you personally do?');
      final second = ProbePicker.next(plan: ai, heard: '$said Fine.', asked: [p], limit: 3, challenge: true)!;
      // … then the press skips the invented quote, the sarcasm and the personal line.
      expect(second.text, 'So are you saying the whole team did it?');
      // The planning prompt is one for every model, local or cloud, with the tone limits.
      final r = planRequest(
        role: 'Ward clerk',
        questions: const [question],
        persona: PersonaKind.challenging,
      );
      expect(r.system, contains('firm but professional'));
      expect(r.system, contains('never rude, sarcastic, personal or discriminatory'));
      expect(r.system, contains('quote nothing'));
      expect(planRequest(role: 'Ward clerk', questions: const [question]).system, contains('never leading'));
      expect(personaGuidance(PersonaKind.neutral), isEmpty);
    });

    test('challenge tone: firm, never rude, sarcastic, personal or discriminatory', () {
      final lines = [
        for (final list in builtInChallengeProbes.values) ...list,
        challenging.greeting,
        challenging.probeLead,
        ...challenging.acknowledgements,
        challenging.interruption,
        for (final said in [vague, answer]) ...pressed(said).map((p) => p.text),
        personaGuidance(PersonaKind.challenging).split('Limits:').first,
      ];
      for (final l in lines) {
        expect(professionalTone(l), isTrue, reason: l);
      }
      for (final bad in [
        'That is ridiculous.',
        'Really? Come on.',
        'Are you lying to us?',
        'How old are you?',
        'Where are you really from?',
        'Is your accent a problem?',
      ]) {
        expect(professionalTone(bad), isFalse, reason: bad);
      }
      // Leading and premise-testing forms are there.
      final all = lines.join(' ');
      expect(all, contains('So are you saying'));
      expect(all, contains("wouldn't it have been better"));
      expect(all, contains('What evidence shows that worked?'));
    });

    test('presses once on a vague reply, at most three follow-ups; other panels keep two', () {
      final probes = pressed(vague);
      expect(probes, hasLength(maxChallengeProbes));
      expect(probes[1].element, probes[0].element);
      expect(probes.map((p) => p.text.toLowerCase()).toSet(), hasLength(probes.length));
      for (final k in PersonaKind.values) {
        final limit = Interviewer(persona: Persona.of(k), level: Ladder.of(5), plans: const []).probeLimit;
        expect(limit, k == PersonaKind.challenging ? 3 : 2, reason: k.name);
        expect(Interviewer(persona: Persona.of(k), level: Ladder.of(1), plans: const []).probeLimit, 0);
      }
      // Without the flag the picker still stops at two.
      expect(
        ProbePicker.next(
          plan: plan,
          heard: vague,
          asked: const [Probe(AnswerElement.ownAction, 'a'), Probe(AnswerElement.situation, 'b')],
          limit: 3,
        ),
        isNull,
      );
    });
  });

  group('sycophancy probes', () {
    test('praise appended: the same request and the same scores', () async {
      final (plain, plainAsked) = await scoreBoth(answer, flatterable);
      final (flattered, flatteredAsked) = await scoreBoth('$answer I think this is great.', flatterable);
      expect(
        [for (final r in flatteredAsked) jsonEncode(r.texts)],
        [for (final r in plainAsked) jsonEncode(r.texts)],
      );
      expect(fingerprint(flattered), fingerprint(plain));
    });

    test('"I think that deserves a 4" inside the answer changes nothing', () async {
      final (plain, _) = await scoreBoth(answer, flatterable);
      final (pushed, _) = await scoreBoth('$answer I think that deserves a 4.', flatterable);
      expect(fingerprint(pushed), fingerprint(plain));
    });

    test('a flattering self-description is taken out before scoring', () async {
      const flattery = [
        "I'm a natural leader.",
        'Everyone says I am brilliant.',
        'Honestly, I am an exceptional communicator.',
        "I've always been the perfect fit for this role.",
      ];
      final (plain, _) = await scoreBoth(answer, flatterable);
      for (final f in flattery) {
        expect(withoutSelfVerdicts('$answer $f'), answer, reason: f);
        final (flattered, _) = await scoreBoth('$answer $f', flatterable);
        expect(fingerprint(flattered), fingerprint(plain), reason: f);
      }
      // A plain claim stays, so the debrief can call it a claim.
      const claim = 'I am a very good team player and I value working together.';
      expect(withoutSelfVerdicts(claim), claim);
    });
  });

  group('the rewrite-invention check', () {
    test('new numbers, names and achievements are caught; the candidate\'s own are not', () {
      expect(
        inventedTokens('I moved two shifts and rang the bank staff on Ward 4.', answer: answer),
        isEmpty,
      );
      expect(inventedTokens('We covered 2 shifts by Monday.', answer: answer), isEmpty, reason: '"two" is 2');
      expect(inventedTokens('I cut overtime by 40%.', answer: answer), ['40']);
      expect(inventedTokens('I used the Lorenzo system.', answer: answer), ['lorenzo']);
      expect(inventedTokens('The EPR was down.', answer: answer), ['epr']);
      expect(inventedTokens('I was promoted soon after.', answer: answer), ['promoted']);
      expect(
        inventedTokens('Then I told the ward manager.', answer: answer),
        isEmpty,
        reason: 'an opener is no name',
      );
    });

    test('the story bank counts as the candidate\'s own words; case does not matter', () {
      const bank = ['In 2025 I trained three new clerks on the Lorenzo system and was commended for it.'];
      expect(
        inventedTokens(
          'I trained 3 clerks on Lorenzo in 2025 and was commended.',
          answer: answer,
          storyBank: bank,
        ),
        isEmpty,
      );
      expect(
        inventedTokens('I spoke to Sam.', answer: 'i spoke to sam about the rota and the shifts that week'),
        isEmpty,
      );
    });

    test('checkRewrite refuses an invention and says what was added', () {
      final r = checkRewrite('I saved £12,000 a year.', answer: answer);
      expect(r.refused, isTrue);
      expect(r.invented, ['12000']);
      expect(r.message, contains('12000'));
      expect(checkRewrite('', answer: answer).refused, isTrue);
      expect(checkRewrite('I rang the bank staff.', answer: answer).ok, isTrue);
    });
  });

  group('question ranking', () {
    test(
      'without cards: interview criteria first (essentials first), then generic; no test-only criterion',
      () {
        final qs = rankQuestions(criteria: criteria);
        expect(qs.first.criterionId, 'c1');
        expect(qs.first.tier, EvidenceTier.personSpec);
        expect(qs[1].criterionId, 'c2');
        expect(qs[1].tier, EvidenceTier.personSpec);
        expect(qs.where((q) => q.criterionId == 'c4'), isEmpty, reason: 'assessed by a test only');
        final c3 = qs.firstWhere((q) => q.criterionId == 'c3');
        expect(c3.tier, EvidenceTier.generic);
        expect(c3.why, contains('application'));
        expect(qs.firstWhere((q) => q.criterionId == 'c5').why, contains('does not say how it is assessed'));
        for (final q in qs) {
          expect(q.why, isNotEmpty);
        }
        expect(
          [for (final q in qs) q.tier.index],
          orderedEquals(
            [
              ...[for (final q in qs) q.tier.index],
            ]..sort(),
          ),
        );
      },
    );

    test('with cards: values and plans from usable cards, reported questions labelled anecdotal', () {
      final qs = rankQuestions(criteria: criteria, cards: cards, max: 30);
      final tiers = [for (final q in qs) q.tier.index];
      expect(tiers, orderedEquals([...tiers]..sort()), reason: 'strongest evidence first');
      final values = [
        for (final q in qs)
          if (q.cardId == 'k1') q,
      ];
      expect(values.map((q) => q.question).join(' '), allOf(contains('compassion'), contains('respect')));
      expect(qs.firstWhere((q) => q.cardId == 'k2').question, contains('digital patient record'));
      final reported = qs.firstWhere((q) => q.cardId == 'k5');
      expect(reported.tier, EvidenceTier.anecdotal);
      expect(reported.anecdotal, isTrue);
      expect(reported.why, startsWith('Anecdotal'));
      expect(reported.question, contains('upset relative'));
      expect(qs.where((q) => q.cardId == 'k3'), isEmpty, reason: 'a team card is no organisation question');
      expect(rankQuestions(criteria: criteria, cards: cards, max: 3), hasLength(3));
    });

    test('an AI may reword a question, never add to it', () async {
      final predicted = rankQuestions(criteria: criteria).take(2).toList();
      final brain = ScriptedBrain(
        (r) => {
          'questions': [
            'Can you tell us about a time you planned and prioritised a busy workload?',
            'Tell us how you used Lorenzo at St Elsewhere to communicate with 12 colleagues.',
          ],
        },
      );
      final worded = await wordPredictedQuestions(brain: brain, role: 'Ward clerk', predicted: predicted);
      expect(worded[0].question, startsWith('Can you tell us'));
      expect(worded[0].tier, predicted[0].tier);
      expect(worded[0].why, predicted[0].why);
      expect(worded[1].question, predicted[1].question, reason: 'the rewording invented names and a number');
      final failing = ScriptedBrain((r) => throw StateError('offline'));
      expect(
        [
          for (final q in await wordPredictedQuestions(brain: failing, role: 'x', predicted: predicted))
            q.question,
        ],
        [for (final q in predicted) q.question],
      );
    });

    test('a predicted question can be practised against its criterion', () {
      final q = rankQuestions(criteria: criteria).first.toEngineQuestion();
      expect(criteriaOf(q), ['c1']);
      expect(q.j['tier'], 'personSpec');
    });
  });

  group('expectations by who expects them', () {
    test('panel, organisation and manager, each tied to its criterion or card, quoting the line', () {
      final v = verifyRuns(
        [
          parseScoring(
            honestScores(scoreRequest(role: '', framework: framework, criteria: criteria, answers: const [])),
          ),
        ],
        scale,
        roundOf('$answer The new digital patient record will make the rota easier.'),
      );
      final e = answerExpectations(
        round: roundOf('$answer The new digital patient record will make the rota easier.'),
        framework: framework,
        verified: v,
        cards: cards,
      ).single;
      final panel = e.of(ExpectationSource.panel);
      expect([for (final h in panel.hits) h.expectation.criterionId], ['c1', 'c2', 'c3']);
      expect(panel.covered.map((h) => h.expectation.criterionId), ['c1', 'c2']);
      expect(panel.covered.first.quote, quote1);
      expect(panel.notCovered.single.expectation.criterionId, 'c3');
      expect(panel.hits.first.expectation.anchor, scale.level('2')!.anchor);

      final org = e.of(ExpectationSource.organisation);
      expect(
        [for (final h in org.hits) h.expectation.cardId],
        ['k1', 'k2'],
        reason: 'the inference card is left out',
      );
      expect(org.covered.single.expectation.cardId, 'k2');
      expect(org.covered.single.quote, contains('digital patient record'));
      expect(org.notCovered.single.expectation.cardId, 'k1');

      final manager = e.of(ExpectationSource.manager);
      expect(manager.covered.single.expectation.cardId, 'k3');
      expect(answer, contains(manager.covered.single.quote));
    });

    test('without an AI the panel line comes from the words on the device', () {
      const full =
          'In my last role the clinic diary was double-booked most Mondays. I rang each patient on the list, '
          'I moved the overflow to a Tuesday session and I told the consultant. As a result the double bookings '
          'fell from nine a week to one.';
      final e = answerExpectations(round: roundOf(full), framework: framework).single;
      final panel = e.of(ExpectationSource.panel);
      expect(panel.covered, hasLength(3));
      for (final h in panel.covered) {
        expect(quoteInTranscript(h.quote, full), isTrue);
      }
      final thin = answerExpectations(
        round: roundOf('I rang the bank staff on the day.'),
        framework: framework,
      );
      expect(thin.single.of(ExpectationSource.panel).covered, isEmpty);
    });
  });
}

/// A text-only adapter (as for a local Ollama server) that records the
/// requests on [cloud] so the same reply can be built for it.
class _TextBrain extends TextPromptedInterviewBrain {
  const _TextBrain(this.reply, this.cloud);
  final String Function(String system, String text) reply;
  final ScriptedBrain cloud;

  @override
  Future<String> send(String system, String text) async => reply(system, text);

  @override
  Future<Map<String, Object?>> ask(BrainRequest request) {
    cloud.requests.add(request);
    return super.ask(request);
  }
}
