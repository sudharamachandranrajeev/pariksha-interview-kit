/// "Improve my answer", held to honesty rule 7: no model answer before the
/// candidate's own attempt, and a rewrite keeps the candidate's own story
/// and facts.
///
/// - [hasOwnAttempt] gates every rewrite: with no attempt of their own,
///   nothing is written for them.
/// - [inventedTokens] diffs a rewrite against what the candidate said and
///   their story bank, token by token: any number, capitalised name or
///   achievement word in the rewrite that is not in them is an invention.
/// - [checkRewrite] refuses a rewrite with any invention, and says what it
///   added, so nothing made up is ever shown as theirs.
library;

import 'interview_scoring.dart' show candidateWords, withoutSelfVerdicts;

/// The fewest words of their own a candidate must have said before a
/// rewrite is offered.
const minAttemptWords = 8;

/// Said when "improve my answer" is asked for before an attempt.
const noAttemptNote =
    'Answer it yourself first. A rewrite only works from your own words, so there is nothing to improve yet.';

/// True when [answer] holds an attempt of the candidate's own: at least
/// [minAttemptWords] words once interviewer lines and self-grading
/// sentences are taken out.
bool hasOwnAttempt(String answer) {
  final own = withoutSelfVerdicts(candidateWords(answer)).trim();
  return own.isNotEmpty && own.split(RegExp(r'\s+')).length >= minAttemptWords;
}

const _numberWords = {
  'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', //
  'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14', 'fifteen': '15',
  'sixteen': '16', 'seventeen': '17', 'eighteen': '18', 'nineteen': '19', 'twenty': '20', 'thirty': '30',
  'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70', 'eighty': '80', 'ninety': '90',
  'hundred': '100', 'thousand': '1000', 'million': '1000000', 'dozen': '12', 'half': '0.5',
};

/// The numbers in [text], normalised: "1,200" and "£1200" read as 1200,
/// "40%" as 40, number words ("three") as digits. "one" is left out: it is
/// too often not a number ("no one", "one of").
Set<String> numbersIn(String text) {
  final out = <String>{};
  final t = text.toLowerCase().replaceAllMapped(RegExp(r'(\d),(\d{3})'), (m) => '${m[1]}${m[2]}');
  for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(t)) {
    var n = m[0]!;
    if (n.contains('.')) n = n.replaceFirst(RegExp(r'\.?0+$'), '');
    out.add(n);
  }
  for (final w in RegExp(r'[a-z]+').allMatches(t)) {
    if (_numberWords[w[0]] case final n?) out.add(n);
  }
  return out;
}

// Words that can open a sentence capitalised without being names.
const _commonStarters = {
  'a',
  'about',
  'after',
  'afterwards',
  'all',
  'also',
  'although',
  'an',
  'and',
  'as',
  'at',
  'because',
  'before',
  'both', 'but', 'by', 'during', 'each', 'eventually', 'every', 'finally', 'first', 'for', 'from', 'having',
  'he', 'her', 'his', 'how', 'however', 'i', 'if', 'in', 'initially', 'it', 'its', 'last', 'later', 'looking',
  'my',
  'next',
  'no',
  'not',
  'now',
  'of',
  'on',
  'once',
  'our',
  'over',
  'overall',
  'she',
  'since',
  'so',
  'that',
  'the', 'their', 'then', 'there', 'these', 'they', 'this', 'those', 'to', 'together', 'until', 'we', 'what',
  'when', 'where', 'which', 'while', 'who', 'why', 'with', 'within', 'without', 'working', 'yes', 'you',
  'result', 'situation', 'task', 'action', 'outcome', 'learning', 'second', 'third', 'one', 'some', 'most',
  'many', 'everyone', 'nobody', 'someone', 'here', 'following', 'today', 'recently',
  // Verbs and modals a question or a spoken answer opens with.
  'can', 'could', 'would', 'should', 'will', 'did', 'do', 'does', 'is', 'are', 'was', 'were', 'have', 'has',
  'had', 'may', 'might', 'must', 'please', 'tell', 'describe', 'give', 'walk', 'talk', 'think', 'let',
  'imagine', 'say', 'explain', 'share', 'thinking', 'being', 'given', 'using', 'thanks',
  'early', 'any', 'just', 'again', 'still', 'even', 'only', 'instead', 'luckily', 'sadly',
  'unfortunately', 'fortunately', 'meanwhile', 'otherwise', 'besides', 'basically', 'actually', 'really',
  'well', 'okay', 'ok', 'right', 'sure', 'yeah', 'whenever', 'whatever', 'whoever',
};

/// The capitalised names in [text], lower-cased: words that start with a
/// capital mid-sentence, acronyms anywhere ("EPR"), and a sentence's first
/// word when it is not a common opener. "I" and its forms are not names.
Set<String> namesIn(String text) {
  final out = <String>{};
  for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+|\n+'))) {
    final words = sentence.trim().split(RegExp(r'\s+'));
    for (final (i, raw) in words.indexed) {
      final w = raw
          .replaceAll(RegExp(r"^[^A-Za-z0-9]+|[^A-Za-z0-9]+$"), '')
          .replaceAll(RegExp(r"['’]s$"), '');
      if (w.isEmpty || !RegExp(r'^[A-Z]').hasMatch(w)) continue;
      if (RegExp(r"^I(['’](m|ve|d|ll))?$").hasMatch(w)) continue;
      final acronym = w.length >= 2 && w == w.toUpperCase() && RegExp(r'[A-Z]').hasMatch(w);
      if (i == 0 && !acronym && _commonStarters.contains(w.toLowerCase())) continue;
      out.add(w.toLowerCase());
    }
  }
  return out;
}

// Achievements a rewrite must never add: awards, promotions, praise.
final _achievement = RegExp(
  r'\b(award(ed|s)?|won|win|winning|prizes?|promot(ed|ion)|nominat(ed|ion)|commend(ed|ation)|'
  r'recogni[sz](ed|ion)|certifi(ed|cation)|accredit(ed|ation)|praised|thanked|bonus|record-breaking|'
  r'shortlisted|fellowship|distinction)\b',
);

/// The achievement words in [text], lower-cased.
Set<String> achievementsIn(String text) => {
  for (final m in _achievement.allMatches(text.toLowerCase())) m[0]!,
};

/// Everything a rewrite of [answer] added that is not in [answer] or the
/// candidate's [storyBank]: numbers, capitalised names and achievement
/// words, each as it reads in the rewrite. Names are compared without case,
/// so a transcript in lower case still counts.
List<String> inventedTokens(String rewrite, {required String answer, List<String> storyBank = const []}) {
  final source = [candidateWords(answer), ...storyBank].join('\n');
  final words = {for (final w in RegExp(r"[a-z0-9]+").allMatches(source.toLowerCase())) w[0]!};
  final nums = numbersIn(source);
  final achievements = achievementsIn(source);
  return [
    for (final n in numbersIn(rewrite))
      if (!nums.contains(n)) n,
    for (final n in namesIn(rewrite))
      if (!n.split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty).every(words.contains)) n,
    for (final a in achievementsIn(rewrite))
      if (!achievements.contains(a) && !words.contains(a)) a,
  ];
}

/// What checking a rewrite found.
class RewriteCheck {
  const RewriteCheck({required this.text, this.invented = const [], this.refused = false, this.message = ''});

  /// The rewrite to show, '' when refused.
  final String text;

  /// What it added that the candidate never said.
  final List<String> invented;
  final bool refused;

  /// Why it was refused, in plain words; '' when it stands.
  final String message;

  bool get ok => !refused;
}

/// Checks [rewrite] of the candidate's [answer] (honesty rule 7): refused
/// when the candidate made no attempt of their own, when the rewrite is
/// empty, or when it adds any number, name or achievement that is not in
/// [answer] or [storyBank]. A refused rewrite is never shown.
RewriteCheck checkRewrite(String rewrite, {required String answer, List<String> storyBank = const []}) {
  if (!hasOwnAttempt(answer)) return const RewriteCheck(text: '', refused: true, message: noAttemptNote);
  final r = rewrite.trim();
  if (r.isEmpty) {
    return const RewriteCheck(text: '', refused: true, message: 'The AI gave no rewrite. Try again.');
  }
  final invented = inventedTokens(r, answer: answer, storyBank: storyBank);
  if (invented.isEmpty) return RewriteCheck(text: r);
  return RewriteCheck(
    text: '',
    invented: invented,
    refused: true,
    message:
        'The rewrite was not shown: it added things you never said (${invented.join(', ')}). A rewrite may only '
        'use your own story. If they are true, add them to your story bank and ask again.',
  );
}
