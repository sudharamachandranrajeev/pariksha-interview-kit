# interview_engine

The offline mock-interview engine shared by Udyoga and Vidya. See the [repo README](../../README.md).

- No database and no brahma_core. Each app stores rounds and scores its own way.
- The AI comes in through `InterviewBrain`. Most apps extend `PromptedInterviewBrain` and implement
  one method, `ask`, over their own model client; the instructions and schemas stay in the engine,
  so every app sends the same words.
- Every score quotes the transcript; `verifyScores` drops any quote that is not there. Each
  `AnswerScore` records the `engineVersion` that made it.
- `scoreTwice` scores a round twice with the criteria in a different order each time;
  `verifyRuns` checks both and, where they disagree, shows the lower level marked "uncertain, check
  yourself" (no confidence percentages).
- `recheckScore` handles a dispute: it re-checks the quote and the criterion only, so pushback never
  changes a score.
- Sentences in which the candidate grades their own answer ("I think this is great") are taken out
  before scoring (`withoutSelfVerdicts`), so the sycophancy probe in `test/double_check_test.dart`
  scores the same answer the same with or without them.
- Speech (Kokoro, Moonshine, Silero via sherpa_onnx) and the camera set-up check (BlazeFace on
  LiteRT) run on the device. Models are downloaded only on request and checked against pinned
  SHA-256 hashes.
- `probeNative()` checks that sherpa_onnx, LiteRT and the camera plugin load.
- Video takes (opt-in, see below): `VideoTakeStore`, `RoundVideo`, `VideoRetention` and
  `seekToQuote`.
- `rankQuestions` predicts likely questions from the criteria and the app's checked fact cards
  (`EvidenceCard`), in tiers: (a) the person specification, (b) the organisation's own sources,
  (c) reported by past candidates, (d) common questions. Each says why and which tier it is from; one
  that names the organisation cites a verified or user-confirmed card.
- `answerExpectations` splits what one answer was expected to show into the panel, the
  organisation and the manager, each covered (with the line that covered it) or "not covered".
- `improveAnswer` refuses to rewrite before the candidate's own attempt, and refuses a rewrite that
  adds a number, name or achievement not in their words or story bank (`checkRewrite`).

## Interviewer personas

`RoundSettings.persona` (and `InterviewStage.persona` in a process template) picks the panel's
manner. It is saved by name; an unknown name reads as `neutral`.

| Persona (`PersonaKind`, saved as) | What it does | Follow-ups a question may get |
| --- | --- | --- |
| Friendly (`"friendly"`) | Warm thanks after each answer, short gaps | Up to 2 |
| Neutral (`"neutral"`) | A plain "thank you"; the usual panel | Up to 2 |
| Probing (`"probing"`) | Asks the follow-ups more often | Up to 2 |
| Quiet (`"quiet"`) | No reaction, long gaps | Up to 2 |
| Challenging (`"challenging"`) | Firm but professional, like a tough NHS panel or an HR investigation meeting | Up to 3 |

The ladder level (1 to 5) still sets the base number of follow-ups and the clock; level 1 never
probes.

The challenging panel:

- Quotes your own words back and tests them: `You said "we sorted it". What did you personally
  do?`, "So are you saying…?", "Wouldn't it have been better to…?", "What evidence shows that
  worked?" (`quotedChallenge`, `builtInChallengeProbes`).
- Presses once on a reply that stayed vague (the third follow-up), then moves on.
- At levels 4 and 5 it stops a long answer on the same clock as the other panels, politely:
  "Let me stop you there. In one sentence: what did you personally do?"
- Tone limits, checked on the device for every line, whoever wrote it (`groundedChallenge`):
  - never rude, sarcastic, personal or discriminatory (`professionalTone`, `challengeBannedWords`);
  - never accuses you of lying;
  - quotes only words you said (`quotesOnlyHeard`, three words or more, as in rule 2);
  - states no fact about you; its generic lines carry no number, name or achievement.
- Composure is never a score. `QuestionState.deliveries` gives the delivery ranges of the answer
  and each follow-up reply, as the other panels do.
- The AI planning prompt gets the same limits: `planRequest(persona:)` and
  `PromptedInterviewBrain.planRound(persona:)` add `personaGuidance`. The `InterviewBrain`
  interface is unchanged.

## Video takes

Rule 4 used to say video frames are never stored. It now reads: **video frames are not stored,
unless the user opts in to a video take for that session.** A video take is:

- **Opt-in per session.** No video is recorded unless the app passes a `RoundVideo` to
  `SpokenRound(video: ...)`. Apps keep the switch off by default and never remember it, and show a
  camera indicator while `RoundVideo.recording` is true.
- **On that device only.** `VideoTakeStore` keeps each take in a folder the app gives it, inside its
  private storage: the camera's clip (picture only; the controller is opened without audio), a WAV
  of the same answer from the round's microphone stream (the one Moonshine hears, so the microphone
  is opened once), and a small JSON file with the transcript lines and their times. The JSON holds
  file names, never full paths. Apps keep the folder out of sync and out of backups (on Android,
  `dataExtractionRules` excludes it from cloud backup and device transfer).
- **Never sent to an AI.** Only the transcript goes to `InterviewBrain`; a test checks that no
  video path, file name or folder appears in a `BrainRequest` or in what the `AnswerSink` saves.
- **Deleted after 14 days by default.** `VideoRetention` purges takes older than the user's setting
  (1 to 90 days) at start and once a day; `VideoTakeStore.deleteAll()` is the delete-all button.
- **Not analysed.** Nothing reads the recorded video. No emotion, eye-contact or identity analysis;
  delivery cues stay informational only.

`seekToQuote(takes, quote)` finds a debrief quote in the takes' transcript lines and gives the
moment in the video to jump to (half a second before it). The picture and the WAV are paired with
`VideoTake.audioLead`: audio position = video position + lead.

Recording uses the `camera` plugin (`camera_desktop` on Linux, Windows and macOS). On the desktop
the set-up frames keep coming while it records. On Android the engine asks for frames while
recording; if the phone cannot do both, recording wins and `FaceCamera.cuesPaused` is true until it
stops. On Linux, recording needs a GStreamer H.264 encoder (`x264enc` from plugins-ugly,
`openh264enc`, or a VA-API one).

## Where the models live

| Platform | Folder |
| --- | --- |
| Linux | `$XDG_DATA_HOME/pariksha/models`, else `~/.local/share/pariksha/models` |
| Windows | `%APPDATA%\pariksha\models` |
| macOS | `~/Library/Application Support/pariksha/models` |
| Android, iOS | The app's own storage (each app downloads its own copy) |

`sharedModelFolder()` gives the desktop folder, or null on a phone. On first run an app calls
`adoptModels(from: <its old folder>, to: <shared folder>)`: models that passed their checksum when
they were installed move across (single files are hashed again), so nothing is downloaded twice.
A model the other app already installed is kept and the duplicate removed. Anything that fails the
check stays where it was and is downloaded again when wanted.

**Two apps at once.** Each model has a lock file in `<folder>/.locks/`, held with an operating
system file lock while it downloads, installs or is deleted. If Udyoga and Vidya ask for the same
model together, one downloads it and the other waits, finds it installed and checked, and does not
download it again. Each download writes to its own temporary file (`<id>.<pid>-<random>.part`), so
two downloads never write to one file. A delete never waits: while a download of that model is
running, the delete is refused with a message saying so.

**Deleting removes it for both apps.** Apps call `registerUser('udyoga')` or
`registerUser('vidya')` on their model manager, and `users()` lists who has used the folder.
`modelSharingNote(app: ..., shared: ..., users: ...)` gives the sentence to show above the models
list and in the delete confirmation, for example "These models are shared with Udyoga on this
computer: one copy in one folder. Deleting one here deletes it for Udyoga too."

## Testing an app that uses it

`package:interview_engine/testing.dart` has test doubles (`FakeVoice`, `FakeListener`,
`MemoryTakes`, `ListSink`, `FakeCoach`, `FakeCamera`, `FakeSpokenEngines`, `ScriptedBrain`,
`spokenAnswer`, `frameMeasure`), so a widget test can run a spoken round and score it with no
microphone, camera, model or AI.

## The honesty rules: where each is enforced

The answer checker (journey plan step J6) applies twelve rules in this engine, so Udyoga and Vidya
check answers the same way. Every rule has a test named after it in
`test/honesty_rules_test.dart`. "Before J6" means the rule was already enforced; "J6" means the gap
was found in the audit and closed then.

| Rule | Where it is enforced | Test | When |
| --- | --- | --- | --- |
| 1. Criteria fixed and shown before the answer | `EngineQuestion` why and look-for, `RoundQuestion.tests`; `verifyScores` drops a score for a criterion not asked | `rule01_criteria_fixed` | Before J6 |
| 2. Every score quotes the transcript, else N/O | `verifyScores`, `quoteInTranscript` | `rule02_quote_checked` | Before J6 |
| 3. Cards carry claim, source, date, quote, status | `EvidenceCard`; only `usable` (verified or user-confirmed) cards feed questions and expectations, each with `cite` | `rule03_cards_are_sourced` | J6 (Vidya's dossier checked quotes before J6) |
| 4. Stale cards flagged | `EvidenceCard.stale`, shown in every `cite` and question reason | `rule04_stale_flagged` | J6 |
| 5. Inference labelled | `onlyInferenceNote`; inference cards never feed a question | `rule05_inference_labelled` | J6 |
| 6. Pushback alone never changes a score | `recheckScore` re-checks the quote and criterion only; `withoutSelfVerdicts` | `rule06_pushback_alone` | Before J6 in Vidya; J6 in Udyoga |
| 7. No model answer before the user's attempt; rewrites never invent | `improveAnswer`, `hasOwnAttempt`, `checkRewrite`, `inventedTokens`; `wordPredictedQuestions` keeps the original wording when a rewording invents | `rule07_no_model_answer_first` | J6 |
| 8. No percentages; scored twice; "uncertain" when runs disagree | `scoreTwice`, `verifyRuns` | `rule08_scored_twice` | Before J6 in Vidya; J6 in Udyoga |
| 9. One strength quoting its line, and one fix | `AnswerScore.strengthQuote` checked by `verifyScores`; `quotedStrength` on the device; `oneFix`; `ContentNote.quote` | `rule09_one_strength_one_fix` | J6 |
| 10. "Not found in your sources" | `noSourcesNote`, `notInSourcesNote`, `organisationTierNote`; empty expectation groups say so | `rule10_not_found` | J6 (Vidya's dossier search before J6) |
| 11. The panel's real scale, with this level's and the next level's anchor | `InterviewProcess.framework` per template (`frameworkForProcess`); `Debrief.scoreLines` gives `next` | `rule11_real_scales` | J6 (scales before J6) |
| 12. Same rules on local and cloud models | One prompt and schema for every brain (`PromptedInterviewBrain`, `TextPromptedInterviewBrain`, `replyJson`); every reply goes through the same checks | `rule12_same_rules_everywhere` | J6 |

The group "the challenging panel keeps the twelve rules" in the same file tests the challenging
persona against them: `rule01_criteria_fixed (challenging)` (it probes only the agreed elements),
`rule02_quote_checked (challenging)` (every quote is a span of the transcript), `rule03_cards_are_sourced
(challenging)` (no card or outside claim in a challenge), `rule07_no_model_answer_first (challenging)` (no
invented number, name or achievement), `rule12_same_rules_everywhere (challenging)` (AI-written probes
get the same checks; one prompt for every model), plus the tone list and the three-follow-up cap.

The same file has sycophancy probes (praise appended to an answer, "I think that deserves a 4",
flattering self-description), the rewrite-invention check, and question ranking with and without
cards.

