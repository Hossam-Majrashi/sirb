import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Desktop context menu route that dismisses immediately on single click/pointer-down
/// anywhere outside the menu, and automatically dismisses any previously active
/// context menu so menus never stack.
class DesktopContextMenuRoute<T> extends PopupRoute<T> {
  DesktopContextMenuRoute({
    required this.position,
    required this.items,
    required this.theme,
    required this.popupMenuTheme,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final ThemeData theme;
  final PopupMenuThemeData popupMenuTheme;

  static Route<dynamic>? _activeRoute;

  /// Closes any currently active desktop context menu immediately.
  static void dismissActive() {
    if (_activeRoute != null && _activeRoute!.isActive) {
      final route = _activeRoute!;
      _activeRoute = null;
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 100);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildModalBarrier() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (barrierDismissible && isCurrent) {
          navigator?.pop();
        }
      },
      child: const SizedBox.expand(),
    );
  }

  @override
  TickerFuture didPush() {
    _activeRoute = this;
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    if (_activeRoute == this) {
      _activeRoute = null;
    }
    return super.didPop(result);
  }

  @override
  void dispose() {
    if (_activeRoute == this) {
      _activeRoute = null;
    }
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: Builder(
        builder: (BuildContext context) {
          return CustomSingleChildLayout(
            delegate: _DesktopContextMenuLayout(
              position: position,
              textDirection: Directionality.of(context),
            ),
            child: FadeTransition(
              opacity: animation,
              child: Theme(
                data: theme,
                child: Material(
                  shape: popupMenuTheme.shape ??
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                  color: popupMenuTheme.color ?? theme.colorScheme.surface,
                  elevation: popupMenuTheme.elevation ?? 8.0,
                  shadowColor: popupMenuTheme.shadowColor ?? Colors.black54,
                  clipBehavior: Clip.antiAlias,
                  type: MaterialType.card,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 160.0,
                      maxWidth: 320.0,
                    ),
                    child: IntrinsicWidth(
                      stepWidth: 16.0,
                      child: Semantics(
                        role: SemanticsRole.menu,
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: 'Context Menu',
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListBody(
                            children: items,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopContextMenuLayout extends SingleChildLayoutDelegate {
  _DesktopContextMenuLayout({
    required this.position,
    required this.textDirection,
  });

  final RelativeRect position;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest)
        .deflate(const EdgeInsets.all(8.0));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double y = position.top;
    double x;
    if (position.left > position.right) {
      x = size.width - position.right - childSize.width;
    } else if (position.left < position.right) {
      x = position.left;
    } else {
      x = switch (textDirection) {
        TextDirection.rtl => size.width - position.right - childSize.width,
        TextDirection.ltr => position.left,
      };
    }

    const margin = 8.0;
    if (x < margin) {
      x = margin;
    } else if (x + childSize.width > size.width - margin) {
      x = size.width - childSize.width - margin;
    }

    if (y < margin) {
      y = margin;
    } else if (y + childSize.height > size.height - margin) {
      y = size.height - childSize.height - margin;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_DesktopContextMenuLayout oldDelegate) {
    return position != oldDelegate.position ||
        textDirection != oldDelegate.textDirection;
  }
}

/// Shows a desktop context menu that closes immediately on single click outside
/// without stacking.
Future<T?> showDesktopContextMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) {
  if (items.isEmpty) {
    return Future<T?>.value(null);
  }
  DesktopContextMenuRoute.dismissActive();

  final theme = Theme.of(context);
  final popupMenuTheme = PopupMenuTheme.of(context);
  final route = DesktopContextMenuRoute<T>(
    position: position,
    items: items,
    theme: theme,
    popupMenuTheme: popupMenuTheme,
  );

  return Navigator.of(context, rootNavigator: false).push<T>(route);
}
