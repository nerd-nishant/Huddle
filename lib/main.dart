import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'auth/auth_screen.dart';
import 'shell/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.isConfigured) {
    await Supabase.initialize(
        url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  }
  runApp(const HuddleApp());
}

class HuddleApp extends StatelessWidget {
  const HuddleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HUDDLE',
        debugShowCheckedModeBanner: false,
        theme: huddleTheme(Brightness.light),
        darkTheme: huddleTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: Config.isConfigured ? const Gate() : const SetupScreen(),
      );
}

/// Routes by auth state: signed out -> AuthScreen, signed in -> Shell.
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: sb.auth.onAuthStateChange,
        builder: (context, _) {
          if (sb.auth.currentSession == null) return const AuthScreen();
          return const ProfileLoader();
        },
      );
}

class ProfileLoader extends StatefulWidget {
  const ProfileLoader({super.key});
  @override
  State<ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<ProfileLoader> {
  late Future<Profile?> f = loadProfile();
  void _retry() => setState(() => f = loadProfile());

  @override
  Widget build(BuildContext context) => FutureBuilder<Profile?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError || snap.data == null) {
            return Scaffold(
              body: SafeArea(
                child: ErrorState(
                    error: snap.error ?? 'Profile not found', onRetry: _retry),
              ),
            );
          }
          final me = snap.data!;
          if (!me.authorised) return PendingScreen(onRefresh: _retry);
          return Shell(me: me);
        },
      );
}

/// Teachers must be approved by an administrator before they can mark attendance.
class PendingScreen extends StatelessWidget {
  final VoidCallback onRefresh;
  const PendingScreen({super.key, required this.onRefresh});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.hourglass_top_rounded,
            title: 'Waiting for authorisation',
            subtitle:
                'Teacher accounts are verified by your institution before attendance tools unlock. Check back soon.',
            action: Column(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(onPressed: onRefresh, child: const Text('Check again')),
              TextButton(
                  onPressed: () => sb.auth.signOut(),
                  child: const Text('Sign out')),
            ]),
          ),
        ),
      );
}

/// Shown when the APK was built without backend credentials.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (r) => HC.grad.createShader(r),
                    child: const Text('HUDDLE',
                        style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  const Pill('Backend not connected',
                      color: HC.peach, icon: Icons.link_off_rounded),
                  const SizedBox(height: 16),
                  const Text(
                      'This build has no Supabase credentials. Rebuild with:\n\n'
                      '--dart-define=SUPABASE_URL=...\n'
                      '--dart-define=SUPABASE_ANON_KEY=...\n\n'
                      'Then run supabase/schema.sql in your Supabase project. See README.md.',
                      style: TextStyle(height: 1.5)),
                ]),
          ),
        ),
      );
}
