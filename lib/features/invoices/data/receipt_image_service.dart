import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class CaptureRecovery {
  const CaptureRecovery({this.path, this.error});
  final String? path;
  final String? error;
  bool get hasData => path != null || error != null;
}

class ReceiptImageService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> pick(ImageSource source) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('A captura de talões requer Android ou iOS.');
    }
    final image = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      // Evitar reduzir a resolução: o texto pequeno precisa de detalhe.
      requestFullMetadata: false,
    );
    return image?.path;
  }

  /// Chamado no arranque, mesmo que o Android tenha recriado a Activity.
  Future<CaptureRecovery> recover() async {
    if (!Platform.isAndroid) return const CaptureRecovery();
    try {
      final result = await _picker.retrieveLostData();
      if (result.isEmpty) return const CaptureRecovery();
      final files = result.files;
      if (files != null && files.isNotEmpty) {
        return CaptureRecovery(path: files.first.path);
      }
      return const CaptureRecovery(error: 'Não foi possível recuperar a fotografia. Tenta novamente.');
    } on PlatformException {
      return const CaptureRecovery(error: 'A recuperação da câmara falhou. Podes tirar outra fotografia.');
    } on MissingPluginException {
      return const CaptureRecovery(error: 'O plugin da câmara não está disponível. Recompila a aplicação após configurar os plugins nativos.');
    }
  }

  /// Copiar só após confirmar o formulário. Devolve um caminho portátil relativo.
  Future<String> keep(String sourcePath) async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/invoices');
    await folder.create(recursive: true);
    final suffix = sourcePath.split('.').last.toLowerCase();
    final extension = RegExp(r'^(jpg|jpeg|png|heic|heif|webp)$').hasMatch(suffix)
        ? '.$suffix' : '.image';
    final relative = 'invoices/${const Uuid().v4()}$extension';
    final destination = File('${root.path}/$relative');
    try {
      await File(sourcePath).copy(destination.path);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    return relative;
  }

  /// Apenas ficheiros criados por este serviço, sem aceitar caminhos arbitrários.
  Future<void> removeOwned(String relativePath) async {
    if (!RegExp(r'^invoices/[a-zA-Z0-9-]+\.(jpg|jpeg|png|heic|heif|webp|image)$')
        .hasMatch(relativePath)) {
      throw ArgumentError('Caminho de fotografia local inválido.');
    }
    final root = await getApplicationDocumentsDirectory();
    final file = File('${root.path}/$relativePath');
    if (await file.exists()) await file.delete();
  }
}
