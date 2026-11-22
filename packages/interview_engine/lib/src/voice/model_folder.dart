/// Where the speech and vision models live.
///
/// On a desktop, Udyoga and Vidya share one per-user folder, so the models
/// (about 245 MB to download) are fetched once for both apps:
///
/// - Linux: `$XDG_DATA_HOME/pariksha/models`, or
///   `~/.local/share/pariksha/models` when XDG_DATA_HOME is not set;
/// - Windows: `%APPDATA%\pariksha\models`;
/// - macOS: `~/Library/Application Support/pariksha/models`.
///
/// Every model in it is checked against its pinned SHA-256 before it is
/// installed (see [ModelManager]), whichever app downloaded it. On Android
/// and iOS each app is sandboxed, so each keeps its own copy in its private
/// storage, as before.
///
/// [adoptModels] moves models an app downloaded into its own folder before
/// the shared folder existed, so nothing is downloaded twice.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'models.dart';

/// The folder name under the per-user data folder.
const sharedFolderName = 'pariksha';

/// The shared model folder for this user, or null where apps cannot share
/// one (Android, iOS) or the user's data folder is unknown. [environment]
/// and [os] default to this process's; tests pass their own.
Directory? sharedModelFolder({Map<String, String>? environment, String? os}) {
  final env = environment ?? Platform.environment;
  final sep = (os ?? Platform.operatingSystem) == 'windows' ? r'\' : '/';
  String? base;
  switch (os ?? Platform.operatingSystem) {
    case 'linux':
      final xdg = env['XDG_DATA_HOME'] ?? '';
      // The XDG spec says a relative path is invalid and must be ignored.
      if (xdg.startsWith('/')) {
        base = xdg;
      } else if ((env['HOME'] ?? '').isNotEmpty) {
        base = '${env['HOME']}/.local/share';
      }
    case 'windows':
      if ((env['APPDATA'] ?? '').isNotEmpty) base = env['APPDATA'];
    case 'macos':
      if ((env['HOME'] ?? '').isNotEmpty) base = '${env['HOME']}/Library/Application Support';
  }
  if (base == null) return null;
  return Directory('$base$sep$sharedFolderName${sep}models');
}

/// What [adoptModels] did.
class AdoptReport {
  const AdoptReport({this.moved = const [], this.duplicates = const [], this.skipped = const []});

  /// Model ids moved into the shared folder.
  final List<String> moved;

  /// Model ids already installed in the shared folder: the app's own copy
  /// matched the same pinned checksum and was removed.
  final List<String> duplicates;

  /// Model ids left where they were because they did not pass the check;
  /// they are downloaded again when wanted.
  final List<String> skipped;

  bool get nothing => moved.isEmpty && duplicates.isEmpty;
}

/// Moves the models installed under [from] (an app's own folder) into [to]
/// (the shared folder), so they are not downloaded again.
///
/// A model is moved only when it passed its SHA-256 check when it was
/// installed (its `.verified` marker holds the pinned checksum and its main
/// file is there); a single-file model is hashed again. A model already
/// installed in [to] is not touched, and the app's duplicate copy is
/// removed. Folders of retired models move too, so the lab can still offer
/// to delete them. A move is a rename when both folders are on one disk,
/// otherwise a copy into a staging folder that is then renamed into place.
Future<AdoptReport> adoptModels({
  required Directory from,
  required Directory to,
  List<SpeechModel> models = speechModels,
}) async {
  if (!await from.exists() || _same(from, to)) return const AdoptReport();
  final source = ModelManager(from), target = ModelManager(to);
  final moved = <String>[], duplicates = <String>[], skipped = <String>[];
  for (final m in models) {
    final dir = Directory('${from.path}/${m.id}');
    if (!await dir.exists()) continue;
    if (!await source.installed(m) || !await _rehashOk(source, m)) {
      skipped.add(m.id);
      continue;
    }
    if (await target.installed(m)) {
      await dir.delete(recursive: true);
      duplicates.add(m.id);
      continue;
    }
    await _move(dir, Directory('${to.path}/${m.id}'));
    moved.add(m.id);
  }
  for (final id in retiredModelIds) {
    final dir = Directory('${from.path}/$id');
    final dest = Directory('${to.path}/$id');
    if (await dir.exists() && !await dest.exists()) await _move(dir, dest);
  }
  return AdoptReport(moved: moved, duplicates: duplicates, skipped: skipped);
}

bool _same(Directory a, Directory b) => a.absolute.path == b.absolute.path;

/// A single file is hashed again; an unpacked archive cannot be, so its
/// marker (written only after the archive matched) stands.
Future<bool> _rehashOk(ModelManager mm, SpeechModel m) async {
  if (m.archive) return true;
  final digest = await sha256.bind(File(mm.path(m)).openRead()).first;
  return digest.toString() == m.sha256;
}

Future<void> _move(Directory dir, Directory dest) async {
  await dest.parent.create(recursive: true);
  // A half-installed folder in the way (no marker) is replaced.
  if (await dest.exists()) await dest.delete(recursive: true);
  try {
    await dir.rename(dest.path);
    return;
  } on FileSystemException {
    // Different disks: copy, then swap in.
  }
  final staging = Directory('${dest.path}.new');
  if (await staging.exists()) await staging.delete(recursive: true);
  await _copy(dir, staging);
  await staging.rename(dest.path);
  await dir.delete(recursive: true);
}

Future<void> _copy(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (e is Directory) {
      await _copy(e, Directory('${to.path}/$name'));
    } else if (e is File) {
      await e.copy('${to.path}/$name');
    }
  }
}
