# interview_engine

The offline mock-interview engine shared by Udyoga and Vidya. See the [repo README](../../README.md).

- No database and no brahma_core.
- The AI comes in through `InterviewBrain`; each app writes a small adapter.
- `probeNative()` checks that sherpa_onnx, LiteRT and the camera plugin load.

Status: J0 skeleton. The voice, vision, plan and scoring code moves here from Udyoga in J2.
