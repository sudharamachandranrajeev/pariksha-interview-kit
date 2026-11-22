/// Offline mock-interview engine shared by Udyoga and Vidya.
///
/// No database, no brahma_core, no network at import or start-up. The AI
/// comes in through [InterviewBrain]; models are downloaded only when the
/// user asks, and checked against pinned SHA-256 hashes.
library;

export 'src/brain.dart';
export 'src/interview/answer_metrics.dart';
export 'src/interview/delivery.dart';
export 'src/interview/interview_plan.dart';
export 'src/interview/interview_process.dart';
export 'src/interview/interview_scoring.dart';
export 'src/interview/offline_guard.dart';
export 'src/interview/process_summary.dart';
export 'src/native_probe.dart';
export 'src/question.dart';
export 'src/version.dart';
export 'src/vision/blazeface.dart';
export 'src/vision/camera_coach.dart';
export 'src/vision/face_camera.dart';
export 'src/vision/setup_check.dart';
export 'src/voice/lab.dart';
export 'src/voice/lexicon.dart';
export 'src/voice/model_folder.dart';
export 'src/voice/models.dart';
export 'src/voice/native_engines.dart';
export 'src/voice/round.dart';
export 'src/voice/round_engines.dart';
export 'src/voice/spoken_engines.dart';
export 'src/voice/voice_cache.dart';
export 'src/voice/worker.dart';
