import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Tamaño máximo por archivo de evidencia (el backend rechaza lo que lo supere).
const int maxBytesEvidencia = 25 * 1024 * 1024;

/// Vista previa de una evidencia antes de guardar: miniatura si es imagen, ícono si es PDF.
class EvidenciaMiniatura extends StatelessWidget {
  final Uint8List bytes;
  final String nombre;
  final double size;

  const EvidenciaMiniatura({
    super.key,
    required this.bytes,
    required this.nombre,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final esPdf = nombre.toLowerCase().endsWith('.pdf');

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: esPdf
            ? const ColoredBox(
                color: Color(0xFF263238),
                child: Icon(Icons.picture_as_pdf, color: Color(0xFFFFCC80)),
              )
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF263238),
                  child: Icon(Icons.broken_image, color: Color(0xFFB0BEC5)),
                ),
              ),
      ),
    );
  }
}
