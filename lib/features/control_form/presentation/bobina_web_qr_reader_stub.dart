import 'package:flutter/widgets.dart';

/// Stub para plataformas nativas (Android/iOS). Nunca se construye ahí:
/// [BobinaQrScannerPage] solo lo usa cuando `kIsWeb` es true, y en ese caso
/// la importación condicional resuelve a `bobina_web_qr_reader_web.dart` en
/// vez de este archivo.
class BobinaWebQrReaderView extends StatelessWidget {
  const BobinaWebQrReaderView({super.key, required this.onDetect});

  final ValueChanged<String> onDetect;

  @override
  Widget build(BuildContext context) {
    throw UnsupportedError(
      'BobinaWebQrReaderView solo está disponible en Flutter Web.',
    );
  }
}
