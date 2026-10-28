import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/explore_screen.dart';
import 'screens/my_work_screen.dart';
import 'screens/setup_guide_screen.dart';
import 'screens/studio_screen.dart';
import 'state/studio_state.dart';
import 'theme.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  studio.loadLibrary();
  runApp(const LiveWallpaperStudioApp());
}

class LiveWallpaperStudioApp extends StatelessWidget {
  const LiveWallpaperStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Wallpaper Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Keep layouts intact when the phone uses a very large or small font size.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.15),
          ),
          child: child!,
        );
      },
      home: const HomeShell(),
    );
  }
}

/// Root screen: Studio and Guide tabs with the floating pill bar.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: studio.tab,
                children: const [StudioScreen(), ExploreScreen(), MyWorkScreen(), SetupGuideScreen()],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 20 + MediaQuery.of(context).padding.bottom,
                child: Center(
                  child: FloatingTabBar(
                    index: studio.tab,
                    onChanged: studio.setTab,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
