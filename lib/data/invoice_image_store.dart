import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// On-disk store for scanned invoice images, keyed by the push_queue row id.
///
/// The scanned image only lives in memory on the transient local scan entry,
/// so the push_queue (supabase) row that comes back via realtime has none.
/// Persisting it under the row id lets the queue row show the image after the
/// sheet closes and across app restarts.
class InvoiceImageStore {
  const InvoiceImageStore._();

  static Future<File> _fileFor(String rowId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/invoice_images');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File('${folder.path}/$rowId.jpg');
  }

  /// Writes the scanned image bytes for [rowId]. Quietly does nothing on error.
  static Future<void> save(String rowId, Uint8List bytes) async {
    if (rowId.isEmpty) return;
    try {
      final file = await _fileFor(rowId);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// Returns the stored image bytes for [rowId], or null if none/on error.
  static Future<Uint8List?> load(String rowId) async {
    if (rowId.isEmpty) return null;
    try {
      final file = await _fileFor(rowId);
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    return null;
  }
}
