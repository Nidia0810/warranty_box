import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/receipt_reading.dart';
import 'receipt_parser.dart';

class ReceiptOcrService {
  ReceiptOcrService();

  TextRecognizer? _recognizer;
  Future<ReceiptReading>? _pending;
  Future<void>? _closing;

  /// O ecrã reutiliza o motor; leituras concorrentes são rejeitadas.
  Future<ReceiptReading> recognize(String imagePath) {
    if (_closing != null) throw StateError('O serviço OCR já foi fechado.');
    if (_pending != null) throw StateError('Já existe uma leitura em curso.');
    final operation = _recognize(imagePath);
    _pending = operation;
    return _complete(operation);
  }

  Future<ReceiptReading> _complete(Future<ReceiptReading> operation) async {
    try {
      return await operation;
    } finally {
      _pending = null;
    }
  }

  Future<ReceiptReading> _recognize(String imagePath) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('O OCR está disponível apenas em Android e iOS.');
    }
    if (!await File(imagePath).exists()) {
      throw const FileSystemException('A imagem já não está disponível.');
    }
    final recognizer = _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
    return const ReceiptParser().parse(result.text);
  }

  /// Espera pela leitura antes de libertar os recursos nativos.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _pending;
    } catch (_) {
      // O erro da leitura já é tratado pelo chamador.
    } finally {
      await _recognizer?.close();
      _recognizer = null;
    }
  }
}
