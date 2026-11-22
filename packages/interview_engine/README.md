# interview_engine

The offline mock-interview engine shared by Udyoga and Vidya. See the [repo README](../../README.md).

- No database and no brahma_core. Each app stores rounds and scores its own way.
- The AI comes in through `InterviewBrain`. Most apps extend `PromptedInterviewBrain` and implement
  one method, `ask`, over their own model client; the instructions and schemas stay in the engine,
  so every app sends the same words.
- Every score quotes the transcript; `verifyScores` drops any quote that is not there. Each
  `AnswerScore` records the `engineVersion` that made it.
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

## Testing an app that uses it

`package:interview_engine/testing.dart` has test doubles (`FakeVoice`, `FakeListener`,
`MemoryTakes`, `ListSink`, `FakeCoach`, `FakeCamera`, `spokenAnswer`, `frameMeasure`), so a widget
test can run a spoken round with no microphone, camera or model.
