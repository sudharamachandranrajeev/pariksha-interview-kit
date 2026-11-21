/// Offline mock-interview engine shared by Udyoga and Vidya.
///
/// No database, no brahma_core, no network at import or start-up. The AI
/// comes in through [InterviewBrain].
library;

export 'src/brain.dart';
export 'src/native_probe.dart';
export 'src/question.dart';
