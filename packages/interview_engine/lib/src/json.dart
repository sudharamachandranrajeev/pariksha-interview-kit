/// Lenient readers for JSON from the AI and from an app's saved data: a
/// missing or wrongly typed field reads as empty, never as a crash.
///
/// A minimal copy of Udyoga's readers (lib/domain/json.dart there), kept
/// private to the package so it never clashes with an app's own helpers.
library;

typedef Json = Map<String, Object?>;

String str(Object? v) => switch (v) {
  String s => s.trim(),
  num n => '$n',
  _ => '',
};

int? intOf(Object? v) => switch (v) {
  num n when n.isFinite => n.round(),
  String s => num.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''))?.round(),
  _ => null,
};

Json obj(Object? v) => v is Map ? v.cast<String, Object?>() : const {};

List<Json> objs(Object? v) => v is List ? [for (final e in v) obj(e)] : const [];

List<String> strs(Object? v) =>
    v is List ? [for (final e in v) str(e)].where((s) => s.isNotEmpty).toList() : const [];
