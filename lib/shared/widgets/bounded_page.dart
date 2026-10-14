import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class BoundedPage extends StatelessWidget {
  const BoundedPage({super.key, required this.child, this.width = 840});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons & kBackMouseButton != 0) {
        Navigator.maybePop(context);
      }
    },
    child: LayoutBuilder(
      builder: (context, c) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: c.maxWidth < 600 ? 16 : 32,
              vertical: 24,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
