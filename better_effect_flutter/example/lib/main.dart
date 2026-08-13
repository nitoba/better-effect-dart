import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:better_effect_flutter_example/ui/splash_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config/app_module.dart';
import 'ui/tasks_screen.dart';

void main() {
  runApp(
    BetterEffectBootstrap(
      module: appModule,
      observer: (transition) {
        if (kDebugMode) {
          debugPrint('$transition');
        }
      },
      loadingBuilder: (_) => const SplashScreen(),
      minimumLoadingDuration: const Duration(seconds: 2),
      errorBuilder: (context, error, stackTrace, retry) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not start the app: $error'),
              ),
            ),
          ),
        );
      },
      builder: (_) => const TasksApp(),
    ),
  );
  // Or Use Application root method
  // return runBetterEffectApp(
  //   module: appModule,
  //   observer: (transition) {
  //     if (kDebugMode) {
  //       debugPrint('$transition');
  //     }
  //   },
  //   startupErrorBuilder: (error, stackTrace) {
  //     return MaterialApp(
  //       home: Scaffold(
  //         body: Center(
  //           child: Padding(
  //             padding: const EdgeInsets.all(24),
  //             child: Text('Could not start the app: $error'),
  //           ),
  //         ),
  //       ),
  //     );
  //   },
  //   app: const TasksApp(),
  // );
}
