import 'dart:async';

import 'package:flutter/material.dart';

class WebviewTooltip {
  WebviewTooltip(BuildContext context) {
    _overlayState = Overlay.maybeOf(context);
    final renderBox = context.findRenderObject();
    if (renderBox is RenderBox) {
      _box = renderBox;
    }
  }

  OverlayState? _overlayState;
  OverlayEntry? _overlayEntry;
  Timer? _delayTimer;
  Timer? _autoDismissTimer;
  Offset cursorOffset = Offset.zero;
  RenderBox? _box;
  final TextStyle _textStyle =
      const TextStyle(color: Colors.black, fontSize: 14);

  void dismiss() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (_overlayEntry != null) {
      try {
        _overlayEntry?.remove();
      } catch (_) {}
      _overlayEntry = null;
    }
  }

  void _buildOverlayEntry(String text) {
    _delayTimer?.cancel();
    _delayTimer = Timer(const Duration(milliseconds: 400), () {
      final overlay = _overlayState;
      if (overlay == null || !overlay.mounted) {
        dismiss();
        return;
      }

      if (_overlayEntry != null) {
        try {
          _overlayEntry?.remove();
        } catch (_) {}
        _overlayEntry = null;
      }

      final capturedCursor = cursorOffset;
      final box = _box;
      final boxSize = (box != null && box.attached && box.hasSize)
          ? box.size
          : Size.zero;
      final boxOffset = (box != null && box.attached && box.hasSize)
          ? box.localToGlobal(Offset.zero)
          : Offset.zero;

      _overlayEntry = OverlayEntry(builder: (context) {
        final textPainter = TextPainter(
          locale: Localizations.localeOf(context),
          textDirection: TextDirection.ltr,
          text: TextSpan(text: text, style: _textStyle),
          maxLines: 5,
          ellipsis: '...',
        )..layout(maxWidth: boxSize.width > 32 ? boxSize.width - 32 : 400);

        double tipX = capturedCursor.dx + 12;
        double tipY = capturedCursor.dy + 18;

        if (boxSize.width > 0 && boxSize.height > 0) {
          final maxX = boxOffset.dx + boxSize.width - textPainter.width - 24;
          if (tipX > maxX) {
            tipX = (capturedCursor.dx - textPainter.width - 12)
                .clamp(boxOffset.dx + 8, maxX > boxOffset.dx + 8 ? maxX : boxOffset.dx + 8);
          }
          final maxY = boxOffset.dy + boxSize.height - textPainter.height - 24;
          if (tipY > maxY) {
            tipY = (capturedCursor.dy - textPainter.height - 18)
                .clamp(boxOffset.dy + 8, maxY > boxOffset.dy + 8 ? maxY : boxOffset.dy + 8);
          }
        }

        return Positioned(
          top: tipY,
          left: tipX,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxWidth: textPainter.width + 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 4,
                      color: Colors.black.withValues(alpha: .25),
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: RichText(
                  text: TextSpan(text: text, style: _textStyle),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      });

      try {
        overlay.insert(_overlayEntry!);
        _autoDismissTimer?.cancel();
        _autoDismissTimer = Timer(const Duration(seconds: 4), () {
          dismiss();
        });
      } catch (_) {
        dismiss();
      }
    });
  }

  void showToolTip(String text) {
    if (text.isEmpty) {
      dismiss();
      return;
    }
    dismiss();
    _buildOverlayEntry(text);
  }
}
