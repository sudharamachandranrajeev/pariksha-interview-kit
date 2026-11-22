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
