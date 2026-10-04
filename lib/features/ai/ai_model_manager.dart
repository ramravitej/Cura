import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';
import 'model_download.dart';

/// Subdirectory of application support the model files live in.
const kModelsDirectory = 'models';

/// Manages the on-device model file (and optional Vision mmproj file), which
/// llama.cpp loads directly.
class AiModelManager {
  static const _activeKey = 'cura_active_ai_model';
  static const _thinkKey = 'cura_think_harder';

  /// The user's "Think harder" preference, for models with `AiModel.canThink`.
  /// Off by default, since reasoning is slower.
  Future<bool> thinkHarder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_thinkKey) ?? false;
  }

  /// Persists the "Think harder" preference. Takes effect on the next question
  /// (the service reads it fresh each time), so no model reload is needed.
  Future<void> setThinkHarder(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_thinkKey, value);
  }

  /// Whether [model]'s file (and its vision mmproj if required) is fully present on disk.
  Future<bool> isInstalled(AiModel model) async {
    final file = await _modelFile(model);
    if (!await file.exists()) return false;
    if (model.supportsVision) {
      final mmproj = await _mmprojFile(model);
      if (mmproj == null || !await mmproj.exists()) return false;
      await _writeMmprojPointer(file, mmproj);
    }
    return true;
  }

  /// Absolute path to [model]'s file on disk (whether or not it exists yet).
  Future<String> modelPath(AiModel model) async {
    final file = await _modelFile(model);
    if (model.supportsVision) {
      final mmproj = await _mmprojFile(model);
      if (mmproj != null && await mmproj.exists()) {
        await _writeMmprojPointer(file, mmproj);
      }
    }
    return file.path;
  }

  /// The downloaded model to use, if any: prefers the last-selected one, else
  /// any catalog model whose file is present. Null if nothing is downloaded.
  Future<AiModel?> installedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final preferred = aiModelById(prefs.getString(_activeKey));
    if (preferred != null && await isInstalled(preferred)) return preferred;
    for (final m in kAiModelCatalog) {
      if (await isInstalled(m)) return m;
    }
    return null;
  }

  /// Switches the active selection to [model] (must already be downloaded).
  Future<void> activate(AiModel model) async {
    if (!await isInstalled(model)) {
      throw const ModelDownloadException('Model is not downloaded yet.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, model.id);
  }

  /// Queues [model] (or its missing vision mmproj companion). Returns once the
  /// transfer is accepted, not finished, or false if all files were already here.
  Future<bool> download(AiModel model, ModelDownloader downloader) async {
    final dest = await _modelFile(model);
    await dest.parent.create(recursive: true);

    if (!await dest.exists()) {
      await downloader.start(
        url: model.url,
        fileName: model.fileName,
        directory: kModelsDirectory,
        displayName: model.displayName,
        kind: kLlmDownload,
      );
      return true;
    }

    if (model.supportsVision) {
      final mmproj = await _mmprojFile(model);
      if (mmproj != null && !await mmproj.exists()) {
        await downloader.start(
          url: model.mmprojUrl!,
          fileName: model.mmprojFileName!,
          directory: kModelsDirectory,
          displayName: '${model.displayName} (Vision)',
          kind: kLlmDownload,
        );
        return true;
      }
      if (mmproj != null) {
        await _writeMmprojPointer(dest, mmproj);
      }
    }

    await activate(model);
    return false;
  }

  /// Removes the downloaded model (and any vision mmproj) from the device.
  Future<void> delete(AiModel model) async {
    final file = await _modelFile(model);
    if (await file.exists()) await file.delete();
    final ptr = File('${file.path}.mmproj_path');
    if (await ptr.exists()) await ptr.delete();
    final mmproj = await _mmprojFile(model);
    if (mmproj != null && await mmproj.exists()) {
      await mmproj.delete();
    }
  }

  /// Removes every downloaded model from the device and clears the active
  /// selection. Deletes the whole models directory so orphaned files (e.g. a
  /// model dropped from the catalog, or leftover .part temp files) go too.
  Future<void> deleteAll() async {
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(dir.path, kModelsDirectory));
    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }

  Future<File> _modelFile(AiModel model) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, kModelsDirectory, model.fileName));
  }

  Future<File?> _mmprojFile(AiModel model) async {
    if (!model.supportsVision || model.mmprojFileName == null) return null;
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, kModelsDirectory, model.mmprojFileName!));
  }

  Future<void> _writeMmprojPointer(File modelFile, File mmprojFile) async {
    try {
      final ptr = File('${modelFile.path}.mmproj_path');
      await ptr.writeAsString(mmprojFile.path, flush: true);
    } catch (_) {}
  }
}
