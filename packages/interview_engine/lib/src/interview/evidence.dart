/// Employer facts as the answer checker reads them, the questions a panel
/// is likely to ask ranked by evidence, and what each answer was expected
/// to show, split by who expects it (journey plan J6; honesty rules 3, 5
/// and 10).
///
/// - [EvidenceCard] is plain data: each app maps its own fact cards (Vidya's
///   dossier) to it. Only verified and user-confirmed cards ever feed a
///   question or an expectation; an inference card never does.
/// - [rankQuestions] ranks likely questions with no AI: the person
///   specification's interview criteria first, then the organisation's
///   values when a card supports them, then questions candidates reported
///   (always labelled anecdotal), then generic competency questions. Each
///   says why it is there and which criterion or card it rests on.
/// - [answerExpectations] says, for each answer, which panel, organisation
///   and manager expectations it covered, each quoting the line that did,
///   and lists the rest as not covered. With no cards it says so instead of
///   guessing ([noSourcesNote]).
library;

import '../question.dart';
import 'interview_plan.dart';
import 'interview_scoring.dart';

// ---- cards ----

/// How far a card can be trusted (honesty rule 3).
enum CardStatus {
  /// Its supporting sentence was found word for word in its source.
  verified('Verified'),

  /// The user checked it themselves.
  userConfirmed('You checked it'),

  /// Not checked: always labelled as inference, never used as fact.
  inference('Inference');

  const CardStatus(this.label);
  final String label;

  /// From the words apps store: `verified`, `user-confirmed` (or
  /// `userConfirmed`), anything else reads as inference.
  static CardStatus of(String s) => switch (s.trim().toLowerCase()) {
    'verified' => verified,
    'user-confirmed' || 'userconfirmed' || 'user_confirmed' => userConfirmed,
    _ => inference,
  };
}

/// One employer fact, as the answer checker reads it.
class EvidenceCard {
  const EvidenceCard({
    required this.id,
    required this.claim,
    this.quote = '',
    this.kind = 'other',
    this.status = CardStatus.inference,
    this.sourceTitle = '',
    this.sourceDate = '',
    this.stale = false,
  });

  final String id;

  /// The fact in one plain sentence.
  final String claim;

  /// The exact supporting sentence from the source; '' when none.
  final String quote;

  /// values, strategy, board, team, systems, staff-survey, cqc, pay,
  /// reviews-anecdotal or other (Vidya's dossier kinds).
  final String kind;
  final CardStatus status;
  final String sourceTitle;

  /// The source's own date (yyyy-MM-dd), '' when not known.
  final String sourceDate;

  /// Older than its source's cycle (honesty rule 4): shown with a flag.
  final bool stale;

  /// Verified or user-confirmed: the only cards that may be used.
  bool get usable => status != CardStatus.inference;

  /// From staff reviews or candidates' reports: never stated as fact.
  bool get anecdotal => kind == 'reviews-anecdotal';

  /// Where it came from, for a "why" line.
  String get cite => [
    sourceTitle.isNotEmpty ? sourceTitle : 'your source',
    if (sourceDate.isNotEmpty) sourceDate,
    if (stale) 'may be out of date',
  ].join(', ');
}

/// Card kinds whose facts the organisation expects candidates to know.
const organisationKinds = {'values', 'strategy', 'board'};

/// Card kinds about the team and its current work: what the manager
/// expects.
const managerKinds = {'team', 'systems'};

/// Said where there are no usable cards (honesty rule 10).
const noSourcesNote = 'No sources yet — add some in Research.';

/// Said where the only cards are inference (honesty rule 5).
const onlyInferenceNote = 'Only inference cards so far: check them in Research before they count.';

/// Said beside an organisation question when no card supports one.
const notInSourcesNote = 'Not found in your sources: add the organisation\'s values or strategy in Research.';

// ---- ranked questions ----

/// Why a predicted question is on the list, strongest evidence first.
enum EvidenceTier {
  personSpec('Person specification: assessed at interview'),
  organisation('Organisation values or plans, from your sources'),
  anecdotal('Reported by candidates (anecdotal)'),
  generic('Generic competency question');

  const EvidenceTier(this.label);
  final String label;
}

/// A question a panel is likely to ask, with why.
class PredictedQuestion {
  const PredictedQuestion({
    required this.question,
    required this.tier,
    required this.why,
    this.category = 'Behavioural',
    this.criterionId = '',
    this.cardId = '',
    this.essential = false,
  });

  final String question;
  final EvidenceTier tier;

  /// Which criterion or card it rests on, in plain words.
  final String why;
  final String category;

  /// The criterion it tests, '' for one from a card or a generic one.
  final String criterionId;

  /// The card it rests on, '' when none.
  final String cardId;
  final bool essential;

  bool get anecdotal => tier == EvidenceTier.anecdotal;

  PredictedQuestion withWording(String q) => PredictedQuestion(
    question: q,
    tier: tier,
    why: why,
    category: category,
    criterionId: criterionId,
    cardId: cardId,
    essential: essential,
  );

  /// As a question to practise: it tests its criterion when it has one.
  EngineQuestion toEngineQuestion() => EngineQuestion({
    'question': question,
    'category': category,
    'why': why,
    'lookFor': const ['One specific example', 'What you yourself did', 'What came of it'],
    if (criterionId.isNotEmpty) 'criteria': [criterionId],
    'tier': tier.name,
    if (cardId.isNotEmpty) 'card': cardId,
  });
}

/// Value-based questions keyed by the value words a card may hold. Generic
/// wording, used only when a usable card shows the organisation holds such
/// a value; never a claim about the organisation in itself.
const vbrBank = <(String, String)>[
  (
    r'compassion|caring|kindness|kind\b|care\b',
    'Tell us about a time you showed compassion to someone who was finding things hard. What did you do?',
  ),
  (
    r'respect|dignity',
    'Tell us about a time you made sure someone was treated with respect and dignity, when that was not easy.',
  ),
  (
    r'together|teamwork|collaborat|partnership',
    'Tell us about a time you worked with people outside your own team to make things better for the people '
        'you serve.',
  ),
  (
    r'improv|quality|excellen|innovat|learning',
    'Tell us about a time you spotted something that could be done better and did something about it.',
  ),
  (
    r'everyone counts|inclusi|equalit|equity|divers|fair',
    'Tell us about a time you made sure everyone was included or treated fairly.',
  ),
  (
    r'open|honest|integrity|transparen|speak up|speaking up',
    'Tell us about a time you had to be open about a mistake or raise a concern.',
  ),
];

String _words(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _clip(String s, int max) => s.length > max ? '${s.substring(0, max - 1).trimRight()}…' : s;

String _trimEnd(String s) => s.trim().replaceAll(RegExp(r'[.;:]+$'), '');

/// Generic competency questions that come last: most panels ask some form
/// of them whatever the job.
const genericQuestions = <(String, String, String)>[
  ('Why do you want this role?', 'Motivation', 'Asked in most interviews.'),
  (
    'Tell us about a time you had to manage several priorities at once. How did you decide what came first?',
    'Behavioural',
    'A common competency question: prioritising.',
  ),
  (
    'Tell us about a time something went wrong at work. What did you do, and what did you learn?',
    'Behavioural',
    'A common competency question: learning from mistakes.',
  ),
];

/// Ranks likely questions for a job's [criteria] by evidence (journey plan
/// J6): (a) criteria the person specification assesses at interview,
/// essentials first; (b) the organisation's values and plans, only from a
/// verified or user-confirmed card, each citing it; (c) questions
/// candidates reported, from anecdotal cards, labelled so; (d) generic
/// competency questions: criteria whose means of assessment is not stated
/// or is the application (panels often re-probe it), then common ones.
/// Criteria assessed only by a test are left out. At most [max].
List<PredictedQuestion> rankQuestions({
  required List<Criterion> criteria,
  List<EvidenceCard> cards = const [],
  int max = 12,
}) {
  final out = <PredictedQuestion>[];
  final seen = <String>{};
  void add(PredictedQuestion q) {
    if (seen.add(_norm(q.question))) out.add(q);
  }

  String category(Criterion c) => switch (c.kind) {
    CriterionKind.value => 'Values',
    CriterionKind.knowledge || CriterionKind.qualification => 'Technical',
    _ => 'Behavioural',
  };

  // (a) Interview criteria, as the spec marks them.
  final atInterview = [
    for (final c in criteria)
      if (c.assessBy.contains('I') || c.assessBy.contains('P')) c,
  ]..sort((a, b) => (a.essential ? 0 : 1).compareTo(b.essential ? 0 : 1));
  for (final c in atInterview) {
    add(
      PredictedQuestion(
        question: c.question.isNotEmpty ? c.question : templateQuestion(c),
        tier: EvidenceTier.personSpec,
        category: category(c),
        criterionId: c.id,
        essential: c.essential,
        why:
            'The person specification marks "${_trimEnd(c.text)}" (${c.essential ? 'essential' : 'desirable'}) '
            'for assessment at ${c.assessBy.contains('I') ? 'interview' : 'the presentation'}.',
      ),
    );
  }

  // (b) The organisation's values and plans: usable cards only.
  final usable = [
    for (final c in cards)
      if (c.usable && !c.anecdotal) c,
  ];
  for (final card in usable.where((c) => c.kind == 'values')) {
    final text = _words('${card.claim} ${card.quote}');
    final evidence = card.quote.isNotEmpty ? card.quote : card.claim;
    var matched = false;
    for (final (pattern, q) in vbrBank) {
      if (!RegExp(pattern).hasMatch(text)) continue;
      matched = true;
      add(
        PredictedQuestion(
          question: q,
          tier: EvidenceTier.organisation,
          category: 'Values',
          cardId: card.id,
          why:
              'Values-based question: your card says "${_clip(_trimEnd(evidence), 160)}" '
              '(${card.status.label.toLowerCase()}; ${card.cite}).',
        ),
      );
    }
    if (!matched) {
      add(
        PredictedQuestion(
          question:
              'The organisation\'s values include: "${_clip(_trimEnd(evidence), 160)}". Which of these matters '
              'most to you, and when have you shown it at work?',
          tier: EvidenceTier.organisation,
          category: 'Values',
          cardId: card.id,
          why: 'From your card (${card.status.label.toLowerCase()}; ${card.cite}).',
        ),
      );
    }
  }
  for (final card in usable.where((c) => c.kind == 'strategy' || c.kind == 'board').take(2)) {
    add(
      PredictedQuestion(
        question:
            'Our plans include this: "${_clip(_trimEnd(card.claim), 160)}". How would your experience help with '
            'that in this role?',
        tier: EvidenceTier.organisation,
        category: 'Motivation',
        cardId: card.id,
        why:
            'Panels often ask how you fit their plans. From your card (${card.status.label.toLowerCase()}; '
            '${card.cite}).',
      ),
    );
  }

  // (c) Questions candidates reported: anecdotal, and said so.
  for (final card in cards.where((c) => c.usable && c.anecdotal)) {
    final reported = _reportedQuestion(card);
    if (reported == null) continue;
    add(
      PredictedQuestion(
        question: reported,
        tier: EvidenceTier.anecdotal,
        cardId: card.id,
        why: 'Anecdotal: one candidate\'s report, not the employer\'s own words (${card.cite}).',
      ),
    );
  }

  // (d) Generic: criteria not marked for interview (but not test-only).
  final rest = [
    for (final c in criteria)
      if (!atInterview.contains(c) && !c.testOnly) c,
  ]..sort((a, b) => (a.essential ? 0 : 1).compareTo(b.essential ? 0 : 1));
  for (final c in rest) {
    add(
      PredictedQuestion(
        question: c.question.isNotEmpty ? c.question : templateQuestion(c),
        tier: EvidenceTier.generic,
        category: category(c),
        criterionId: c.id,
        essential: c.essential,
        why: c.assessBy.isEmpty
            ? 'The person specification lists "${_trimEnd(c.text)}" but does not say how it is assessed.'
            : 'Assessed on the application ("${_trimEnd(c.text)}"); panels often ask about it again.',
      ),
    );
  }
  for (final (q, cat, why) in genericQuestions) {
    add(PredictedQuestion(question: q, tier: EvidenceTier.generic, category: cat, why: why));
  }
  return out.take(max).toList();
}

/// The question a candidate reported on [card], or null when the card is
/// a review rather than a reported question: a sentence of its quote (or
/// claim) that ends in "?", or one that says what was asked.
String? _reportedQuestion(EvidenceCard card) {
  for (final text in [card.quote, card.claim]) {
    for (final s in text.split(RegExp(r'(?<=[.!?])\s+|\n+'))) {
      final t = s.trim();
      if (t.endsWith('?') && t.split(' ').length >= 4) return t.replaceFirst(RegExp(r'^["“]+'), '');
    }
  }
  for (final text in [card.quote, card.claim]) {
    final m = RegExp(
      r'\basked (me |us |candidates |people )?(about|to|why|how|what|whether|if)\b(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) {
      final rest = _trimEnd(m.group(3)!.trim().replaceAll(RegExp(r'["”]+$'), ''));
      if (rest.split(' ').length >= 2) return 'Reported: asked ${m.group(2)!.toLowerCase()} $rest.';
    }
  }
  return null;
}

/// The note to show for the organisation tier: null when a usable card fed
/// it, else why it is empty.
String? organisationTierNote(List<EvidenceCard> cards) {
  final org = [
    for (final c in cards)
      if (organisationKinds.contains(c.kind)) c,
  ];
  if (org.any((c) => c.usable)) return null;
  return org.isEmpty ? notInSourcesNote : onlyInferenceNote;
}

// ---- expectations ----

/// Who expects something of an answer.
enum ExpectationSource {
  panel('Panel', 'The criteria the panel agreed, and the anchor for evidence'),
  organisation('Organisation', 'Its values and plans, from your cards'),
  manager('Manager', 'The team and its current work, from your cards');

  const ExpectationSource(this.label, this.about);
  final String label;
  final String about;
}

/// One thing an answer was expected to show.
class Expectation {
  const Expectation({
    required this.source,
    required this.text,
    this.criterionId = '',
    this.cardId = '',
    this.anchor = '',
  });
  final ExpectationSource source;
  final String text;

  /// The criterion it is tied to (panel), or ''.
  final String criterionId;

  /// The card it is tied to (organisation, manager), or ''.
  final String cardId;

  /// For a panel expectation: what the evidence level's anchor needs.
  final String anchor;
}

/// Whether an answer covered an [Expectation], and the line that did.
class ExpectationHit {
  const ExpectationHit(this.expectation, {this.quote = ''});
  final Expectation expectation;

  /// The candidate's own line that covered it; '' when not covered.
  final String quote;

  bool get covered => quote.isNotEmpty;
}

/// One source's expectations for one answer, or why there are none.
class ExpectationGroup {
  const ExpectationGroup(this.source, {this.hits = const [], this.note = ''});
  final ExpectationSource source;
  final List<ExpectationHit> hits;

  /// Why there are no expectations ([noSourcesNote], [onlyInferenceNote]),
  /// or ''.
  final String note;

  List<ExpectationHit> get covered => [
    for (final h in hits)
      if (h.covered) h,
  ];
  List<ExpectationHit> get notCovered => [
    for (final h in hits)
      if (!h.covered) h,
  ];
}

/// What one answer was expected to show, by who expects it.
class AnswerExpectations {
  const AnswerExpectations({required this.question, required this.groups});
  final int question;

  /// Panel, organisation, manager: always all three, in that order.
  final List<ExpectationGroup> groups;

  ExpectationGroup of(ExpectationSource s) => groups.firstWhere((g) => g.source == s);
}

const _stop = {
  'about', 'after', 'also', 'and', 'are', 'been', 'being', 'both', 'but', 'can', 'could', 'each', 'for', //
  'from', 'had', 'has', 'have', 'into', 'its', 'more', 'most', 'much', 'our', 'over', 'own', 'should', //
  'some', 'such', 'than', 'that', 'the', 'their', 'them', 'then', 'there', 'these', 'they', 'this', //
  'those', 'through', 'very', 'was', 'were', 'what', 'when', 'where', 'which', 'while', 'who', 'will', //
  'with', 'would', 'your', 'trust', 'organisation', 'staff', 'team', 'work', 'working', 'role', 'people',
  'service', 'services', 'new', 'all', 'one', 'year', 'years',
};

Set<String> _keyWords(String s) => {
  for (final w in _norm(s).split(' '))
    if (w.length >= 4 && !_stop.contains(w)) w.length > 5 ? w.substring(0, 5) : w,
};

/// The line of [transcript] that covers [card]: the first sentence sharing
/// at least two of its key words (one when it has two or fewer), or ''.
String _cardLine(EvidenceCard card, String transcript) {
  final words = _keyWords('${card.claim} ${card.quote}');
  if (words.isEmpty) return '';
  final need = words.length <= 2 ? 1 : 2;
  for (final s in transcript.split(RegExp(r'(?<=[.!?])\s+|\n+'))) {
    if (_keyWords(s).where(words.contains).length >= need) return s.trim();
  }
  return '';
}

/// The line of [transcript] that best shows an example: the first sentence
/// with the speaker's own past action and a specific situation, else the
/// first with either. '' when there is none.
String earningLine(String transcript) {
  final sentences = [
    for (final s in transcript.split(RegExp(r'(?<=[.!?])\s+|\n+')))
      if (s.trim().split(RegExp(r'\s+')).length >= 3) s.trim(),
  ];
  for (final want in [
    {AnswerElement.ownAction, AnswerElement.situation},
    {AnswerElement.ownAction},
    {AnswerElement.result},
    {AnswerElement.measure},
    {AnswerElement.situation},
  ]) {
    for (final s in sentences) {
      if (detectElements(s).containsAll(want) && !claimWithoutExample(s, s)) return s;
    }
  }
  return '';
}

ExpectationGroup _cardGroup(
  ExpectationSource source,
  Set<String> kinds,
  List<EvidenceCard> cards,
  String transcript,
) {
  final mine = [
    for (final c in cards)
      if (kinds.contains(c.kind)) c,
  ];
  final usable = [
    for (final c in mine)
      if (c.usable) c,
  ];
  if (usable.isEmpty) return ExpectationGroup(source, note: mine.isEmpty ? noSourcesNote : onlyInferenceNote);
  return ExpectationGroup(
    source,
    hits: [
      for (final c in usable)
        ExpectationHit(
          Expectation(source: source, text: c.claim, cardId: c.id),
          quote: _cardLine(c, transcript),
        ),
    ],
  );
}

/// For each answered question of [round], which panel, organisation and
/// manager expectations it covered, each tied to its criterion or card and
/// quoting the candidate's own line; the rest are listed as not covered.
///
/// Panel: each criterion the question tests, covered when its verified
/// score (from [verified]) reaches the scale's evidence level, quoting that
/// score's quote; without an AI score, when the words on the device read as
/// a full example, quoting the earning line. Organisation (values and
/// plans) and manager (team and current work): each usable card, covered
/// when a sentence of the answer shares its key words. With no usable card
/// a group says so ([noSourcesNote], [onlyInferenceNote]) and guesses
/// nothing.
List<AnswerExpectations> answerExpectations({
  required DebriefRound round,
  required Framework framework,
  Verified? verified,
  List<EvidenceCard> cards = const [],
}) {
  final scale = framework.scale;
  final anchor = scale.levels[scale.evidencedFrom.clamp(0, scale.levels.length - 1)].anchor;
  final out = <AnswerExpectations>[];
  for (final q in round.answered) {
    final panel = <ExpectationHit>[];
    for (final id in q.criteria) {
      final c = round.criteria.where((c) => c.id == id).firstOrNull;
      if (c == null) continue;
      var quote = '';
      if (verified != null) {
        final best = [
          for (final s in verified.scores)
            if (s.question == q.index &&
                s.criterionId == id &&
                scale.coverageOf(s.level) == Coverage.evidenced)
              s,
        ].firstOrNull;
        quote = best?.quote ?? '';
      } else {
        // The same reading as the debrief's coverage on the device.
        quote = matcherCoverage(q) == Coverage.evidenced ? earningLine(q.heard) : '';
      }
      panel.add(
        ExpectationHit(
          Expectation(source: ExpectationSource.panel, text: c.text, criterionId: id, anchor: anchor),
          quote: quote,
        ),
      );
    }
    out.add(
      AnswerExpectations(
        question: q.index,
        groups: [
          ExpectationGroup(ExpectationSource.panel, hits: panel),
          _cardGroup(ExpectationSource.organisation, organisationKinds, cards, q.heard),
          _cardGroup(ExpectationSource.manager, managerKinds, cards, q.heard),
        ],
      ),
    );
  }
  return out;
}
