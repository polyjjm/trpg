import 'package:flutter/widgets.dart';

import '../state/cloud_sync_controller.dart';
import 'auth_service.dart';

/// [AuthService]와 [CloudSyncController]를 위젯 트리 아래로 전달한다.
class AuthScope extends InheritedWidget {
  const AuthScope({
    super.key,
    required this.authService,
    required this.cloudSyncController,
    required super.child,
  });

  final AuthService authService;
  final CloudSyncController cloudSyncController;

  static AuthService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope.of() called with no AuthScope ancestor');
    return scope!.authService;
  }

  static CloudSyncController cloudSyncOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope.cloudSyncOf() called with no AuthScope ancestor');
    return scope!.cloudSyncController;
  }

  @override
  bool updateShouldNotify(AuthScope oldWidget) =>
      authService != oldWidget.authService ||
      cloudSyncController != oldWidget.cloudSyncController;
}
