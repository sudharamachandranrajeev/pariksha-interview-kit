# Changelog

## 0.3.0 (unreleased)

J6: the answer checker. The twelve honesty rules, audited and enforced; see the README table.

- A strength must quote the line that earned it (`AnswerScore.strengthQuote`, `quotedStrength`,
  `ContentNote.quote`); one fix in one sentence (`oneFix`).
- Each process template scores on its real scale (`InterviewProcess.framework`); score lines carry
  the next level's anchor.
- `rankQuestions`: likely questions in four evidence tiers, each with why; organisation questions
  cite a verified or user-confirmed `EvidenceCard`.
- `answerExpectations`: panel, organisation and manager expectations, covered or not covered; "No
  sources yet" when there are no cards.
- `improveAnswer` and `checkRewrite`: no rewrite before the candidate's attempt, none that adds a
  number, name or achievement. `wordPredictedQuestions` for AI wording under the same check.
- `TextPromptedInterviewBrain` and `replyJson` for text-only models, so local and cloud models get
  the same prompt and checks.
- Flattering self-descriptions are taken out before scoring, like other self-verdicts.

## 0.2.0 (unreleased)

J3: what Vidya's spoken interviewer needs, shared so both apps get it.

- Two apps can share the desktop model folder safely: an OS file lock per model while it downloads,
  installs or is deleted; each download writes to its own temporary file; a second app waits and
  uses the first app's checked model instead of downloading again; a delete during a download is
  refused.
- `registerUser`/`users` and `modelSharingNote`: screens say the models are shared with the other
  app and that deleting one deletes it there too.
- `scoreTwice` and `verifyRuns`: each round is scored twice with the criteria shuffled; where the
  runs disagree the lower level shows, marked "uncertain, check yourself".
- `recheckScore`: a dispute re-checks the quote and the criterion; pushback never changes a score.
- `withoutSelfVerdicts`: "I think this is great" and the like are taken out before scoring (the
  sycophancy probe). Scores made by 0.1.0 did not do this, hence the new version.
- `ScoringScale.next` for the next level's anchor.
- `testing.dart`: `ScriptedBrain` and `FakeSpokenEngines`.

## 0.1.0 (unreleased)

J2: the interviewer moves here from Udyoga, with no change in behaviour.

- Voice: Kokoro voice, Moonshine transcripts and Silero voice detection through sherpa_onnx, the
  spoken round state machine, take store, voice cache and the interview lab.
- Vision: BlazeFace on LiteRT and the camera set-up check.
- Interview logic: question plans, probes and the answer-element matcher, personas, levels and
  interruptions, process templates (NHS, Civil Service, private), criteria and role profiles,
  framework scales, verified-quote scoring, the debrief and coverage, delivery and answer metrics,
  and the offline guard.
- `EngineQuestion` keeps the JSON it was made from, so app keys travel with a question.
- `InterviewBrain` (plan a round, read criteria, follow-up, score a round) and
  `PromptedInterviewBrain`, which holds the engine's own instructions: an app only implements `ask`.
- Every `AnswerScore` records `engineVersion`.
- Shared model folder on desktop (`sharedModelFolder`) and `adoptModels`, which moves an app's own
  checked models there instead of downloading them again.
- `package:interview_engine/testing.dart`: test doubles for a voice, a listener, a take store and a
  camera.
- Tests moved from Udyoga; the network-off and privacy tests cover the moved code.

## 0.0.1

- J0 skeleton: `InterviewBrain` and `EngineQuestion` stubs, a native-library probe, network-off and privacy tests.
