import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../core/utils.dart';
import '../../core/palette.dart';
import '../../shared/screen_frame.dart';
import 'camera_overlay.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
    required this.captures,
    required this.activeCaptureType,
    required this.onCaptureRequested,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final List<CapturedShot> captures;
  final TransactionType? activeCaptureType;
  final Future<void> Function(TransactionType? preferredType) onCaptureRequested;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Future<void> _savePdf(CapturedShot shot) async {
    try {
      final bytes = await File(shot.path).readAsBytes();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF',
        fileName: 'challan_${shot.type.name}_$ts.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF saved')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _openCaptureTray() async {
    if (widget.captures.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.44,
          child: Container(
            decoration: const BoxDecoration(
              color: AppPalette.sheet,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 56,
                  height: 4,
                  decoration: BoxDecoration(color: AppPalette.line, borderRadius: BorderRadius.circular(99)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Row(
                    children: [
                      Text('Captured batch', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text('${widget.captures.length} shots', style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    itemCount: widget.captures.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.74,
                    ),
                    itemBuilder: (context, index) {
                      final shot = widget.captures[index];
                      final color = captureColorForType(shot.type, seedOffset: index);
                      return Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppPalette.ink, width: 1.4),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [color.withValues(alpha: 0.95), AppPalette.ink],
                              ),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shot.path.split(RegExp(r'[\\/]')).last.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                                ),
                                const Spacer(),
                                Text('${shot.type.label} receipt', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white)),
                                Text('Capture ${index + 1}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => _savePdf(shot),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white38, width: 1),
                                ),
                                child: const Icon(Icons.download_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.18,
            colors: [Color(0xFF31353F), Color(0xFF171A20), Color(0xFF0D0F12)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: CameraOverlayBrackets())),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          if (widget.activeCaptureType != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white70, width: 1.2),
                              ),
                              child: Text(
                                '${widget.activeCaptureType!.label} batch',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ),
                          const SizedBox(height: 18),
                          Text(
                            widget.activeCaptureType == null
                                ? 'choose sale or purchase first'
                                : 'point at ${widget.activeCaptureType!.label.toLowerCase()} receipt',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: _openCaptureTray,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      widget.captures.isEmpty
                                          ? Colors.white24
                                          : captureColorForType(widget.captures.last.type, seedOffset: widget.captures.length).withValues(alpha: 0.95),
                                      Colors.black,
                                    ],
                                  ),
                                ),
                              ),
                              if (widget.captures.isNotEmpty)
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: AppPalette.accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.3),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('${widget.captures.length}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontSize: 10)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => widget.onCaptureRequested(widget.activeCaptureType),
                          child: Container(
                            width: 82,
                            height: 82,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.94), width: 2.2),
                            ),
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Colors.black87, width: 2.6)),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => widget.onCaptureRequested(null),
                          child: Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 1.6)),
                            child: Text('+', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
