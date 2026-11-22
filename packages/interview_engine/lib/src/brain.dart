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

import 'dart:convert';

import 'interview/evidence.dart';
import 'interview/interview_plan.dart';
import 'interview/interview_scoring.dart';
import 'interview/rewrite_check.dart';
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

  /// Rewrites the candidate's own [answer] to [question] so it shows
  /// [criterion] better and applies [fix], using only what is in the answer
  /// and the [storyBank]. Returns the rewrite as text. Never call it before
  /// the candidate's own attempt: use [improveAnswer], which gates it and
  /// checks the result for inventions (honesty rule 7).
  Future<String> rewriteAnswer({
    required String question,
    required String criterion,
    required String fix,
    required String answer,
    List<String> storyBank = const [],
  });

  /// Words each of [questions] as a panel would ask it, in the same order.
  /// May return fewer (the rest keep their wording). Every rewording is
  /// checked by [wordPredictedQuestions]: one that adds a number, name or
  /// claim not in the original is not used.
  Future<List<String>> wordQuestions({required String role, required List<String> questions});
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

  @override
  Future<String> rewriteAnswer({
    required String question,
    required String criterion,
    required String fix,
    required String answer,
    List<String> storyBank = const [],
  }) async {
    final data = await ask(
      rewriteRequest(
        question: question,
        criterion: criterion,
        fix: fix,
        answer: answer,
        storyBank: storyBank,
      ),
    );
    return str(data['answer']);
  }

  @override
  Future<List<String>> wordQuestions({required String role, required List<String> questions}) async {
    if (questions.isEmpty) return const [];
    final data = await ask(wordingRequest(role: role, questions: questions));
    return strs(data['questions']);
  }
}

/// The JSON object in a model's text reply, even with words or a code
/// fence around it: for apps whose AI connection returns text (a local
/// Ollama server as much as a cloud model), so every model's reply goes
/// through the same checks (honesty rule 12). Throws a [FormatException]
/// in plain words when there is none.
Json replyJson(String reply) {
  final start = reply.indexOf('{'), end = reply.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      if (jsonDecode(reply.substring(start, end + 1)) case final Map m) return m.cast<String, Object?>();
    } on FormatException {
      // Said below.
    }
  }
  throw const FormatException(
    'The AI did not reply in the form asked for, so nothing was scored. Try again, or try another AI.',
  );
}

/// The system prompt for a text-only AI connection: the request's own,
/// with the reply's JSON schema spelled out.
String textInstructions(BrainRequest r) =>
    '${r.system}\n\nReply with one JSON object only, with no other text before or after it. It must match '
    'this JSON schema exactly (every property present):\n${jsonEncode(r.schema)}';

/// A [PromptedInterviewBrain] over an AI connection that takes text and
/// returns text (Vidya's Ask AI, a local Ollama server): the schema goes in
/// the prompt ([textInstructions]) and the JSON is read back out of the
/// reply ([replyJson]). Everything after that is the same as for any other
/// model: the same parsing, the same quote checks.
abstract class TextPromptedInterviewBrain extends PromptedInterviewBrain {
  const TextPromptedInterviewBrain();

  /// Sends [system] and [text] to the model and returns its reply.
  Future<String> send(String system, String text);

  @override
  Future<Json> ask(BrainRequest request) async =>
      replyJson(await send(textInstructions(request), request.texts.join('\n\n')));
}

/// Improves the candidate's own [answer] through [brain], held to honesty
/// rule 7: nothing is asked of the AI until the candidate has made an
/// attempt of their own ([hasOwnAttempt]), and the rewrite is refused when
/// it adds any number, name or achievement that is not in the answer or
/// the [storyBank] ([checkRewrite]).
Future<RewriteCheck> improveAnswer({
  required InterviewBrain brain,
  required String question,
  required String answer,
  String criterion = '',
  String fix = '',
  List<String> storyBank = const [],
}) async {
  if (!hasOwnAttempt(answer)) return const RewriteCheck(text: '', refused: true, message: noAttemptNote);
  final own = withoutSelfVerdicts(candidateWords(answer));
  final rewrite = await brain.rewriteAnswer(
    question: question,
    criterion: criterion,
    fix: fix,
    answer: own,
    storyBank: storyBank,
  );
  return checkRewrite(rewrite, answer: own, storyBank: storyBank);
}

/// [predicted] reworded by [brain] where the rewording adds nothing: a
/// rewording with a number, name or achievement word that is not in the
/// question, its reason or its card's words keeps the original wording.
/// The tier, reason, criterion and card never change. If the AI fails, the
/// questions come back as they were.
Future<List<PredictedQuestion>> wordPredictedQuestions({
  required InterviewBrain brain,
  required String role,
  required List<PredictedQuestion> predicted,
}) async {
  List<String> worded;
  try {
    worded = await brain.wordQuestions(role: role, questions: [for (final p in predicted) p.question]);
  } on Object {
    return predicted;
  }
  return [
    for (final (i, p) in predicted.indexed)
      if (i < worded.length &&
          worded[i].trim().isNotEmpty &&
          inventedTokens(worded[i], answer: '${p.question}\n${p.why}\n$role').isEmpty)
        p.withWording(worded[i].trim())
      else
        p,
  ];
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
Then exactly one strength of the answer, with strengthQuote: the candidate's exact words that earned it (copied character for character; a strength you cannot quote is not a strength), and exactly one fix: one concrete thing to do differently in the answer next time, in one sentence.
The strength and the fix never mention scores, levels, the scale or its numbers (not "move toward a 3", not "to score higher"). Say what to do, for example "Say how you knew it worked: a number, a check or feedback."''',
    ],
    schema: scoringSchema(scale, [for (final c in criteria) c.id]),
    effort: 'medium',
    maxTokens: 12000,
  );
}

/// The request [PromptedInterviewBrain.rewriteAnswer] sends: the question,
/// what it tests, the fix, the candidate's own words and story bank. No
/// profile.
BrainRequest rewriteRequest({
  required String question,
  required String criterion,
  required String fix,
  required String answer,
  List<String> storyBank = const [],
}) => BrainRequest(
  system:
      'You help a candidate improve their own interview answer. You keep their story and their facts: every '
      'event, number, name, place, date, result and achievement must already be in their answer or their story '
      'bank. Never add a number, a name, a result or an achievement they did not give, not even as an example. '
      'Where something is missing, write [add: what is missing] for them to fill in. Plain UK English, first '
      'person, spoken length (under 250 words).',
  texts: [
    '<question>$question</question>\n<tests>${criterion.isEmpty ? 'not stated' : criterion}</tests>\n'
        '<fix>${fix.isEmpty ? 'none given' : fix}</fix>',
    '<answer>\n$answer\n</answer>',
    '<story_bank>\n${storyBank.isEmpty ? '(empty)' : storyBank.map((s) => '<story>$s</story>').join('\n')}\n</story_bank>',
    'Rewrite the answer so it is clearer and applies the fix, using only what is above. answer: the rewrite.',
  ],
  schema: object({'answer': string('The rewritten answer, using only the candidate\'s own facts')}),
  effort: 'low',
  maxTokens: 2000,
);

/// The request [PromptedInterviewBrain.wordQuestions] sends: only the
/// questions and the role.
BrainRequest wordingRequest({required String role, required List<String> questions}) => BrainRequest(
  system:
      'You word interview questions the way a UK panel asks them: open, neutral, one question at a time. Keep '
      'each question\'s meaning. Never add a fact, a number, a name, a value or a plan that the question does '
      'not already hold.',
  texts: [
    '<role>${_attr(role)}</role>\n${[for (final (i, q) in questions.indexed) '<q n="${i + 1}">$q</q>'].join('\n')}',
    'questions: each question reworded, in the same order, the same count.',
  ],
  schema: object({'questions': array(string())}),
  effort: 'low',
  maxTokens: 3000,
);
