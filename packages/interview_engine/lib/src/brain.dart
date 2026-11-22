/// The AI the engine talks to, injected by each app.
///
/// The engine never chooses or calls a model itself. Udyoga adapts its
/// `Ai` providers (Claude, Gemini, Claude Code, Ollama and the rest); Vidya
/// adapts brahma_core's `HelpAsker` and its local Ollama setting. Both go
/// through this interface, so scoring works the same in both apps and on
/// local and cloud models (honesty rule 12).
///
/// Most apps extend [PromptedInterviewBrain]: it holds the engine's own
/// instructions and schemas, and the app only sends one structured request
/// to its model ([PromptedInterviewBrain.ask]). The words sent are the same
/// in every app.
library;

import 'interview/interview_plan.dart';
import 'interview/interview_scoring.dart';
import 'json.dart';
import 'question.dart';
import 'schema.dart';

/// One answer of a round, as it goes to the scorer: the question's
/// [index] in the round, its text, the ids of the criteria it tests and
/// what the candidate said.
typedef RoundAnswer = ({int index, String question, List<String> criteria, String answer});

/// What an app must provide for the engine's AI steps.
///
/// Every method may throw the app's own error when its AI is missing or
/// fails; the engine's on-device plans and matcher work without one.
abstract interface class InterviewBrain {
  /// Plans a round (interview plan I2): for each of [questions], the
  /// criterion it tests, the elements a full answer has and probes for
  /// each. Only the questions go: no profile, no answers.
  Future<List<QuestionPlan>> planRound({required String role, required List<EngineQuestion> questions});

  /// Reads an advert and person specification into the criteria a panel
  /// agrees in advance (interview plan I3). The reply is parsed with
  /// [parseCriteria]; the user edits it before it is used.
  Future<Json> readCriteria({required String advert, String title = ''});

  /// One probing follow-up to [answer] worded by the AI, or null to use
  /// the probe the engine picks on the device from what the answer lacks
  /// ([QuestionPlan]'s probes). Udyoga always returns null.
  Future<String?> followUp({
    required EngineQuestion question,
    required QuestionPlan plan,
    required String answer,
  });

  /// Scores a whole round against the agreed [criteria] on [framework]'s
  /// scale. Every score must quote the transcript; the caller checks each
  /// quote with [verifyScores] and drops any that is not there. Each
  /// [AnswerScore] records the engine version that made it.
  Future<List<AnswerScore>> scoreRound({
    required String role,
    required Framework framework,
    required List<Criterion> criteria,
    required List<RoundAnswer> answers,
  });
}

/// One structured request to the app's model: a system prompt, text parts
/// in order, and the JSON schema the reply must follow.
class BrainRequest {
  const BrainRequest({
    required this.system,
    required this.texts,
    required this.schema,
    this.effort = 'medium',
    this.maxTokens = 8000,
  });

  final String system;

  /// Plain-text content parts, sent in this order.
  final List<String> texts;

  /// Built with the engine's schema helpers (every property required, no
  /// extras), so structured outputs accept it.
  final Json schema;

  /// `low`, `medium` or `high`: how hard the model should think.
  final String effort;
  final int maxTokens;
}

/// An [InterviewBrain] built on the engine's own instructions. An app
/// implements [ask] over its model client and gets the same prompts,
/// schemas and parsing as every other app.
abstract class PromptedInterviewBrain implements InterviewBrain {
  const PromptedInterviewBrain();

  /// Sends [request] to the app's model and returns the reply's JSON.
  Future<Json> ask(BrainRequest request);

  @override
  Future<List<QuestionPlan>> planRound({
    required String role,
    required List<EngineQuestion> questions,
  }) async {
    final data = await ask(planRequest(role: role, questions: questions));
    return [for (final q in objs(data['questions'])) QuestionPlan.fromJson(q)];
  }

  @override
  Future<Json> readCriteria({required String advert, String title = ''}) =>
      ask(criteriaRequest(advert: advert, title: title));

  @override
  Future<String?> followUp({
    required EngineQuestion question,
    required QuestionPlan plan,
    required String answer,
  }) async => null;

  @override
  Future<List<AnswerScore>> scoreRound({
    required String role,
    required Framework framework,
    required List<Criterion> criteria,
    required List<RoundAnswer> answers,
  }) async {
    final data = await ask(
      scoreRequest(role: role, framework: framework, criteria: criteria, answers: answers),
    );
    return parseScoring(data);
  }
}

String _attr(String s) => s.replaceAll('"', "'");

/// The request [PromptedInterviewBrain.planRound] sends.
BrainRequest planRequest({required String role, required List<EngineQuestion> questions}) => BrainRequest(
  system:
      'You plan structured interview questions the way a trained UK panel does: each question tests one '
      'pre-agreed criterion, and follow-up probes are chosen by what an answer leaves out. Use plain UK '
      'English. Probes are short, neutral and open; never leading, never two questions in one.',
  texts: [
    '<round role="${_attr(role)}">\n'
        '${[for (final (i, q) in questions.indexed) '<question n="${i + 1}" kind="${_attr(q.category)}">${q.question}</question>'].join('\n')}\n'
        '</round>',
    '''
For each question, in order, give:
- criterion: what it tests, in a few words.
- expected: the elements a full answer has, from: situation (one specific example), ownAction (what the candidate did themselves), measure (how they measured it or knew it worked), result (the outcome), learning (what they learned or would do differently), others (who else was involved). Settler, motivation, strengths and "any questions for us" questions expect none.
- probes: one or two short follow-ups for each expected element, worded for this question.''',
  ],
  schema: object({
    'questions': array(
      object({
        'criterion': string(),
        'expected': array(oneOf([for (final e in AnswerElement.values) e.name])),
        'probes': array(
          object({
            'element': oneOf([for (final e in AnswerElement.values) e.name]),
            'text': string(),
          }),
        ),
      }),
    ),
  }),
  effort: 'low',
  maxTokens: 6000,
);

/// The request [PromptedInterviewBrain.readCriteria] sends. Only the advert
/// goes: no profile.
BrainRequest criteriaRequest({required String advert, String title = ''}) => BrainRequest(
  system:
      'You read job adverts and person specifications the way a UK or Irish recruiting panel does before '
      'shortlisting. List only criteria the text states; never add your own. Keep each criterion in the '
      "document's own words, shortened. Use plain UK English.",
  texts: [
    '<advert title="${_attr(title)}">\n$advert\n</advert>',
    '''
List every essential and desirable criterion in the person specification (and any the advert states as required), one per item:
- text: the criterion, short, in the document's words.
- essential: true when the document calls it essential or required; false when desirable.
- kind: experience, skill, knowledge, value, behaviour or qualification.
- assessBy: how it is assessed when the document says (A application, I interview, T test, P presentation); [] when it does not say.
- question: one open, neutral interview question that tests it. Values: "What does … mean to you, and when have you shown it?". Experience and behaviours: "Tell us about a time…".
Also give the job title, the employer, and the framework this employer most likely scores with (nhs_values for NHS England, Scotland and Wales; hsc_ni for Health and Social Care Northern Ireland; civil_service for the UK Civil Service; hse_ie for the HSE in Ireland; private otherwise).''',
  ],
  schema: criteriaSchema,
  effort: 'low',
  maxTokens: 8000,
);

/// The request [PromptedInterviewBrain.scoreRound] sends: only the
/// transcripts and the criteria, no profile.
BrainRequest scoreRequest({
  required String role,
  required Framework framework,
  required List<Criterion> criteria,
  required List<RoundAnswer> answers,
}) {
  final scale = framework.scale;
  return BrainRequest(
    system:
        'You are a trained interview panel member scoring a practice interview. You score only what the '
        'candidate said, against criteria agreed in advance, on the panel\'s own scale. Never guess: if the '
        'transcript has no evidence for a criterion, give the "no evidence" level. Every other level must quote '
        'the candidate\'s exact words that it rests on. Feedback is about the task, never the person: no '
        'judgements of confidence or personality, no percentages.',
    texts: [
      '<scale name="${_attr(scale.name)}">\n'
          '${[for (final l in scale.levels) '<level code="${l.code}" label="${_attr(l.label)}">${l.anchor}</level>'].join('\n')}\n'
          '</scale>\n'
          '<criteria role="${_attr(role)}">\n'
          '${[for (final c in criteria) '<criterion id="${c.id}" essential="${c.essential}">${c.text}</criterion>'].join('\n')}\n'
          '</criteria>',
      '<round>\n'
          '${[for (final a in answers) '<answer question="${a.index + 1}" tests="${a.criteria.join(',')}">\n<asked>${a.question}</asked>\n<said>\n${a.answer}\n</said>\n</answer>'].join('\n')}\n'
          '</round>',
      '''
For each answer, score each criterion it tests (its "tests" ids) on the scale:
- level: a code from the scale. "${scale.noEvidence.code}" when the answer has no evidence for it, or only a bare claim.
- quote: the candidate's exact words (one sentence or part of one, copied character for character) that the level rests on; "" for "${scale.noEvidence.code}".
A claim without an example is "${scale.noEvidence.code}": "I am a good team player", "I always…" or "I would…" with no real instance of something the candidate did.
Then one strength of the answer and one fix: a concrete thing to do differently in the answer next time.
The strength and the fix never mention scores, levels, the scale or its numbers (not "move toward a 3", not "to score higher"). Say what to do, for example "Say how you knew it worked: a number, a check or feedback."''',
    ],
    schema: scoringSchema(scale, [for (final c in criteria) c.id]),
    effort: 'medium',
    maxTokens: 12000,
  );
}
