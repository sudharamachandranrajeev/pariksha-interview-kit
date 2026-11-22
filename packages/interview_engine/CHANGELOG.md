# Changelog

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
