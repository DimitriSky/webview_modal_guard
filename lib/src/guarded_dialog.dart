import 'package:flutter/material.dart';

import '../webview_modal_guard.dart';

/// A Material dialog with native input isolation through its exit animation.
Future<T?> showWebViewGuardedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  WebViewModalGuard guard = const WebViewModalGuard(),
  bool barrierDismissible = true,
  Color barrierColor = Colors.black54,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) async {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final lease = await guard.acquire();
  DialogRoute<T>? route;
  var pushed = false;
  try {
    if (!context.mounted || !navigator.mounted) return null;
    route = DialogRoute<T>(
      context: context,
      builder: builder,
      themes: themes,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
    );
    final result = navigator.push<T>(route);
    pushed = true;
    // Navigator disposal completes route removal without completing push's
    // result future. Either event must reach cleanup.
    return await Future.any<T?>([result, route.completed]);
  } finally {
    try {
      // push completes on pop, while the native view is still covered.
      if (pushed) await route!.completed;
    } finally {
      await lease.release();
    }
  }
}
