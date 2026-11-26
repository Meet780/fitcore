import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';


String? _fitCoreDatasetMediaUrl(dynamic path) {
  final value = (path ?? '').toString().trim();
  if (value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  final clean = value.replaceFirst(RegExp(r'^/+'), '');
  return 'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/$clean';
}

Widget _fitCoreExerciseThumbnail(dynamic exerciseOrMediaId, {double size = 54}) {
  final Map? record = exerciseOrMediaId is Map ? exerciseOrMediaId : null;
  final mediaId = record == null ? (exerciseOrMediaId ?? '').toString().trim() : '';
  final imageUrl = record != null ? _fitCoreDatasetMediaUrl(record['image']) : null;
  final gifUrl = record != null
      ? _fitCoreDatasetMediaUrl(record['gif_url'])
      : (mediaId.isNotEmpty ? 'https://static.exercisedb.dev/media/$mediaId.gif' : null);

  Widget unavailable() => const _ExerciseImageUnavailable();
  Widget gifFallback() {
    if (gifUrl == null) return unavailable();
    return Image.network(
      gifUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => unavailable(),
    );
  }

  // The dataset JPG is the most reliable thumbnail; use the dataset GIF if it fails.
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: size,
      height: size,
      color: const Color(0xFF202322),
      alignment: Alignment.center,
      child: imageUrl == null
          ? gifFallback()
          : Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return const _ExerciseImageLoading();
        },
        errorBuilder: (_, __, ___) => gifFallback(),
      ),
    ),
  );
}

class _ExerciseImageLoading extends StatelessWidget {
  const _ExerciseImageLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFF00D4FF),
      ),
    ),
  );
}

class _ExerciseImageUnavailable extends StatelessWidget {
  const _ExerciseImageUnavailable();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(
      Icons.image_not_supported_outlined,
      color: Color(0xFF00D4FF),
      size: 22,
    ),
  );
}

Future<Map<String, String>> _fitCoreLoadMediaByExerciseName() async {
  final raw = await rootBundle.loadString(
    'assets/exercises/exercises-dataset-main/data/exercises.json',
  );
  final decoded = jsonDecode(raw) as List;
  final mediaByName = <String, String>{};
  for (final row in decoded.whereType<Map>()) {
    final name = (row['name'] ?? '').toString().trim().toLowerCase();
    final media = (row['media_id'] ?? '').toString().trim();
    if (name.isNotEmpty && media.isNotEmpty) {
      mediaByName.putIfAbsent(name, () => media);
    }
  }
  return mediaByName;
}

Future<List<Map<String, dynamic>>> _fitCoreLoadExerciseRecords() async {
  final raw = await rootBundle.loadString(
    'assets/exercises/exercises-dataset-main/data/exercises.json',
  );
  final decoded = jsonDecode(raw) as List;
  return decoded.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}

IconData _fitCoreSplitIcon(dynamic splitValue) {
  switch ((splitValue ?? '').toString().toLowerCase()) {
    case 'push': return Icons.arrow_circle_up_rounded;
    case 'pull': return Icons.arrow_circle_down_rounded;
    case 'legs': return Icons.directions_run_rounded;
    case 'upper': return Icons.accessibility_new_rounded;
    case 'lower': return Icons.sports_gymnastics_rounded;
    case 'bro split': return Icons.calendar_view_week_rounded;
    case 'full body': return Icons.self_improvement_rounded;
    case 'custom': return Icons.tune_rounded;
    default: return Icons.grid_view_rounded;
  }
}

Widget _fitCoreSplitBadge(dynamic split, {double size = 42}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF00D4FF).withOpacity(.14),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFF00D4FF).withOpacity(.48), width: 1.2),
    ),
    child: Icon(_fitCoreSplitIcon(split), color: const Color(0xFF00D4FF), size: size * .68),
  );
}


// Maps atlas anatomy into the muscle groups used by FitCore workout splits.
String _fitCoreFitnessGroupForMuscle(MuscleInfo muscle) {
  final id = muscle.id.toLowerCase();
  final atlasGroup = muscle.group.id.toLowerCase();

  if (id.contains('pectoralis') || atlasGroup == 'chest') return 'chest';
  if (id.contains('biceps_brachii')) return 'biceps';
  if (id.contains('triceps_brachii')) return 'triceps';
  if (id.contains('deltoid')) return 'shoulders';
  if (id.contains('trapezius') ||
      id.contains('rhomboid') ||
      id.contains('latissimus') ||
      id.contains('infraspinatus') ||
      id.contains('teres_major') ||
      atlasGroup == 'back') return 'back';
  if (atlasGroup == 'core' ||
      id.contains('rectus_abdominis') ||
      id.contains('oblique')) return 'abs';
  if (atlasGroup == 'legs' ||
      atlasGroup == 'hamstrings' ||
      atlasGroup == 'glutes' ||
      atlasGroup == 'adductors') return 'legs';
  if (atlasGroup == 'arms') return 'forearms';
  if (atlasGroup == 'neck') return 'neck';
  if (atlasGroup == 'shoulders') return 'shoulders';
  return atlasGroup;
}

Set<String> _fitCoreSplitMuscleGroups(dynamic splitValue) {
  switch ((splitValue ?? '').toString().toLowerCase()) {
    case 'push':
      return {'chest', 'shoulders', 'triceps'};
    case 'pull':
      return {'back', 'biceps', 'shoulders', 'forearms'};
    case 'legs':
    case 'lower':
      return {'legs'};
    case 'upper':
      return {'chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms'};
    case 'full body':
      return {'chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms', 'legs', 'abs'};
    case 'bro split':
      return {'chest'};
    default:
      return <String>{};
  }
}

Widget _fitCoreSplitMusclePreview(dynamic split, {double width = 104, double height = 82}) {
  final groups = _fitCoreSplitMuscleGroups(split);
  if (groups.isEmpty) return _fitCoreSplitBadge(split, size: height * .68);

  final highlightedMuscles = <MuscleInfo, Color>{
    for (final muscle in Muscle.values.map((item) => MuscleCatalog.byIdOrThrow(item.id)))
      if (groups.contains(_fitCoreFitnessGroupForMuscle(muscle)))
        muscle: const Color(0xFF00D4FF),
  };

  Widget atlas(AtlasAsset view) => Expanded(
    child: IgnorePointer(
      child: BodyAtlasView<MuscleInfo>(
        view: view,
        resolver: const MuscleResolver(),
        colorMapping: highlightedMuscles,
        onTapElement: (_) {},
      ),
    ),
  );

  return Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xFF11191D),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFF00D4FF).withOpacity(.28)),
    ),
    child: Row(
      children: [
        atlas(AtlasAsset.musclesFront),
        const SizedBox(width: 3),
        atlas(AtlasAsset.musclesBack),
      ],
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  _initFitCoreForegroundTask();
  runApp(const FitCoreApp());
}

void _initFitCoreForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'fitcore_workout_channel',
      channelName: 'FitCore workout',
      channelDescription: 'Shows your active workout and timer.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(1000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

String _fitCoreElapsed(String? startedAt) {
  final start = DateTime.tryParse(startedAt ?? '') ?? DateTime.now();
  final seconds = DateTime.now().difference(start).inSeconds.clamp(0, 999999);
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _fitCoreNotificationInfo(Map<String, dynamic> workout) {
  final exercises = workout['exercises'] is List
      ? (workout['exercises'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  Map<String, dynamic>? current;
  var currentSet = 1;
  for (final exercise in exercises) {
    final logged = exercise['actualSets'] is List
        ? (exercise['actualSets'] as List).length
        : (exercise['actualReps'] is List ? (exercise['actualReps'] as List).length : 0);
    final planned = (exercise['sets'] as num?)?.toInt() ?? 1;
    if (logged < planned) {
      current = exercise;
      currentSet = logged + 1;
      break;
    }
  }
  final exerciseName = current == null ? 'Workout in progress' : '${current['name'] ?? 'Exercise'}';
  final setText = current == null ? 'All sets logged' : 'Set $currentSet/${current['sets'] ?? 1}';
  return {
    'planName': '${workout['planName'] ?? 'Workout'}',
    'startedAt': '${workout['startedAt'] ?? DateTime.now().toIso8601String()}',
    'exerciseName': exerciseName,
    'setText': setText,
  };
}

Future<void> _updateFitCoreWorkoutNotification(Map<String, dynamic> workout) async {
  final info = _fitCoreNotificationInfo(workout);
  final payload = jsonEncode(info);
  await FlutterForegroundTask.saveData(key: 'fitcore_workout_notification', value: payload);

  final running = await FlutterForegroundTask.isRunningService;
  if (running) {
    FlutterForegroundTask.sendDataToTask(payload);
    FlutterForegroundTask.updateService(
      notificationTitle: 'FitCore • ${info['planName']}',
      notificationText: '${_fitCoreElapsed(info['startedAt'] as String?)} • ${info['exerciseName']} • ${info['setText']}',
    );
    return;
  }

  final permission = await FlutterForegroundTask.checkNotificationPermission();
  if (permission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  await FlutterForegroundTask.startService(
    serviceId: 341,
    serviceTypes: [ForegroundServiceTypes.dataSync],
    notificationTitle: 'FitCore • ${info['planName']}',
    notificationText: '${_fitCoreElapsed(info['startedAt'] as String?)} • ${info['exerciseName']} • ${info['setText']}',
    notificationInitialRoute: '/',
    callback: fitCoreWorkoutTaskCallback,
  );
}

Future<void> _stopFitCoreWorkoutNotification() async {
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void fitCoreWorkoutTaskCallback() {
  FlutterForegroundTask.setTaskHandler(FitCoreWorkoutTaskHandler());
}

class FitCoreWorkoutTaskHandler extends TaskHandler {
  Map<String, dynamic> _info = {};

  void _readInfo(Object? value) {
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) _info = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _readInfo(await FlutterForegroundTask.getData(key: 'fitcore_workout_notification'));
    _updateNotification();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _updateNotification();
  }

  @override
  void onReceiveData(Object data) {
    _readInfo(data);
    _updateNotification();
  }

  void _updateNotification() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'FitCore • ${_info['planName'] ?? 'Workout'}',
      notificationText: '${_fitCoreElapsed(_info['startedAt'] as String?)} • ${_info['exerciseName'] ?? 'Workout in progress'} • ${_info['setText'] ?? ''}',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

const Color lime = Color(0xFF00D4FF);
const Color bg = Color(0xFF101110);
const Color card = Color(0xFF1B1D1B);
const Color muted = Color(0xFF929792);


// Approximate workout energy expenditure using MET x 3.5 x body mass / 200 x minutes.
// Values follow the 2024 Adult Compendium resistance-training categories.
double fitCoreEstimateWorkoutCalories({
  required double bodyWeightKg,
  required int durationSeconds,
  required double metValue,
}) {
  if (bodyWeightKg <= 0 || durationSeconds <= 0 || metValue <= 0) return 0;
  final minutes = durationSeconds / 60.0;
  return metValue * 3.5 * bodyWeightKg / 200.0 * minutes;
}


class FitCoreApp extends StatelessWidget {
  const FitCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FitCore',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: lime,
          surface: card,
        ),
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _loggedIn = prefs.getBool('fitcore_logged_in') ?? false;
      _checking = false;
    });
  }

  Future<void> _setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fitcore_logged_in', value);
    if (!mounted) return;
    setState(() => _loggedIn = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: lime)),
      );
    }
    return _loggedIn
        ? MainScreen(onLogout: () => _setLoggedIn(false))
        : AuthPage(onSuccess: () => _setLoggedIn(true));
  }
}

class AuthPage extends StatefulWidget {
  final VoidCallback onSuccess;
  const AuthPage({super.key, required this.onSuccess});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isSignup = false;
  bool _showPassword = false;
  bool _busy = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    // Demo-only: stores the session locally. This is not secure server authentication.
    final prefs = await SharedPreferences.getInstance();
    if (_isSignup) {
      await prefs.setString('fitcore_user_name', _nameController.text.trim());
    }
    await prefs.setString('fitcore_user_email', _emailController.text.trim());
    await prefs.setBool('fitcore_logged_in', true);

    if (!mounted) return;
    setState(() => _busy = false);
    widget.onSuccess();
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: muted),
      filled: true,
      fillColor: const Color(0xFF202320),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: lime, width: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: lime,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.fitness_center_rounded,
                          color: Colors.black, size: 36),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _isSignup ? 'CREATE ACCOUNT' : 'WELCOME BACK',
                      style: const TextStyle(
                        color: lime,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isSignup ? 'Start your fitness journey.' : 'Your next rep starts here.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Train smarter. Stay consistent. Become stronger.',
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                    const SizedBox(height: 30),
                    if (_isSignup) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration('Full name', Icons.person_outline),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _decoration('Email address', Icons.mail_outline),
                      validator: (v) {
                        if (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(v.trim())) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      decoration: _decoration('Password', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword ? Icons.visibility_off : Icons.visibility,
                            color: muted,
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Password must be at least 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: lime,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black,
                          ),
                        )
                            : Text(
                          _isSignup ? 'CREATE ACCOUNT' : 'LOGIN',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isSignup ? 'Already have an account? ' : 'New to FitCore? ',
                          style: const TextStyle(color: muted),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _isSignup = !_isSignup),
                          child: Text(
                            _isSignup ? 'Login' : 'Sign up',
                            style: const TextStyle(
                              color: lime,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'DEMO AUTH • LOCAL SESSION ONLY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class MainScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const MainScreen({super.key, this.onLogout});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _restoreWorkoutNotification();
  }

  Future<void> _restoreWorkoutNotification() async {
    final active = await loadFitCoreActiveWorkout();
    if (active != null) {
      await _updateFitCoreWorkoutNotification(active);
    } else {
      await _stopFitCoreWorkoutNotification();
    }
  }

  final titles = [
    'Dashboard',
    'Workouts',
    'Trainer',
    'Analysis',
    'History',
  ];

  Future<void> _startHomeWorkout() async {
    final active = await loadFitCoreActiveWorkout();
    if (!mounted) return;
    if (active != null && active['exercises'] is List) {
      final activeExercises = (active['exercises'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (activeExercises.isNotEmpty) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CustomWorkoutSessionPage(
              planName: '${active['planName'] ?? 'Workout'}',
              exercises: activeExercises,
              planId: active['planId']?.toString(),
              initialStartedAt: active['startedAt']?.toString(),
              initialEffort: active['workoutEffort']?.toString(),
            ),
          ),
        );
        return;
      }
    }

    final plans = await loadCustomWorkoutPlans();
    if (!mounted) return;
    if (plans.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkoutPlansPage()),
      );
      return;
    }
    final plan = plans.first;
    final rawExercises = plan['exercises'];
    final exercises = rawExercises is List
        ? rawExercises.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    if (exercises.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkoutPlansPage()),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a plan and add exercises before starting.')),
        );
      }
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomWorkoutSessionPage(
          planName: '${plan['name']}',
          exercises: exercises,
          planId: '${plan['id']}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: selectedIndex == 5
            ? ProfilePage(
          onLogout: widget.onLogout,
          onBack: () => setState(() => selectedIndex = 0),
        )
            : selectedIndex == 0
            ? DashboardPage(
          onProfileTap: () => setState(() => selectedIndex = 5),
          onViewPlan: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const WorkoutPlansPage(),
            ),
          ),
          onStartWorkout: _startHomeWorkout,
        )
            : selectedIndex == 1
            ? const WorkoutPlansPage()
            : selectedIndex == 2
            ? const TrainerPage()
            : selectedIndex == 4
            ? const WorkoutHistoryPage()
            : SimplePage(title: titles[selectedIndex]),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: card,
          border: Border(
            top: BorderSide(color: Colors.white10),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: NavigationBar(
                backgroundColor: card,
                indicatorColor: lime.withOpacity(0.15),
                selectedIndex: selectedIndex == 5 ? 0 : selectedIndex,
                onDestinationSelected: (index) {
                  setState(() => selectedIndex = index);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.fitness_center_rounded),
                    label: 'Workout',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    label: 'Trainer',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.insights_rounded),
                    label: 'Analysis',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    label: 'History',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class ProfilePage extends StatefulWidget {
  final VoidCallback? onLogout;
  final VoidCallback onBack;

  const ProfilePage({
    super.key,
    required this.onLogout,
    required this.onBack,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String _goal = 'General Fitness';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString('fitcore_user_name') ?? '';
    _emailController.text = prefs.getString('fitcore_user_email') ?? '';
    _ageController.text = prefs.getString('fitcore_profile_age') ?? '';
    _heightController.text = prefs.getString('fitcore_profile_height') ?? '';
    _weightController.text = prefs.getString('fitcore_profile_weight') ?? '';
    _goal = prefs.getString('fitcore_profile_goal') ?? 'General Fitness';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fitcore_user_name', _nameController.text.trim());
    await prefs.setString('fitcore_user_email', _emailController.text.trim());
    await prefs.setString('fitcore_profile_age', _ageController.text.trim());
    await prefs.setString('fitcore_profile_height', _heightController.text.trim());
    await prefs.setString('fitcore_profile_weight', _weightController.text.trim());
    await prefs.setString('fitcore_profile_goal', _goal);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved successfully')),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        title: const Text('Log out?'),
        content: const Text('You will return to the FitCore login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: lime,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout?.call();
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: muted),
      filled: true,
      fillColor: const Color(0xFF202320),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: lime, width: 1.2),
      ),
    );
  }

  Widget _profileField(
      TextEditingController controller,
      String label,
      IconData icon, {
        TextInputType keyboardType = TextInputType.text,
      }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(label, icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        leading: IconButton(
          tooltip: 'Back to dashboard',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'PROFILE & SETTINGS',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: lime))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    height: 82,
                    width: 82,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: lime.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: lime,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'YOUR FITNESS PROFILE',
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            _profileField(_nameController, 'Full name', Icons.person_outline),
            const SizedBox(height: 14),
            _profileField(_emailController, 'Email', Icons.mail_outline,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _profileField(
                    _ageController,
                    'Age',
                    Icons.cake_outlined,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _profileField(
                    _heightController,
                    'Height (cm)',
                    Icons.height_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _profileField(
              _weightController,
              'Weight (kg)',
              Icons.monitor_weight_outlined,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _goal,
              decoration: _fieldDecoration(
                'Fitness goal',
                Icons.flag_outlined,
              ),
              dropdownColor: card,
              items: const [
                DropdownMenuItem(
                  value: 'General Fitness',
                  child: Text('General Fitness'),
                ),
                DropdownMenuItem(
                  value: 'Muscle Gain',
                  child: Text('Muscle Gain'),
                ),
                DropdownMenuItem(
                  value: 'Fat Loss',
                  child: Text('Fat Loss'),
                ),
                DropdownMenuItem(
                  value: 'Strength',
                  child: Text('Strength'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _goal = value);
              },
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: lime,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _saveProfile,
                icon: const Icon(Icons.save_rounded),
                label: const Text(
                  'SAVE PROFILE',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'LOG OUT',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'FitCore • Local profile data',
                style: TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onViewPlan;
  final Future<void> Function() onStartWorkout;

  const DashboardPage({
    super.key,
    required this.onProfileTap,
    required this.onViewPlan,
    required this.onStartWorkout,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _activeWorkoutTicker;
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _activeWorkout;

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
    _activeWorkoutTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeWorkout != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _activeWorkoutTicker?.cancel();
    super.dispose();
  }

  String _homeWorkoutTime() {
    final started = DateTime.tryParse('${_activeWorkout?['startedAt'] ?? ''}');
    if (started == null) return '00:00';
    final seconds = DateTime.now().difference(started).inSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final sec = seconds % 60;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshDashboard() async {
    await loadWorkoutHistory();
    final results = await Future.wait([
      loadCustomWorkoutPlans(),
      loadFitCoreActiveWorkout(),
    ]);
    if (!mounted) return;
    setState(() {
      _plans = results[0] as List<Map<String, dynamic>>;
      _activeWorkout = results[1] as Map<String, dynamic>?;
    });
  }

  Future<void> _startOrContinueWorkout() async {
    await widget.onStartWorkout();
    await _refreshDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final totalWorkouts = fitCoreHistory.length;
    final todayPlan = _plans.isNotEmpty ? _plans.first : null;
    final todayPlanExercises = todayPlan != null && todayPlan['exercises'] is List
        ? (todayPlan['exercises'] as List).length
        : 0;

    final now = DateTime.now();

    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    final weeklyWorkoutDays = List<bool>.generate(7, (index) {
      final day = weekStart.add(Duration(days: index));

      return fitCoreHistory.any((session) {
        final dateValue = session['date'];

        if (dateValue is! String) return false;

        final sessionDate = DateTime.tryParse(dateValue);

        return sessionDate != null &&
            sessionDate.year == day.year &&
            sessionDate.month == day.month &&
            sessionDate.day == day.day;
      });
    });

    final weeklyDaysCount =
        weeklyWorkoutDays.where((worked) => worked).length;

    final weeklyPercent =
    (weeklyDaysCount / 5 * 100).clamp(0, 100).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: lime,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.black,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FITCORE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'YOUR FITNESS JOURNEY',
                    style: TextStyle(
                      color: muted,
                      fontSize: 9,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Profile & settings',
                onPressed: widget.onProfileTap,
                style: IconButton.styleFrom(
                  backgroundColor: card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  fixedSize: const Size(42, 42),
                ),
                icon: const Icon(Icons.account_circle_outlined, color: lime),
              ),
            ],
          ),

          const SizedBox(height: 30),

          Text(
            '${['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'][now.weekday - 1]}, ${['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'][now.month - 1]} ${now.day}',
            style: const TextStyle(
              color: muted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'LET’S GET\nSTRONGER.',
            style: TextStyle(
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),

          const SizedBox(height: 22),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: lime,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'YOUR WEEKLY ACTIVITY',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$weeklyDaysCount',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    SizedBox(width: 8),
                    Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text(
                        '${weeklyDaysCount} / 5 DAYS',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Spacer(),
                    Text(
                      '$weeklyPercent%',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: List.generate(7, (index) {
                    final active = weeklyWorkoutDays[index];
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 5),
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.black
                              : Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                const Text(
                  'You’re building a great habit. Keep going!',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.timer_outlined,
                  label: 'WORKOUT TIME',
                  value: '3.5',
                  unit: 'hrs',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  icon: Icons.bolt_rounded,
                  label: 'WORKOUTS SAVED',
                  value: totalWorkouts.toString(),
                  unit: 'sessions',
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Row(
            children: [
              Text(
                'TODAY’S WORKOUT',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              Spacer(),
              TextButton(
                onPressed: widget.onViewPlan,
                style: TextButton.styleFrom(
                  foregroundColor: lime,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'VIEW PLAN  →',
                  style: TextStyle(
                    color: lime,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      height: 58,
                      width: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        color: lime,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeWorkout != null
                                ? '${_activeWorkout!['planName'] ?? 'WORKOUT'}'.toUpperCase()
                                : todayPlan == null
                                ? 'NO PLAN CREATED'
                                : '${todayPlan['name']}'.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _activeWorkout != null
                                ? 'Workout in progress • ${_homeWorkoutTime()} • Tap continue'
                                : todayPlan == null
                                ? 'Create a custom workout plan'
                                : '${todayPlan['split']} • $todayPlanExercises exercises',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: muted),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: lime,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _startOrContinueWorkout,
                    child: Text(
                      _activeWorkout == null ? 'START WORKOUT  →' : 'CONTINUE WORKOUT  →',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Row(
            children: [
              Text(
                'YOUR TRAINER',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              Spacer(),
              Icon(Icons.more_horiz_rounded, color: muted),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFF343834),
                  child: Icon(Icons.person, color: lime, size: 28),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alex Johnson',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Certified Personal Trainer',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chat_bubble_outline_rounded, color: lime),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final totalWorkouts = fitCoreHistory.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: lime, size: 20),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              color: muted,
              fontSize: 9,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



class SimplePage extends StatelessWidget {
  final String title;

  const SimplePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    if (title == 'Workouts') {
      return const WorkoutPlansPage();
    }
    if (title == 'Analysis') {
      return const AnalysisPage();
    }
    if (title == 'History') {
      return const WorkoutHistoryPage();
    }
    return Center(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ---------------- CUSTOM WORKOUT PLANS ----------------
// Plans and exercises are stored locally on this device with SharedPreferences.
const String fitCorePlansKey = 'fitcore_custom_plans';

Future<List<Map<String, dynamic>>> loadCustomWorkoutPlans() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(fitCorePlansKey);
  if (raw == null) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (e) {
    debugPrint('Custom plan loading error: $e');
    return [];
  }
}

Future<void> saveCustomWorkoutPlans(
    List<Map<String, dynamic>> plans) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(fitCorePlansKey, jsonEncode(plans));
}

const String fitCoreActiveWorkoutKey = 'fitcore_active_workout';

Future<Map<String, dynamic>?> loadFitCoreActiveWorkout() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(fitCoreActiveWorkoutKey);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (e) {
    debugPrint('Active workout loading error: $e');
  }
  return null;
}

Future<void> saveFitCoreActiveWorkout(Map<String, dynamic> workout) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(fitCoreActiveWorkoutKey, jsonEncode(workout));
}

Future<void> clearFitCoreActiveWorkout() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(fitCoreActiveWorkoutKey);
}

const List<String> fitCoreSplitOptions = [
  'Push',
  'Pull',
  'Legs',
  'Upper',
  'Lower',
  'Bro Split',
  'Full Body',
  'Custom',
];

const List<Map<String, dynamic>> fitCoreExerciseOptions = [
  {'name': 'Bench Press', 'muscle': 'Chest'},
  {'name': 'Incline Dumbbell Press', 'muscle': 'Chest'},
  {'name': 'Chest Fly', 'muscle': 'Chest'},
  {'name': 'Shoulder Press', 'muscle': 'Shoulders'},
  {'name': 'Lateral Raise', 'muscle': 'Shoulders'},
  {'name': 'Triceps Pushdown', 'muscle': 'Triceps'},
  {'name': 'Pull Ups', 'muscle': 'Back'},
  {'name': 'Lat Pulldown', 'muscle': 'Back'},
  {'name': 'Seated Cable Row', 'muscle': 'Back'},
  {'name': 'Biceps Curl', 'muscle': 'Biceps'},
  {'name': 'Hammer Curl', 'muscle': 'Biceps'},
  {'name': 'Squat', 'muscle': 'Quads'},
  {'name': 'Leg Press', 'muscle': 'Quads'},
  {'name': 'Romanian Deadlift', 'muscle': 'Hamstrings'},
  {'name': 'Leg Curl', 'muscle': 'Hamstrings'},
  {'name': 'Calf Raise', 'muscle': 'Calves'},
  {'name': 'Plank', 'muscle': 'Core'},
  {'name': 'Crunches', 'muscle': 'Core'},
];

class WorkoutPlansPage extends StatefulWidget {
  final bool startFirstPlan;
  const WorkoutPlansPage({super.key, this.startFirstPlan = false});

  @override
  State<WorkoutPlansPage> createState() => _WorkoutPlansPageState();
}

class _WorkoutPlansPageState extends State<WorkoutPlansPage> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  bool _handledStart = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final plans = await loadCustomWorkoutPlans();
    var changed = false;
    try {
      final records = await _fitCoreLoadExerciseRecords();
      final byId = <String, Map<String, dynamic>>{};
      final byName = <String, List<Map<String, dynamic>>>{};
      for (final row in records) {
        final id = (row['id'] ?? '').toString();
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (id.isNotEmpty) byId[id] = row;
        if (name.isNotEmpty) byName.putIfAbsent(name, () => []).add(row);
      }
      for (final plan in plans) {
        final exerciseList = plan['exercises'] as List? ?? <dynamic>[];
        for (final rawExercise in exerciseList) {
          if (rawExercise is! Map) continue;
          final exercise = rawExercise;
          Map<String, dynamic>? record = byId[(exercise['datasetId'] ?? '').toString()];
          if (record == null) {
            var name = (exercise['name'] ?? '').toString().trim().toLowerCase();
            final equipment = (exercise['equipment'] ?? '').toString().trim().toLowerCase();
            final legacy = <String, String>{
              'bench press': equipment.contains('dumbbell') ? 'dumbbell bench press' : 'barbell bench press',
              'incline dumbbell press': 'dumbbell incline bench press',
              'shoulder press': 'dumbbell seated shoulder press',
              'lateral raise': 'dumbbell lateral raise',
              'triceps pushdown': 'cable triceps pushdown (v-bar)',
              'pull ups': 'pull up (neutral grip)',
              'lat pulldown': 'cable lat pulldown full range of motion',
              'seated cable row': 'cable seated row',
              'biceps curl': 'dumbbell biceps curl',
              'hammer curl': 'dumbbell hammer curl',
              'squat': 'barbell front squat',
              'leg press': 'sled 45° leg press (side pov)',
              'romanian deadlift': 'barbell romanian deadlift',
              'leg curl': 'lever lying leg curl',
              'calf raise': 'barbell standing calf raise',
            };
            name = legacy[name] ?? name;
            final candidates = byName[name] ?? <Map<String, dynamic>>[];
            if (equipment.isNotEmpty) {
              for (final candidate in candidates) {
                if ((candidate['equipment'] ?? '').toString().trim().toLowerCase() == equipment) {
                  record = candidate;
                  break;
                }
              }
            }
            record ??= candidates.length == 1 ? candidates.first : null;
          }
          if (record == null) continue;
          for (final key in ['datasetId', 'media_id', 'image', 'gif_url', 'equipment', 'body_part', 'target']) {
            final value = key == 'datasetId' ? record['id'] : record[key];
            if (value != null && value.toString().trim().isNotEmpty && exercise[key] != value) {
              exercise[key] = value;
              changed = true;
            }
          }
          if (exercise['name'] != record['name']) {
            exercise['name'] = record['name'];
            changed = true;
          }
        }
      }
      if (changed) await saveCustomWorkoutPlans(plans);
    } catch (error) {
      debugPrint('Plan dataset media hydration error: $error');
    }
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _loading = false;
    });
    if (widget.startFirstPlan && !_handledStart) {
      _handledStart = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_plans.isNotEmpty) {
          _openPlan(_plans.first, start: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Create a workout plan first.')),
          );
        }
      });
    }
  }

  Future<void> _createPlan() async {
    List<Map<String, dynamic>> datasetExercises = [];
    try {
      datasetExercises = await _fitCoreLoadExerciseRecords();
    } catch (error) {
      debugPrint('Workout plan dataset load error: $error');
    }
    if (!mounted) return;

    final datasetByName = <String, Map<String, dynamic>>{};
    for (final record in datasetExercises) {
      final name = (record['name'] ?? '').toString().trim().toLowerCase();
      final gif = (record['gif_url'] ?? '').toString().trim();
      final image = (record['image'] ?? '').toString().trim();
      if (name.isNotEmpty && gif.isNotEmpty && image.isNotEmpty && (record['id'] ?? '').toString().trim().isNotEmpty) {
        datasetByName.putIfAbsent(name, () => record);
      }
    }

    final templates = <Map<String, dynamic>>[
      {
        'split': 'Push', 'name': 'Push Day', 'description': 'Chest • Shoulders • Triceps',
        'exercises': ['barbell bench press', 'dumbbell incline bench press', 'dumbbell seated shoulder press', 'dumbbell lateral raise', 'cable triceps pushdown (v-bar)'],
      },
      {
        'split': 'Pull', 'name': 'Pull Day', 'description': 'Back • Biceps • Rear delts',
        'exercises': ['pull up (neutral grip)', 'cable lat pulldown full range of motion', 'cable seated row', 'dumbbell bent over row', 'dumbbell rear delt raise', 'dumbbell biceps curl', 'dumbbell hammer curl'],
      },
      {
        'split': 'Legs', 'name': 'Leg Day', 'description': 'Quads • Hamstrings • Glutes • Calves',
        'exercises': ['barbell front squat', 'sled 45° leg press (side pov)', 'barbell romanian deadlift', 'lever lying leg curl', 'barbell standing calf raise'],
      },
      {
        'split': 'Upper', 'name': 'Upper Body', 'description': 'Chest • Back • Shoulders • Arms',
        'exercises': ['barbell bench press', 'cable lat pulldown full range of motion', 'dumbbell seated shoulder press', 'cable seated row', 'dumbbell biceps curl', 'cable triceps pushdown (v-bar)'],
      },
      {
        'split': 'Lower', 'name': 'Lower Body', 'description': 'Quads • Hamstrings • Glutes • Calves',
        'exercises': ['barbell front squat', 'barbell romanian deadlift', 'sled 45° leg press (side pov)', 'lever lying leg curl', 'barbell standing calf raise'],
      },
      {
        'split': 'Full Body', 'name': 'Full Body', 'description': 'A complete full-body session',
        'exercises': ['barbell front squat', 'barbell bench press', 'cable lat pulldown full range of motion', 'barbell romanian deadlift', 'dumbbell seated shoulder press', 'dumbbell biceps curl'],
      },
      {
        'split': 'Bro Split', 'name': 'Bro Split • Chest Day', 'description': 'Chest-focused day from a classic bro split',
        'exercises': ['barbell bench press', 'barbell incline bench press', 'dumbbell decline bench press', 'cable bench press', 'cable one arm decline chest fly'],
      },
    ];

    for (final template in templates) {
      final names = (template['exercises'] as List).cast<String>();
      template['exerciseRecords'] = names
          .map((name) => datasetByName[name.toLowerCase()])
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: 520,
          height: MediaQuery.of(dialogContext).size.height * .78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CHOOSE A WORKOUT PLAN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                          SizedBox(height: 5),
                          Text('Select a split to view its exercise list', style: TextStyle(color: muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: templates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    final exerciseNames = (template['exercises'] as List).cast<String>();
                    final exerciseRecords = (template['exerciseRecords'] as List).whereType<Map<String, dynamic>>().toList();
                    final displayNames = exerciseRecords.map((record) => '${record['name']} (${record['equipment']})').toList();
                    return Material(
                      color: bg,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pop(dialogContext, template),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF00D4FF).withOpacity(.28), width: 1.2),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fitCoreSplitMusclePreview(
                                template['split'],
                                width: 106,
                                height: 126,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${template['name']}',
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                          ),
                                        ),
                                        _fitCoreSplitBadge(template['split'], size: 34),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${template['description']}',
                                      style: const TextStyle(color: muted, fontSize: 11.5),
                                    ),
                                    const SizedBox(height: 9),
                                    Text(
                                      '${exerciseRecords.length} exercises  •  ${displayNames.join('  ·  ')}',
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, height: 1.35),
                                    ),
                                    if (exerciseRecords.length != exerciseNames.length) ...[
                                      const SizedBox(height: 5),
                                      const Text(
                                        'Some dataset entries could not be matched',
                                        style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                                      ),
                                    ],
                                    const SizedBox(height: 9),
                                    const Text(
                                      '1 set each  •  Add kg, reps & sets later',
                                      style: TextStyle(color: Color(0xFF00D4FF), fontSize: 10, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Icon(Icons.add_circle_rounded, color: Color(0xFF00D4FF), size: 23),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;

    final selectedRecords = (selected['exerciseRecords'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList() ?? <Map<String, dynamic>>[];
    if (selectedRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not match this split to exercise media in the dataset.')),
      );
      return;
    }
    final planExercises = selectedRecords.map((record) {
      final name = (record['name'] ?? '').toString();
      final target = (record['target'] ?? record['body_part'] ?? selected['split']).toString();
      return <String, dynamic>{
        'datasetId': record['id'],
        'name': name,
        'target': target,
        'body_part': record['body_part'],
        'equipment': record['equipment'],
        'media_id': record['media_id'],
        'image': record['image'],
        'gif_url': record['gif_url'],
        'sets': 1,
        'reps': 0,
        'weight': 0.0,
        'actualSets': <Map<String, dynamic>>[],
        'actualReps': <int>[],
        'setDetails': <Map<String, dynamic>>[
          {'reps': 0, 'weight': 0.0, 'done': false},
        ],
        'done': false,
      };
    }).toList();

    final plan = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': selected['name'],
      'split': selected['split'],
      'exercises': planExercises,
      'createdAt': DateTime.now().toIso8601String(),
    };
    final updated = [..._plans, plan];
    await saveCustomWorkoutPlans(updated);
    if (!mounted) return;
    setState(() => _plans = updated);
    _openPlan(plan);
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        title: const Text('Delete plan?'),
        content: Text('Delete "${plan['name']}" and its saved exercises?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final updated = _plans
        .where((item) => '${item['id']}' != '${plan['id']}')
        .toList();
    await saveCustomWorkoutPlans(updated);
    if (mounted) setState(() => _plans = updated);
  }

  Future<void> _openPlan(Map<String, dynamic> plan, {bool start = false, bool addExerciseImmediately = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutPlanDetailPage(
          plan: Map<String, dynamic>.from(plan),
          onPlanChanged: (updatedPlan) async {
            final updated = _plans.map((item) {
              return '${item['id']}' == '${updatedPlan['id']}'
                  ? updatedPlan
                  : item;
            }).toList();
            await saveCustomWorkoutPlans(updated);
            if (mounted) setState(() => _plans = updated);
          },
          startImmediately: start,
          addExerciseImmediately: addExerciseImmediately,
        ),
      ),
    );
    await _loadPlans();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('WORKOUT PLANS',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: lime,
        foregroundColor: Colors.black,
        onPressed: _createPlan,
        icon: const Icon(Icons.add),
        label: const Text('CREATE PLAN', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: lime))
          : _plans.isEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.view_list_rounded, color: Color(0xFF00D4FF), size: 48),
              const SizedBox(height: 16),
              const Text('No custom plans yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Create your first split, add exercises, and set your own sets, reps and weights.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _createPlan,
                icon: const Icon(Icons.add),
                label: const Text('Create workout'),
              ),
            ],
          ),
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final plan = _plans[index];
          final exercises = plan['exercises'] is List
              ? (plan['exercises'] as List).length
              : 0;
          return Container(
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: _fitCoreSplitMusclePreview(
                plan['split'],
                width: 92,
                height: 76,
              ),
              title: Row(
                children: [
                  Expanded(child: Text('${plan['name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Icon(_fitCoreSplitIcon(plan['split']), color: const Color(0xFF00D4FF), size: 20),
                ],
              ),
              subtitle: Text('${plan['split']} • $exercises exercises',
                  style: const TextStyle(color: muted)),
              onTap: () => _openPlan(plan),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _openPlan(plan);
                  if (value == 'delete') _deletePlan(plan);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Open / Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class WorkoutPlanDetailPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final Future<void> Function(Map<String, dynamic>) onPlanChanged;
  final bool startImmediately;
  final bool addExerciseImmediately;

  const WorkoutPlanDetailPage({
    super.key,
    required this.plan,
    required this.onPlanChanged,
    this.startImmediately = false,
    this.addExerciseImmediately = false,
  });

  @override
  State<WorkoutPlanDetailPage> createState() => _WorkoutPlanDetailPageState();
}

class _WorkoutPlanDetailPageState extends State<WorkoutPlanDetailPage> {
  late Map<String, dynamic> _plan;
  bool _startedAuto = false;
  bool _startedAddingExercise = false;

  List<Map<String, dynamic>> get _exercises {
    final raw = _plan['exercises'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  @override
  void initState() {
    super.initState();
    _plan = Map<String, dynamic>.from(widget.plan);
    _plan['exercises'] = _exercises;
    _attachExerciseMedia();
    if (widget.startImmediately && !_startedAuto) {
      _startedAuto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startWorkout();
      });
    }
    if (widget.addExerciseImmediately && !_startedAddingExercise) {
      _startedAddingExercise = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addExercise();
      });
    }
  }

  Future<void> _attachExerciseMedia() async {
    try {
      final records = await _fitCoreLoadExerciseRecords();
      final byId = <String, Map<String, dynamic>>{};
      final byName = <String, List<Map<String, dynamic>>>{};
      for (final row in records) {
        final id = (row['id'] ?? '').toString();
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (id.isNotEmpty) byId[id] = row;
        if (name.isNotEmpty) byName.putIfAbsent(name, () => []).add(row);
      }
      var changed = false;
      final list = _plan['exercises'] as List? ?? <dynamic>[];
      for (final rawExercise in list) {
        if (rawExercise is! Map) continue;
        final exercise = rawExercise;
        Map<String, dynamic>? record;
        final datasetId = (exercise['datasetId'] ?? '').toString();
        if (datasetId.isNotEmpty) record = byId[datasetId];
        if (record == null) {
          final name = (exercise['name'] ?? '').toString().trim().toLowerCase();
          final candidates = byName[name] ?? <Map<String, dynamic>>[];
          final equipment = (exercise['equipment'] ?? '').toString().trim().toLowerCase();
          if (equipment.isNotEmpty) {
            for (final candidate in candidates) {
              if ((candidate['equipment'] ?? '').toString().trim().toLowerCase() == equipment) {
                record = candidate;
                break;
              }
            }
          } else if (candidates.length == 1) {
            record = candidates.first;
          }
        }
        if (record == null) continue;
        for (final key in ['datasetId', 'media_id', 'image', 'gif_url', 'equipment', 'body_part', 'target']) {
          final value = key == 'datasetId' ? record['id'] : record[key];
          if (value != null && value.toString().trim().isNotEmpty && exercise[key] != value) {
            exercise[key] = value;
            changed = true;
          }
        }
      }
      if (changed && mounted) {
        setState(() {});
        await widget.onPlanChanged(_plan);
      }
    } catch (error) {
      debugPrint('Exercise dataset media mapping error: $error');
    }
  }

  Future<void> _savePlan() async {
    await widget.onPlanChanged(_plan);
  }

  Future<void> _renamePlan() async {
    final controller = TextEditingController(text: '${_plan['name']}');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        title: const Text('Rename plan'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    setState(() => _plan['name'] = name);
    await _savePlan();
  }

  Future<void> _addExercise() async {
    final pickedExercise = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const TrainerPage(selectMode: true)),
    );
    if (pickedExercise == null || !mounted) return;

    String valueOf(dynamic value) {
      if (value is Map) return (value['en'] ?? (value.values.isEmpty ? '' : value.values.first)).toString();
      if (value is List) return value.join(', ');
      return (value ?? '').toString();
    }

    final name = valueOf(pickedExercise['name']).trim().isEmpty
        ? 'Exercise' : valueOf(pickedExercise['name']);
    final target = valueOf(pickedExercise['target']).trim().isNotEmpty
        ? valueOf(pickedExercise['target'])
        : valueOf(pickedExercise['body_part']);
    final exercise = <String, dynamic>{
      'name': name,
      'target': target.isEmpty ? 'General' : target,
      'equipment': valueOf(pickedExercise['equipment']),
      'media_id': pickedExercise['media_id'],
      'datasetId': pickedExercise['datasetId'],
      'image': pickedExercise['image'],
      'gif_url': pickedExercise['gif_url'],
      'body_part': pickedExercise['body_part'],
      'sets': 1,
      'reps': 0,
      'weight': 0.0,
      'actualSets': <Map<String, dynamic>>[],
      'actualReps': <int>[],
      'setDetails': <Map<String, dynamic>>[
        {'reps': 0, 'weight': 0.0, 'done': false},
      ],
      'done': false,
    };
    setState(() => (_plan['exercises'] as List).add(exercise));
    await _savePlan();
  }

  Future<void> _addSetToPlan(int index) async {
    final rawExercises = _plan['exercises'] as List? ?? <dynamic>[];
    if (index < 0 || index >= rawExercises.length || rawExercises[index] is! Map) return;
    final exercise = Map<String, dynamic>.from(rawExercises[index] as Map);
    final planned = ((exercise['sets'] as num?)?.toInt() ?? 3).clamp(1, 100);
    final reps = (exercise['reps'] as num?)?.toInt() ?? 10;
    final weight = (exercise['weight'] as num?)?.toDouble() ?? 0.0;
    final details = (exercise['setDetails'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList();
    while (details.length < planned) {
      details.add({'reps': reps, 'weight': weight, 'done': false});
    }
    final last = details.isNotEmpty ? details.last : <String, dynamic>{};
    details.add({
      'reps': (last['reps'] as num?)?.toInt() ?? reps,
      'weight': (last['weight'] as num?)?.toDouble() ?? weight,
      'done': false,
    });
    exercise['setDetails'] = details;
    exercise['sets'] = details.length;
    rawExercises[index] = exercise;
    setState(() => _plan['exercises'] = rawExercises);
    await _savePlan();
  }

  Future<void> _removeExercise(int index) async {
    setState(() => (_plan['exercises'] as List).removeAt(index));
    await _savePlan();
  }

  Future<void> _startWorkout() async {
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise to this plan first.')),
      );
      return;
    }
    final activeWorkout = await loadFitCoreActiveWorkout();
    if (activeWorkout != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A workout is already active: ${activeWorkout['planName'] ?? 'Workout'}. Resume it from Dashboard.'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomWorkoutSessionPage(
          planName: '${_plan['name']}',
          exercises: _exercises.map((item) => Map<String, dynamic>.from(item)).toList(),
          planId: '${_plan['id']}',
        ),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workout saved to History and Analysis.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: Text('${_plan['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Rename plan', onPressed: _renamePlan, icon: const Icon(Icons.edit_outlined, color: lime)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00D4FF).withOpacity(.18)),
              ),
              child: Row(
                children: [
                  _fitCoreSplitMusclePreview(_plan['split'], width: 112, height: 88),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_plan['split']} SPLIT', style: const TextStyle(
                          color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1,
                        )),
                        const SizedBox(height: 5),
                        const Text('TARGET MUSCLES', style: TextStyle(
                          color: muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .8,
                        )),
                        const SizedBox(height: 3),
                        Text(
                          _fitCoreSplitMuscleGroups(_plan['split']).map((group) => group[0].toUpperCase() + group.substring(1)).join(' • '),
                          style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.35),
                        ),
                        const SizedBox(height: 5),
                        Text('${_exercises.length} exercises', style: const TextStyle(color: muted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _exercises.isEmpty
                ? const Center(child: Text('Add exercises to build your plan.', style: TextStyle(color: muted)))
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: _exercises.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final exercise = _exercises[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      _fitCoreExerciseThumbnail(exercise, size: 72),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${exercise['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Target: ${exercise['target'] ?? 'General'}', style: const TextStyle(color: lime, fontSize: 11)),
                            const SizedBox(height: 5),
                            Text('${exercise['sets']} set${((exercise['sets'] as num?)?.toInt() ?? 1) == 1 ? '' : 's'} • Enter kg & reps during workout',
                                style: const TextStyle(color: muted, fontSize: 12)),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _addSetToPlan(index),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: lime,
                                  side: BorderSide(color: lime.withOpacity(0.35)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('ADD SET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => _removeExercise(index), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _addExercise,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: lime,
                          side: BorderSide(color: lime.withOpacity(0.45)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('ADD EXERCISE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _startWorkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: lime,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('START WORKOUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutExercisePickerPage extends StatefulWidget {
  const WorkoutExercisePickerPage({super.key});

  @override
  State<WorkoutExercisePickerPage> createState() => _WorkoutExercisePickerPageState();
}

class _WorkoutExercisePickerPageState extends State<WorkoutExercisePickerPage> {
  List<Map<String, dynamic>> _allExercises = [];
  bool _loading = true;
  String _query = '';
  String _selectedTarget = 'All muscles';
  final TextEditingController _searchController = TextEditingController();

  String _value(dynamic value) {
    if (value is Map) return (value['en'] ?? (value.values.isEmpty ? '' : value.values.first)).toString();
    if (value is List) return value.join(', ');
    return (value ?? '').toString();
  }

  String _target(Map<String, dynamic> exercise) {
    final target = _value(exercise['target']).trim();
    if (target.isNotEmpty) return target;
    final group = _value(exercise['muscle_group']).trim();
    if (group.isNotEmpty) return group;
    return _value(exercise['body_part']).trim().isEmpty
        ? 'General'
        : _value(exercise['body_part']).trim();
  }

  List<String> get _targets {
    final values = _allExercises.map(_target).where((value) => value.isNotEmpty).toSet().toList()..sort();
    return ['All muscles', ...values];
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _query.toLowerCase().trim();
    return _allExercises.where((exercise) {
      final name = _value(exercise['name']).toLowerCase();
      final target = _target(exercise).toLowerCase();
      final bodyPart = _value(exercise['body_part']).toLowerCase();
      final equipment = _value(exercise['equipment']).toLowerCase();
      final matchesTarget = _selectedTarget == 'All muscles' || _target(exercise) == _selectedTarget;
      final matchesQuery = query.isEmpty || '$name $target $bodyPart $equipment'.contains(query);
      return matchesTarget && matchesQuery;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final jsonString = await rootBundle.loadString('assets/exercises/exercises-dataset-main/data/exercises.json');
      final decoded = jsonDecode(jsonString) as List;
      _allExercises = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (error) {
      debugPrint('Workout exercise picker load error: $error');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(Map<String, dynamic> exercise) {
    Navigator.of(context).pop({
      'name': _value(exercise['name']),
      'target': _target(exercise),
      'body_part': _value(exercise['body_part']),
      'equipment': _value(exercise['equipment']),
      'datasetId': exercise['id'],
      'media_id': exercise['media_id'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('CHOOSE EXERCISE', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: lime))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search exercise or muscle target',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty ? null : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () { _searchController.clear(); setState(() => _query = ''); },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              value: _targets.contains(_selectedTarget) ? _selectedTarget : 'All muscles',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Muscle target'),
              items: _targets.map((target) => DropdownMenuItem(value: target, child: Text(target))).toList(),
              onChanged: (value) => setState(() => _selectedTarget = value ?? 'All muscles'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Text('Exercise library', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${items.length} exercises', style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No exercises found for this muscle target.', style: TextStyle(color: muted)))
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final exercise = items[index];
                final target = _target(exercise);
                return Container(
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: _fitCoreExerciseThumbnail(exercise, size: 54),
                    title: Text(_value(exercise['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text('Target: $target • ${_value(exercise['equipment'])}', style: const TextStyle(color: muted, fontSize: 12)),
                    ),
                    trailing: const Icon(Icons.add_circle_outline, color: lime),
                    onTap: () => _select(exercise),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomWorkoutSessionPage extends StatefulWidget {
  final String planName;
  final String? planId;
  final List<Map<String, dynamic>> exercises;
  final String? initialStartedAt;
  final String? initialEffort;

  const CustomWorkoutSessionPage({
    super.key,
    required this.planName,
    required this.exercises,
    this.planId,
    this.initialStartedAt,
    this.initialEffort,
  });

  @override
  State<CustomWorkoutSessionPage> createState() => _CustomWorkoutSessionPageState();
}

class _CustomWorkoutSessionPageState extends State<CustomWorkoutSessionPage> {
  late List<Map<String, dynamic>> _exercises;
  late DateTime _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _stopwatchTicker;
  String _workoutEffort = 'General';
  double? _bodyWeightKg;

  double get _effortMet {
    switch (_workoutEffort) {
      case 'Moderate': return 5.0;
      case 'Vigorous': return 6.0;
      default: return 3.5;
    }
  }

  double? get _liveCaloriesBurned {
    final weight = _bodyWeightKg;
    if (weight == null || weight <= 0) return null;
    return fitCoreEstimateWorkoutCalories(
      bodyWeightKg: weight,
      durationSeconds: _elapsed.inSeconds,
      metValue: _effortMet,
    );
  }

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.tryParse(widget.initialStartedAt ?? '') ?? DateTime.now();
    const availableEfforts = ['General', 'Moderate', 'Vigorous'];
    _workoutEffort = availableEfforts.contains(widget.initialEffort) ? widget.initialEffort! : 'General';
    _loadWorkoutCalorieProfile();
    _exercises = widget.exercises.map((item) {
      final copy = Map<String, dynamic>.from(item);
      copy['done'] = copy['done'] == true;
      final legacyReps = copy['actualReps'] is List
          ? List<int>.from(copy['actualReps'])
          : <int>[];
      if (copy['actualSets'] is List) {
        copy['actualSets'] = (copy['actualSets'] as List)
            .whereType<Map>()
            .map((set) => Map<String, dynamic>.from(set))
            .toList();
      } else {
        final legacyWeight = (copy['weight'] as num?)?.toDouble() ?? 0.0;
        copy['actualSets'] = legacyReps
            .map((reps) => <String, dynamic>{'reps': reps, 'weight': legacyWeight})
            .toList();
      }
      copy['actualReps'] = (copy['actualSets'] as List)
          .map((set) => (set['reps'] as num?)?.toInt() ?? 0)
          .toList();

      final existingSetDetails = copy['setDetails'] is List
          ? (copy['setDetails'] as List)
          .whereType<Map>()
          .map((set) => Map<String, dynamic>.from(set))
          .toList()
          : <Map<String, dynamic>>[];
      final plannedSets = ((copy['sets'] as num?)?.toInt() ?? 3).clamp(1, 100);
      final targetReps = (copy['reps'] as num?)?.toInt() ?? 10;
      final targetWeight = (copy['weight'] as num?)?.toDouble() ?? 0.0;
      while (existingSetDetails.length < plannedSets) {
        final setIndex = existingSetDetails.length;
        final logged = (copy['actualSets'] as List);
        final loggedSet = setIndex < logged.length && logged[setIndex] is Map
            ? Map<String, dynamic>.from(logged[setIndex] as Map)
            : <String, dynamic>{};
        existingSetDetails.add({
          'reps': (loggedSet['reps'] as num?)?.toInt() ?? targetReps,
          'weight': (loggedSet['weight'] as num?)?.toDouble() ?? targetWeight,
          'done': setIndex < logged.length,
        });
      }
      if (existingSetDetails.length > plannedSets) {
        existingSetDetails.removeRange(plannedSets, existingSetDetails.length);
      }
      for (var setIndex = 0; setIndex < existingSetDetails.length; setIndex++) {
        existingSetDetails[setIndex]['done'] = setIndex <
            (copy['actualSets'] as List).length;
      }
      copy['sets'] = plannedSets;
      copy['setDetails'] = existingSetDetails;
      return copy;
    }).toList();
    _elapsed = DateTime.now().difference(_startedAt);
    _persistActiveWorkout();
    _stopwatchTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
  }

  Future<void> _loadWorkoutCalorieProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final rawWeight = prefs.get('fitcore_profile_weight');
    final savedWeight = rawWeight is num
        ? rawWeight.toDouble()
        : double.tryParse(rawWeight?.toString() ?? '');
    if (!mounted) return;
    setState(() => _bodyWeightKg = (savedWeight != null && savedWeight >= 20 && savedWeight <= 300) ? savedWeight : null);
  }

  Future<double?> _ensureBodyWeightForCalories() async {
    if (_bodyWeightKg != null && _bodyWeightKg! >= 20) return _bodyWeightKg;
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        title: const Text('Add body weight'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('FitCore uses your body weight to estimate workout calories.'),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Body weight (kg)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Skip')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: lime, foregroundColor: Colors.black),
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 20 || value > 300) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('SAVE WEIGHT'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fitcore_profile_weight', result.toString());
    if (mounted) setState(() => _bodyWeightKg = result);
    return result;
  }

  @override
  void dispose() {
    _stopwatchTicker?.cancel();
    super.dispose();
  }

  Future<void> _persistActiveWorkout() async {
    final workout = {
      'planName': widget.planName,
      'planId': widget.planId,
      'startedAt': _startedAt.toIso8601String(),
      'workoutEffort': _workoutEffort,
      'exercises': _exercises.map((item) => Map<String, dynamic>.from(item)).toList(),
    };
    await saveFitCoreActiveWorkout(workout);
    await _updateFitCoreWorkoutNotification(workout);
  }

  String get _formattedTime {
    final totalSeconds = _elapsed.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _saveEditsToPlan() async {
    final id = widget.planId;
    if (id == null || id.isEmpty) return;
    final plans = await loadCustomWorkoutPlans();
    final planIndex = plans.indexWhere((plan) => '${plan['id']}' == id);
    if (planIndex < 0) return;
    plans[planIndex]['exercises'] = _exercises.map((item) {
      final copy = Map<String, dynamic>.from(item);
      copy.remove('done');
      return copy;
    }).toList();
    await saveCustomWorkoutPlans(plans);
  }

  Future<void> _editExercise(int index) async {
    final item = _exercises[index];
    final setsController = TextEditingController(text: '${item['sets'] ?? 3}');
    final repsController = TextEditingController(text: '${item['reps'] ?? 10}');
    final weightController = TextEditingController(text: '${item['weight'] ?? 0}');
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        title: Text('Edit ${item['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: setsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sets')),
              TextField(controller: repsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reps')),
              TextField(controller: weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final sets = int.tryParse(setsController.text.trim());
              final reps = int.tryParse(repsController.text.trim());
              final weight = double.tryParse(weightController.text.trim());
              if (sets == null || sets < 1 || reps == null || reps < 1 || weight == null || weight < 0) return;
              Navigator.pop(dialogContext, {'sets': sets, 'reps': reps, 'weight': weight});
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
    setsController.dispose();
    repsController.dispose();
    weightController.dispose();
    if (updated == null || !mounted) return;
    setState(() {
      item['sets'] = updated['sets'];
      item['reps'] = updated['reps'];
      item['weight'] = updated['weight'];
      final actualSets = List<Map<String, dynamic>>.from(
        (item['actualSets'] as List? ?? const []).map((set) => Map<String, dynamic>.from(set)),
      );
      if (actualSets.length > updated['sets']) {
        actualSets.removeRange(updated['sets'], actualSets.length);
      }
      item['actualSets'] = actualSets;
      item['actualReps'] = actualSets.map((set) => (set['reps'] as num?)?.toInt() ?? 0).toList();
      final setDetails = (item['setDetails'] as List? ?? const [])
          .whereType<Map>()
          .map((set) => Map<String, dynamic>.from(set))
          .toList();
      while (setDetails.length < updated['sets']) {
        setDetails.add({
          'reps': updated['reps'],
          'weight': updated['weight'],
          'done': false,
        });
      }
      if (setDetails.length > updated['sets']) {
        setDetails.removeRange(updated['sets'], setDetails.length);
      }
      for (var i = 0; i < setDetails.length; i++) {
        if (i < actualSets.length) {
          setDetails[i]['reps'] = actualSets[i]['reps'];
          setDetails[i]['weight'] = actualSets[i]['weight'];
        } else {
          setDetails[i]['reps'] = updated['reps'];
          setDetails[i]['weight'] = updated['weight'];
        }
        setDetails[i]['done'] = i < actualSets.length;
      }
      item['setDetails'] = setDetails;
      item['done'] = actualSets.length >= updated['sets'];
    });
    await _saveEditsToPlan();
    await _persistActiveWorkout();
  }

  Future<void> _logSet(int index) async {
    final item = _exercises[index];
    final logged = List<Map<String, dynamic>>.from(
      (item['actualSets'] as List? ?? const []).map((set) => Map<String, dynamic>.from(set)),
    );
    final plannedSets = (item['sets'] as num?)?.toInt() ?? 1;
    if (logged.length >= plannedSets) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All planned sets logged. Edit sets if you want to add more.')),
      );
      return;
    }

    final repsController = TextEditingController(text: '${item['reps'] ?? 10}');
    final weightController = TextEditingController(text: '${item['weight'] ?? 0}');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        title: Text('Log set ${logged.length + 1} • ${item['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repsController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Actual reps completed'),
            ),
            TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight used (kg)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final reps = int.tryParse(repsController.text.trim());
              final weight = double.tryParse(weightController.text.trim());
              if (reps != null && reps >= 0 && weight != null && weight >= 0) {
                Navigator.pop(ctx, {'reps': reps, 'weight': weight});
              }
            },
            child: const Text('Save set'),
          ),
        ],
      ),
    );
    repsController.dispose();
    weightController.dispose();
    if (result == null || !mounted) return;

    logged.add({'reps': result['reps'], 'weight': result['weight']});
    setState(() {
      item['actualSets'] = logged;
      item['actualReps'] = logged.map((set) => (set['reps'] as num?)?.toInt() ?? 0).toList();
      item['done'] = logged.length >= plannedSets;
    });
    await _persistActiveWorkout();
  }

  Future<void> _editLoggedSet(int exerciseIndex, int setIndex) async {
    final item = _exercises[exerciseIndex];
    final actualSets = List<Map<String, dynamic>>.from(
      (item['actualSets'] as List? ?? const []).map((set) => Map<String, dynamic>.from(set)),
    );
    if (setIndex < 0 || setIndex >= actualSets.length) return;
    final current = actualSets[setIndex];
    final repsController = TextEditingController(text: '${current['reps'] ?? 0}');
    final weightController = TextEditingController(text: '${current['weight'] ?? item['weight'] ?? 0}');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        title: Text('Edit set ${setIndex + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: repsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reps')),
            TextField(controller: weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final reps = int.tryParse(repsController.text.trim());
              final weight = double.tryParse(weightController.text.trim());
              if (reps != null && reps >= 0 && weight != null && weight >= 0) {
                Navigator.pop(ctx, {'reps': reps, 'weight': weight});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    repsController.dispose();
    weightController.dispose();
    if (result == null || !mounted) return;
    actualSets[setIndex] = {'reps': result['reps'], 'weight': result['weight']};
    setState(() {
      item['actualSets'] = actualSets;
      item['actualReps'] = actualSets.map((set) => (set['reps'] as num?)?.toInt() ?? 0).toList();
    });
    await _persistActiveWorkout();
  }

  Future<void> _persistSetDetails(int exerciseIndex) async {
    final item = _exercises[exerciseIndex];
    final details = item['setDetails'] is List
        ? (item['setDetails'] as List)
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList()
        : <Map<String, dynamic>>[];
    item['sets'] = details.length;
    if (details.isNotEmpty) {
      item['reps'] = (details.first['reps'] as num?)?.toInt() ?? item['reps'] ?? 10;
      item['weight'] = (details.first['weight'] as num?)?.toDouble() ?? item['weight'] ?? 0.0;
    }
    await _persistActiveWorkout();
    await _saveEditsToPlan();
  }

  Future<void> _addSet(int exerciseIndex) async {
    final item = _exercises[exerciseIndex];
    final details = (item['setDetails'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList();
    final last = details.isNotEmpty ? details.last : <String, dynamic>{};
    details.add({
      'reps': (last['reps'] as num?)?.toInt() ?? (item['reps'] as num?)?.toInt() ?? 10,
      'weight': (last['weight'] as num?)?.toDouble() ?? (item['weight'] as num?)?.toDouble() ?? 0.0,
      'done': false,
    });
    setState(() {
      item['setDetails'] = details;
      item['sets'] = details.length;
      item['done'] = false;
    });
    await _persistSetDetails(exerciseIndex);
  }

  Future<void> _updateSetValue(int exerciseIndex, int setIndex, String field, String value) async {
    final item = _exercises[exerciseIndex];
    final details = (item['setDetails'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList();
    if (setIndex < 0 || setIndex >= details.length) return;
    if (field == 'reps') {
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 0) return;
      details[setIndex]['reps'] = parsed;
    } else {
      final parsed = double.tryParse(value);
      if (parsed == null || parsed < 0) return;
      details[setIndex]['weight'] = parsed;
    }
    setState(() {
      item['setDetails'] = details;
      if (setIndex == 0) {
        item[field] = field == 'reps'
            ? details[setIndex]['reps']
            : details[setIndex]['weight'];
      }
    });
    await _persistSetDetails(exerciseIndex);
  }

  Future<void> _toggleSetComplete(int exerciseIndex, int setIndex) async {
    final item = _exercises[exerciseIndex];
    final details = (item['setDetails'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList();
    final actualSets = (item['actualSets'] as List? ?? const [])
        .whereType<Map>()
        .map((set) => Map<String, dynamic>.from(set))
        .toList();
    if (setIndex < 0 || setIndex >= details.length) return;

    if (setIndex < actualSets.length) {
      actualSets.removeAt(setIndex);
      for (var i = setIndex; i < details.length; i++) {
        details[i]['done'] = i < actualSets.length;
      }
    } else if (setIndex == actualSets.length) {
      actualSets.add({
        'reps': (details[setIndex]['reps'] as num?)?.toInt() ?? 0,
        'weight': (details[setIndex]['weight'] as num?)?.toDouble() ?? 0.0,
      });
      details[setIndex]['done'] = true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete sets in order.')),
      );
      return;
    }

    for (var i = 0; i < details.length; i++) {
      details[i]['done'] = i < actualSets.length;
    }
    setState(() {
      item['setDetails'] = details;
      item['actualSets'] = actualSets;
      item['actualReps'] = actualSets
          .map((set) => (set['reps'] as num?)?.toInt() ?? 0)
          .toList();
      item['done'] = actualSets.length >= details.length;
    });
    await _persistSetDetails(exerciseIndex);
  }

  Future<void> _addExerciseDuringWorkout() async {
    final pickedExercise = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const TrainerPage(selectMode: true)),
    );
    if (pickedExercise == null || !mounted) return;

    String valueOf(dynamic value) {
      if (value is Map) return (value['en'] ?? (value.values.isEmpty ? '' : value.values.first)).toString();
      if (value is List) return value.join(', ');
      return (value ?? '').toString();
    }

    final name = valueOf(pickedExercise['name']).trim().isEmpty
        ? 'Exercise' : valueOf(pickedExercise['name']);
    final target = valueOf(pickedExercise['target']).trim().isNotEmpty
        ? valueOf(pickedExercise['target']) : valueOf(pickedExercise['body_part']);
    final exercise = <String, dynamic>{
      'name': name,
      'target': target.isEmpty ? 'General' : target,
      'equipment': valueOf(pickedExercise['equipment']),
      'sets': 1,
      'reps': 0,
      'weight': 0.0,
      'actualSets': <Map<String, dynamic>>[],
      'actualReps': <int>[],
      'setDetails': <Map<String, dynamic>>[
        {'reps': 0, 'weight': 0.0, 'done': false},
      ],
      'done': false,
    };
    setState(() => _exercises.add(exercise));
    await _persistActiveWorkout();
    await _saveEditsToPlan();
  }

  Future<void> _showWorkoutCelebration({required bool isPr, int? caloriesBurned}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.25, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lime.withOpacity(0.12),
                    border: Border.all(color: lime.withOpacity(0.45), width: 2),
                  ),
                  child: Icon(
                    isPr ? Icons.emoji_events_rounded : Icons.check_circle_rounded,
                    color: lime,
                    size: 62,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isPr ? 'NEW PERSONAL RECORD!' : 'WORKOUT COMPLETE!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: lime, fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                isPr ? 'That’s a new best. Keep pushing!' : 'You showed up and put in the work. Great job!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.4),
              ),
              if (caloriesBurned != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: lime.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.local_fire_department_rounded, color: lime, size: 20),
                    const SizedBox(width: 8),
                    Text('EST. $caloriesBurned KCAL BURNED', style: const TextStyle(color: lime, fontWeight: FontWeight.w900, letterSpacing: .5)),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: lime, foregroundColor: Colors.black),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('LET’S GO', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finishWorkout() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        title: const Text('End workout?'),
        content: const Text('Your completed workout will be saved to history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue workout'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: lime,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('END & SAVE'),
          ),
        ],
      ),
    );
    if (shouldEnd != true || !mounted) return;

    final completed = _exercises.where((item) => item['done'] == true).map((item) {
      return {
        'name': item['name'],
        'sets': item['sets'],
        'reps': item['reps'],
        'weight': item['weight'],
        'actualReps': item['actualReps'] ?? [],
        'actualSets': item['actualSets'] ?? [],
      };
    }).toList();

    if (completed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mark at least one exercise complete first.')),
      );
      return;
    }

    final bodyWeightKg = await _ensureBodyWeightForCalories();
    if (!mounted) return;
    final estimatedCalories = bodyWeightKg == null
        ? null
        : fitCoreEstimateWorkoutCalories(
      bodyWeightKg: bodyWeightKg,
      durationSeconds: _elapsed.inSeconds,
      metValue: _effortMet,
    );

    await _saveEditsToPlan();
    final prefs = await SharedPreferences.getInstance();
    await loadWorkoutHistory();

    // Compare today's logged weights with the best previous weight for each exercise.
    final previousBest = <String, double>{};
    for (final workout in fitCoreHistory) {
      final pastExercises = workout['exercises'];
      if (pastExercises is! List) continue;
      for (final past in pastExercises.whereType<Map>()) {
        final name = '${past['name'] ?? ''}'.trim().toLowerCase();
        if (name.isEmpty) continue;
        var best = 0.0;
        final sets = past['actualSets'];
        if (sets is List) {
          for (final set in sets.whereType<Map>()) {
            final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
            if (weight > best) best = weight;
          }
        }
        final legacyWeight = (past['weight'] as num?)?.toDouble() ?? 0.0;
        if (legacyWeight > best) best = legacyWeight;
        if (best > (previousBest[name] ?? 0.0)) previousBest[name] = best;
      }
    }
    var achievedPr = false;
    for (final today in completed) {
      final name = '${today['name'] ?? ''}'.trim().toLowerCase();
      final oldBest = previousBest[name] ?? 0.0;
      final sets = today['actualSets'];
      if (sets is List) {
        for (final set in sets.whereType<Map>()) {
          final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
          if (weight > oldBest && weight > 0) achievedPr = true;
        }
      }
    }

    fitCoreHistory.add({
      'date': DateTime.now().toIso8601String(),
      'planName': widget.planName,
      'durationSeconds': _elapsed.inSeconds,
      'caloriesBurned': estimatedCalories?.round(),
      'bodyWeightKg': bodyWeightKg,
      'workoutEffort': _workoutEffort,
      'metValue': _effortMet,
      'exercises': completed,
    });
    await prefs.setString('fitcore_history', jsonEncode(fitCoreHistory));
    await clearFitCoreActiveWorkout();
    await _stopFitCoreWorkoutNotification();
    if (!mounted) return;
    await _showWorkoutCelebration(isPr: achievedPr, caloriesBurned: estimatedCalories?.round());
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _exercises.where((item) => item['done'] == true).length;
    final percent = _exercises.isEmpty ? 0.0 : completedCount / _exercises.length;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: Text(widget.planName, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: const [],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.timer_outlined, color: lime, size: 28),
                const SizedBox(width: 12),
                const Text('WORKOUT TIME', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(_formattedTime, style: const TextStyle(color: lime, fontSize: 24, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, size: 21),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'CALORIES BURNED',
                    style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .7),
                  ),
                ),
                if (_liveCaloriesBurned == null)
                  TextButton.icon(
                    onPressed: () async {
                      await _ensureBodyWeightForCalories();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: lime,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('ADD WEIGHT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                  )
                else
                  Text(
                    '${_liveCaloriesBurned!.toStringAsFixed(1)} kcal',
                    style: const TextStyle(color: lime, fontSize: 19, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
              ]),
              if (_bodyWeightKg == null) ...[
                const SizedBox(height: 2),
                const Text(
                  'Add your body weight to start the live calorie estimate.',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ] else ...[
                const SizedBox(height: 2),
                Text(
                  'Live estimate • ${_bodyWeightKg!.toStringAsFixed(1)} kg body weight',
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                const Text('EFFORT', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8)),
                const Spacer(),
                ...['General', 'Moderate', 'Vigorous'].map((effort) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(effort, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _workoutEffort == effort ? Colors.black : muted)),
                    selected: _workoutEffort == effort,
                    selectedColor: lime,
                    backgroundColor: const Color(0xFF242724),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _workoutEffort = effort);
                      _persistActiveWorkout();
                    },
                  ),
                )),
              ]),
              const SizedBox(height: 5),
              const Text('Estimate uses body weight, workout time and effort; real burn can vary.', style: TextStyle(color: muted, fontSize: 10)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(child: Text('$completedCount / ${_exercises.length} completed', style: const TextStyle(color: lime, fontWeight: FontWeight.bold))),
                Text('${(percent * 100).round()}%', style: const TextStyle(color: muted)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _exercises.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _exercises[index];
                  final done = item['done'] == true;
                  final setDetails = (item['setDetails'] as List? ?? const [])
                      .whereType<Map>()
                      .map((set) => Map<String, dynamic>.from(set))
                      .toList();
                  final loggedCount = ((item['actualSets'] as List?) ?? const []).length;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: done ? lime.withOpacity(0.35) : Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _fitCoreExerciseThumbnail(item, size: 72),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  const SizedBox(height: 5),
                                  Text('$loggedCount / ${setDetails.length} SETS COMPLETED',
                                      style: const TextStyle(color: lime, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit exercise',
                              onPressed: () => _editExercise(index),
                              icon: const Icon(Icons.edit_outlined, color: muted),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() => item['done'] = !done);
                                _persistActiveWorkout();
                              },
                              icon: Icon(done ? Icons.check_circle : Icons.circle_outlined, color: lime, size: 28),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _addSet(index),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: lime,
                              side: BorderSide(color: lime.withOpacity(0.35)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('ADD SET', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10)),
                          child: const Row(
                            children: [
                              SizedBox(width: 34, child: Text('SET', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800))),
                              Expanded(child: Text('WEIGHT (KG)', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800))),
                              Expanded(child: Text('REPS', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800))),
                              SizedBox(width: 32),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        ...List.generate(setDetails.length, (setIndex) {
                          final set = setDetails[setIndex];
                          final isLogged = setIndex < loggedCount;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text('${setIndex + 1}'.padLeft(2, '0'),
                                      style: TextStyle(color: isLogged ? lime : muted, fontWeight: FontWeight.w800, fontSize: 12)),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: TextFormField(
                                      key: ValueKey('weight-$index-$setIndex'),
                                      initialValue: '${set['weight'] ?? 0}',
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        filled: true,
                                        fillColor: const Color(0xFF242724),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                      ),
                                      onChanged: (value) => _updateSetValue(index, setIndex, 'weight', value),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: TextFormField(
                                      key: ValueKey('reps-$index-$setIndex'),
                                      initialValue: '${set['reps'] ?? 10}',
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        filled: true,
                                        fillColor: const Color(0xFF242724),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                      ),
                                      onChanged: (value) => _updateSetValue(index, setIndex, 'reps', value),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _toggleSetComplete(index, setIndex),
                                    icon: Icon(
                                      isLogged ? Icons.check_circle_rounded : Icons.circle_outlined,
                                      color: isLogged ? lime : muted,
                                      size: 25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _addExerciseDuringWorkout,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: lime,
                          side: BorderSide(color: lime.withOpacity(0.45)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('ADD EXERCISE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _finishWorkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: lime,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('FINISH WORKOUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> loadWorkoutData() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    final savedData = prefs.getString('fitcore_exercises');

    if (savedData == null) return;

    final decodedData = jsonDecode(savedData);

    if (decodedData is! List) return;

    for (final saved in decodedData) {
      if (saved is! Map) continue;

      final index = fitCoreExercises.indexWhere(
            (exercise) => exercise['name'] == saved['name'],
      );

      if (index == -1) continue;

      final exercise = fitCoreExercises[index];

      if (saved['weight'] is num) {
        exercise['weight'] =
            (saved['weight'] as num).toDouble();
      }

      if (saved['done'] is bool) {
        exercise['done'] = saved['done'];
      }
    }
  } catch (e) {
    debugPrint('Workout loading error: $e');
  }
}

Future<void> loadWorkoutHistory() async {
  final prefs = await SharedPreferences.getInstance();

  final savedHistory = prefs.getString('fitcore_history');

  if (savedHistory != null) {
    final decodedHistory = jsonDecode(savedHistory);

    fitCoreHistory.clear();
    fitCoreHistory.addAll(
      List<Map<String, dynamic>>.from(
        decodedHistory.map(
              (session) => Map<String, dynamic>.from(session),
        ),
      ),
    );
  }
}

Future<void> saveWorkoutSession() async {
  final prefs = await SharedPreferences.getInstance();

  final completedExercises = fitCoreExercises
      .where((exercise) => exercise['done'] == true)
      .map((exercise) {
    return {
      'name': exercise['name'],
      'sets': exercise['sets'],
      'reps': exercise['reps'],
      'weight': exercise['weight'],
    };
  }).toList();

  final session = {
    'date': DateTime.now().toIso8601String(),
    'exercises': completedExercises,
  };
  await loadWorkoutHistory();
  fitCoreHistory.add(session);

  await prefs.setString(
    'fitcore_history',
    jsonEncode(fitCoreHistory),
  );
}

Future<void> saveWorkoutData() async {
  final prefs = await SharedPreferences.getInstance();

  final savedExercises = fitCoreExercises.map((exercise) {
    return {
      'name': exercise['name'],
      'sets': exercise['sets'],
      'reps': exercise['reps'],
      'weight': exercise['weight'],
      'done': exercise['done'],
    };
  }).toList();

  await prefs.setString(
    'fitcore_exercises',
    jsonEncode(savedExercises),
  );
}

final List<Map<String, dynamic>> fitCoreExercises = [
  {
    'name': 'Bench Press',
    'sets': 3,
    'reps': 12,
    'weight': 40.0,
    'done': false,
  },
  {
    'name': 'Incline Dumbbell Press',
    'sets': 3,
    'reps': 10,
    'weight': 15.0,
    'done': false,
  },
  {
    'name': 'Chest Fly',
    'sets': 3,
    'reps': 12,
    'weight': 10.0,
    'done': false,
  },
  {
    'name': 'Triceps Pushdown',
    'sets': 3,
    'reps': 12,
    'weight': 20.0,
    'done': false,
  },
];
final List<Map<String, dynamic>> fitCoreHistory = [];

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  @override
  void initState() {
    super.initState();
    loadWorkoutData();
  }
  final List<Map<String, dynamic>> exercises = fitCoreExercises;



  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFF00D4FF);
    const dark = Color(0xFF171A17);
    final completedCount = exercises
        .where((exercise) => exercise['done'] == true)
        .length;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        backgroundColor: dark,
        title: const Text(
          'TODAY\'S WORKOUT',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: EdgeInsets.all(isLandscape ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isLandscape ? 12 : 18),
              decoration: BoxDecoration(
                color: const Color(0xFF292E28),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHEST & TRICEPS',
                    style: TextStyle(
                      color: lime,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$completedCount / ${exercises.length} exercises completed',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: completedCount / exercises.length,
                    color: lime,
                    backgroundColor: Colors.white12,
                  ),
                ],
              ),
            ),
            SizedBox(height: isLandscape ? 8 : 20),
            const Text(
              'EXERCISES',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: isLandscape ? 4 : 12),

            Expanded(
              child: ListView.builder(
                itemCount: fitCoreExercises.length,
                itemBuilder: (context, index) {
                  final exercise = fitCoreExercises[index];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF292E28),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                exercise['name'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  exercise['done'] = !(exercise['done'] == true);
                                });
                                saveWorkoutData();
                              },
                              icon: Icon(
                                exercise['done'] == true
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: lime,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${exercise['sets']} sets × ${exercise['reps']} reps',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Weight: ${exercise['weight']} kg',
                              style: TextStyle(
                                color: lime,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  exercise['weight'] =
                                      (exercise['weight'] as num).toDouble() + 2.5;
                                });
                                saveWorkoutData();
                              },
                              icon: Icon(Icons.add_circle_outline, color: lime),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            SizedBox(height: isLandscape ? 6 : 12),

            SizedBox(
              width: double.infinity,
              height: isLandscape ? 44 : 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: lime,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  if (completedCount == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Complete at least one exercise first!',
                        ),
                      ),
                    );
                    return;
                  }

                  await saveWorkoutSession();
                  await saveWorkoutData();

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Workout saved to History!'),
                    ),
                  );
                },
                child: const Text(
                  'SAVE WORKOUT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),


          ],
        ),
      ),
    );
  }
}

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    await loadWorkoutHistory();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  double _asDouble(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  DateTime? _sessionDate(Map<String, dynamic> session) {
    return DateTime.tryParse('${session['date'] ?? ''}');
  }

  List<Map<String, dynamic>> _sessionExercises(Map<String, dynamic> session) {
    final raw = session['exercises'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  double _sessionVolume(Map<String, dynamic> session) {
    return _sessionExercises(session).fold<double>(0, (total, exercise) {
      return total +
          _asDouble(exercise['weight']) *
              _asInt(exercise['sets']) *
              _asInt(exercise['reps']);
    });
  }

  double _caloriesForSessions(Iterable<Map<String, dynamic>> sessions) {
    return sessions.fold<double>(0, (total, session) {
      final calories = session['caloriesBurned'];
      return total + (calories is num ? calories.toDouble() : 0.0);
    });
  }

  double _todayCaloriesBurned() {
    final now = DateTime.now();
    return _caloriesForSessions(fitCoreHistory.where((session) {
      final date = _sessionDate(session);
      return date != null && date.year == now.year && date.month == now.month && date.day == now.day;
    }));
  }

  double _weekCaloriesBurned() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return _caloriesForSessions(fitCoreHistory.where((session) {
      final date = _sessionDate(session);
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      final offset = day.difference(monday).inDays;
      return offset >= 0 && offset < 7;
    }));
  }

  Future<void> _openCaloriesCalculator() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CaloriesCalculatorPage()),
    );
  }

  Map<String, dynamic> _weeklyData() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final counts = List<int>.filled(7, 0);

    for (final session in fitCoreHistory) {
      final date = _sessionDate(session);
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final difference = day.difference(monday).inDays;
      if (difference >= 0 && difference < 7) counts[difference]++;
    }

    final activeDays = counts.where((count) => count > 0).length;
    return {'counts': counts, 'activeDays': activeDays};
  }

  List<Map<String, dynamic>> _strengthData() {
    final sortedSessions = fitCoreHistory.toList()
      ..sort((a, b) {
        final dateA = _sessionDate(a) ?? DateTime(1970);
        final dateB = _sessionDate(b) ?? DateTime(1970);
        return dateA.compareTo(dateB);
      });

    final Map<String, List<double>> historyByExercise = {};
    for (final session in sortedSessions) {
      for (final exercise in _sessionExercises(session)) {
        final name = '${exercise['name'] ?? 'Exercise'}';
        final weight = _asDouble(exercise['weight']);
        if (weight <= 0) continue;
        historyByExercise.putIfAbsent(name, () => []).add(weight);
      }
    }

    return historyByExercise.entries.map((entry) {
      final weights = entry.value;
      final startWeight = weights.first;
      final currentWeight = weights.last;
      final change = currentWeight - startWeight;
      return {
        'name': entry.key,
        'current': currentWeight,
        'change': change,
      };
    }).toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  }

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFF00D4FF);
    const cardColor = Color(0xFF1C1C1C);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: lime),
      );
    }

    final totalWorkouts = fitCoreHistory.length;
    final totalVolume = fitCoreHistory.fold<double>(
      0,
          (total, session) => total + _sessionVolume(session),
    );
    final weekly = _weeklyData();
    final weeklyCounts = weekly['counts'] as List<int>;
    final activeDays = weekly['activeDays'] as int;
    final strengthData = _strengthData();
    final maxCount = weeklyCounts.fold<int>(
      1,
          (maximum, value) => value > maximum ? value : maximum,
    );

    return RefreshIndicator(
      color: lime,
      onRefresh: _refreshHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Progress',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Based on your saved workout sessions',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _analysisCard(
                    'Workouts',
                    '$totalWorkouts',
                    'Sessions completed',
                    cardColor,
                    lime,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _analysisCard(
                    'Volume',
                    totalVolume.toStringAsFixed(0),
                    'kg total volume',
                    cardColor,
                    lime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _analysisCard(
              'Consistency',
              '$activeDays / 7 days',
              'Active this week',
              cardColor,
              lime,
            ),
            const SizedBox(height: 24),
            const Text(
              'Calories & Energy',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _analysisCard('Today burned', '${_todayCaloriesBurned().round()}', 'Estimated kcal', cardColor, lime)),
                const SizedBox(width: 12),
                Expanded(child: _analysisCard('This week', '${_weekCaloriesBurned().round()}', 'Estimated kcal', cardColor, lime)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Workout burn estimates are saved for new sessions after this update.', style: TextStyle(color: muted, fontSize: 10)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCaloriesCalculator,
                style: OutlinedButton.styleFrom(
                  foregroundColor: lime,
                  side: BorderSide(color: lime.withOpacity(0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.local_fire_department_rounded),
                label: const Text('OPEN DAILY CALORIE CALCULATOR', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5)),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Weekly Activity',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                  final count = weeklyCounts[index];
                  final barHeight = count == 0
                      ? 5.0
                      : 18.0 + (count / maxCount) * 68.0;

                  return Column(
                    children: [
                      Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 24,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: count == 0 ? Colors.white12 : lime,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        days[index],
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Strength Progress',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your recorded weight changes by exercise',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (strengthData.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Complete and save workouts with weights to see your strength progress here.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            else
              ...strengthData.map((item) {
                final current = _asDouble(item['current']);
                final change = _asDouble(item['change']);
                final changeText = change > 0
                    ? '+${change.toStringAsFixed(change % 1 == 0 ? 0 : 1)} kg'
                    : change < 0
                    ? '${change.toStringAsFixed(change % 1 == 0 ? 0 : 1)} kg'
                    : 'No change';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _strengthCard(
                    '${item['name']}',
                    '${current.toStringAsFixed(current % 1 == 0 ? 0 : 1)} kg',
                    changeText,
                    lime,
                    cardColor,
                  ),
                );
              }),
            const SizedBox(height: 12),
            if (totalWorkouts == 0)
              const Text(
                'Your charts will start filling in after your first saved workout.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _analysisCard(
      String title,
      String value,
      String subtitle,
      Color cardColor,
      Color lime,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: lime,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _strengthCard(
      String exercise,
      String weight,
      String progress,
      Color lime,
      Color cardColor,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              exercise,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            weight,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            progress,
            style: TextStyle(
              color: lime,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}


class CaloriesCalculatorPage extends StatefulWidget {
  const CaloriesCalculatorPage({super.key});

  @override
  State<CaloriesCalculatorPage> createState() => _CaloriesCalculatorPageState();
}

class _CaloriesCalculatorPageState extends State<CaloriesCalculatorPage> {
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  String _sex = 'Choose';
  String _activity = 'Moderately active';
  String _goal = 'Maintain weight';
  bool _loading = true;
  double? _bmr;
  double? _maintenance;
  double? _target;

  static const Map<String, double> _activityFactors = {
    'Sedentary': 1.2,
    'Lightly active': 1.375,
    'Moderately active': 1.55,
    'Very active': 1.725,
    'Extra active': 1.9,
  };

  @override
  void initState() {
    super.initState();
    _loadSavedValues();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedValues() async {
    final prefs = await SharedPreferences.getInstance();
    _ageController.text = prefs.getString('fitcore_profile_age') ?? '';
    _heightController.text = prefs.getString('fitcore_profile_height') ?? '';
    _weightController.text = prefs.getString('fitcore_profile_weight') ?? '';
    _sex = prefs.getString('fitcore_calorie_sex') ?? 'Choose';
    _activity = prefs.getString('fitcore_calorie_activity') ?? 'Moderately active';
    _goal = prefs.getString('fitcore_calorie_goal') ?? 'Maintain weight';
    if (mounted) setState(() => _loading = false);
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: muted),
      filled: true,
      fillColor: const Color(0xFF202320),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: lime, width: 1.2)),
    );
  }

  Future<void> _calculate() async {
    final age = int.tryParse(_ageController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    if (age == null || age < 19 || age > 78 || height == null || height < 100 || height > 250 ||
        weight == null || weight < 20 || weight > 300 || (_sex != 'Male' && _sex != 'Female')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid age (19–78), height, weight and select the formula profile.')),
      );
      return;
    }

    // Mifflin–St Jeor resting-energy estimate for adults.
    final base = 10 * weight + 6.25 * height - 5 * age;
    final bmr = base + (_sex == 'Male' ? 5 : -161);
    final maintenance = bmr * (_activityFactors[_activity] ?? 1.55);
    final target = _goal == 'Fat loss'
        ? maintenance - 300
        : _goal == 'Muscle gain'
        ? maintenance + 250
        : maintenance;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fitcore_profile_age', age.toString());
    await prefs.setString('fitcore_profile_height', height.toString());
    await prefs.setString('fitcore_profile_weight', weight.toString());
    await prefs.setString('fitcore_calorie_sex', _sex);
    await prefs.setString('fitcore_calorie_activity', _activity);
    await prefs.setString('fitcore_calorie_goal', _goal);
    if (!mounted) return;
    setState(() {
      _bmr = bmr;
      _maintenance = maintenance;
      _target = target;
    });
  }

  Widget _resultTile(String title, double? value, String note, {bool primary = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primary ? lime.withOpacity(.10) : card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary ? lime.withOpacity(.45) : Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Text(value == null ? '--' : '${value.round()} kcal/day',
            style: TextStyle(color: primary ? lime : Colors.white, fontSize: primary ? 25 : 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(note, style: const TextStyle(color: muted, fontSize: 11)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: const Text('CALORIE CALCULATOR', style: TextStyle(fontWeight: FontWeight.w900))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: lime))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.local_fire_department_rounded, color: lime, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Uses the Mifflin–St Jeor equation for adults aged 19–78, with your selected activity level.', style: TextStyle(color: muted, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: TextField(controller: _ageController, keyboardType: TextInputType.number, decoration: _fieldDecoration('Age (years)', Icons.cake_outlined), onChanged: (_) { if (_bmr != null) setState(() { _bmr = null; _maintenance = null; _target = null; }); })),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _heightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _fieldDecoration('Height (cm)', Icons.height_rounded), onChanged: (_) { if (_bmr != null) setState(() { _bmr = null; _maintenance = null; _target = null; }); })),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _fieldDecoration('Weight (kg)', Icons.monitor_weight_outlined), onChanged: (_) { if (_bmr != null) setState(() { _bmr = null; _maintenance = null; _target = null; }); }),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _sex,
            dropdownColor: card,
            decoration: _fieldDecoration('Formula profile', Icons.person_outline_rounded),
            items: const [
              DropdownMenuItem(value: 'Choose', child: Text('Choose for formula')),
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
            ],
            onChanged: (value) { if (value != null) setState(() { _sex = value; _bmr = null; }); },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _activity,
            dropdownColor: card,
            decoration: _fieldDecoration('Daily activity level', Icons.directions_walk_rounded),
            items: _activityFactors.keys.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) { if (value != null) setState(() { _activity = value; _bmr = null; }); },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _goal,
            dropdownColor: card,
            decoration: _fieldDecoration('Your goal', Icons.flag_outlined),
            items: const [
              DropdownMenuItem(value: 'Maintain weight', child: Text('Maintain weight')),
              DropdownMenuItem(value: 'Fat loss', child: Text('Fat loss (moderate deficit)')),
              DropdownMenuItem(value: 'Muscle gain', child: Text('Muscle gain (small surplus)')),
            ],
            onChanged: (value) { if (value != null) setState(() { _goal = value; _bmr = null; }); },
          ),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton.icon(
            onPressed: _calculate,
            style: ElevatedButton.styleFrom(backgroundColor: lime, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.calculate_rounded),
            label: const Text('CALCULATE MY CALORIES', style: TextStyle(fontWeight: FontWeight.w900)),
          )),
          if (_bmr != null) ...[
            const SizedBox(height: 22),
            const Text('YOUR ESTIMATES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: .8)),
            const SizedBox(height: 12),
            _resultTile('Resting energy (BMR / RMR)', _bmr, 'Estimated calories at rest'),
            const SizedBox(height: 10),
            _resultTile('Maintenance calories', _maintenance, 'Estimated daily calories for your selected activity level'),
            const SizedBox(height: 10),
            _resultTile('Daily target', _target, _goal, primary: true),
          ],
          const SizedBox(height: 18),
          const Text('These are estimates, not measurements or medical advice. Actual needs vary; use trends over time and seek a registered dietitian for medical or individual nutrition guidance.', style: TextStyle(color: muted, fontSize: 11, height: 1.45)),
        ]),
      ),
    );
  }
}

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key});

  @override
  State<WorkoutHistoryPage> createState() =>
      _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState
    extends State<WorkoutHistoryPage> {
  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await loadWorkoutHistory();

    if (mounted) {
      setState(() {});
    }
  }

  String formatDate(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) return 'Workout Session';

    const months = [
      'JAN', 'FEB', 'MAR', 'APR',
      'MAY', 'JUN', 'JUL', 'AUG',
      'SEP', 'OCT', 'NOV', 'DEC',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text(
          'Workout History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: fitCoreHistory.isEmpty
          ? const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              color: lime,
              size: 55,
            ),
            SizedBox(height: 14),
            Text(
              'No workout history yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Complete a workout and save it.',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          18, 16, 18, 24,
        ),
        itemCount: fitCoreHistory.length,
        itemBuilder: (context, index) {
          final session = fitCoreHistory[
          fitCoreHistory.length - 1 - index];

          final savedExercises =
          (session['exercises'] as List? ?? [])
              .map(
                (item) =>
            Map<String, dynamic>.from(
                item as Map),
          )
              .toList();

          final dateText =
              session['date']?.toString() ?? '';

          final totalVolume =
          savedExercises.fold<double>(
            0,
                (sum, exercise) {
              final sets =
                  (exercise['sets'] as num?)
                      ?.toDouble() ??
                      0;
              final reps =
                  (exercise['reps'] as num?)
                      ?.toDouble() ??
                      0;
              final weight =
                  (exercise['weight'] as num?)
                      ?.toDouble() ??
                      0;

              return sum + sets * reps * weight;
            },
          );

          final volumeText =
          totalVolume % 1 == 0
              ? totalVolume.toStringAsFixed(0)
              : totalVolume.toStringAsFixed(1);

          return Container(
            margin: const EdgeInsets.only(
              bottom: 16,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: card,
              borderRadius:
              BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white
                    .withOpacity(0.07),
              ),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                // Date and session label
                Row(
                  children: [
                    Container(
                      padding:
                      const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: lime.withOpacity(0.12),
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        color: lime,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatDate(dateText),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight:
                              FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'TRAINING SESSION',
                            style: TextStyle(
                              color: muted,
                              fontSize: 10,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: lime,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Workout statistics
                Row(
                  children: [
                    Expanded(
                      child: _historyStat(
                        '${savedExercises.length}',
                        'EXERCISES',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _historyStat(
                        '$volumeText kg',
                        'TOTAL VOLUME',
                      ),
                    ),
                  ],
                ),

                if (session['caloriesBurned'] is num) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: lime.withOpacity(.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.local_fire_department_rounded, color: lime, size: 20),
                      const SizedBox(width: 8),
                      const Text('EST. CALORIES BURNED', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .7)),
                      const Spacer(),
                      Text('${(session['caloriesBurned'] as num).round()} kcal', style: const TextStyle(color: lime, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ],

                const SizedBox(height: 20),

                Divider(
                  color: Colors.white
                      .withOpacity(0.08),
                ),

                const SizedBox(height: 12),

                const Text(
                  'EXERCISES',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),

                const SizedBox(height: 14),

                ...savedExercises.map((exercise) {
                  return Padding(
                    padding:
                    const EdgeInsets.only(
                        bottom: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withOpacity(0.05),
                            borderRadius:
                            BorderRadius.circular(
                                10),
                          ),
                          child: const Icon(
                            Icons
                                .check_rounded,
                            color: lime,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Text(
                                '${exercise['name']}',
                                style:
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight:
                                  FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(
                                  height: 4),
                              Text(
                                '${exercise['sets']} sets × '
                                    '${exercise['reps']} reps',
                                style:
                                const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Text(
                          '${exercise['weight']} kg',
                          style: const TextStyle(
                            color: lime,
                            fontWeight:
                            FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _historyStat(
      String value,
      String label,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: lime,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
class TrainerPage extends StatefulWidget {
  final bool selectMode;
  const TrainerPage({super.key, this.selectMode = false});

  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> {
  List<Map<String, dynamic>> exercises = [];
  List<Map<String, dynamic>> filteredExercises = [];
  bool isBack = false;
  String selectedMuscle = 'All';
  bool loading = true;
  String? selectedAtlasMuscleId;
  String? selectedAtlasMuscleGroupId;

  final TextEditingController searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _exerciseListScrollController = ScrollController();
  bool _searchHasFocus = false;
  bool _atlasCompact = false;
  String searchQuery = '';
  String selectedBodyPart = 'All';
  String selectedEquipment = 'All';

  final List<String> bodyPartOptions = const [
    'All',
    'Back',
    'Cardio',
    'Chest',
    'Lower arms',
    'Lower legs',
    'Neck',
    'Shoulders',
    'Upper arms',
    'Upper legs',
    'Waist',
  ];

  List<String> get equipmentOptions {
    final values = exercises
        .map((exercise) {
      dynamic equipment = exercise['equipment'];
      if (equipment is Map) equipment = equipment['en'];
      return (equipment ?? '').toString().trim();
    })
        .where((equipment) => equipment.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return ['All', ...values];
  }

  @override
  void dispose() {
    searchController.dispose();
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _exerciseListScrollController.removeListener(_handleExerciseListScroll);
    _exerciseListScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _exerciseListScrollController.addListener(_handleExerciseListScroll);
    _searchFocusNode.addListener(_handleSearchFocusChange);
    loadExercises();
  }

  bool get _listIsScrolled =>
      _exerciseListScrollController.hasClients &&
          _exerciseListScrollController.position.pixels > 28;

  void _handleSearchFocusChange() {
    _searchHasFocus = _searchFocusNode.hasFocus;
    _syncAtlasVisibility();
  }

  void _handleExerciseListScroll() {
    _syncAtlasVisibility();
  }

  void _syncAtlasVisibility() {
    final shouldHideAtlas =
        _searchHasFocus || searchQuery.trim().isNotEmpty || _listIsScrolled;
    if (mounted && shouldHideAtlas != _atlasCompact) {
      setState(() => _atlasCompact = shouldHideAtlas);
    }
  }

  Future<void> loadExercises() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/exercises/exercises-dataset-main/data/exercises.json',
      );

      final decoded = jsonDecode(jsonString) as List;

      exercises = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      filteredExercises = exercises;
    } catch (e) {
      debugPrint('Exercise loading error: $e');
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }



  // Convert the atlas's anatomical subdivisions into broad gym filters.
  // Any selected region maps to its full fitness group, including left/right.
  String fitnessGroupForMuscle(MuscleInfo muscle) =>
      _fitCoreFitnessGroupForMuscle(muscle);

  List<MuscleInfo> atlasMusclesForFitnessGroup(String groupId) {
    return Muscle.values
        .map((muscle) => MuscleCatalog.byIdOrThrow(muscle.id))
        .where((info) => fitnessGroupForMuscle(info) == groupId)
        .toList();
  }

  String _englishValue(dynamic value) {
    if (value is Map) value = value['en'];
    if (value is List) return value.join(' ');
    return (value ?? '').toString();
  }

  bool _matchesAtlasGroup(Map<String, dynamic> exercise) {
    final group = (selectedAtlasMuscleGroupId ?? '').toLowerCase();
    if (group.isEmpty) return true;

    final muscleText = [
      exercise['muscle_group'],
      exercise['target'],
      exercise['secondary_muscles'],
      exercise['body_part'],
    ].map(_englishValue).join(' ').toLowerCase();

    final keywords = <String, List<String>>{
      'chest': ['chest', 'pector', 'pec'],
      'back': ['back', 'lat', 'trapezius', 'trap', 'rhomboid', 'spine'],
      'shoulders': ['shoulder', 'deltoid', 'delt'],
      'biceps': ['biceps', 'bicep', 'brachialis'],
      'triceps': ['triceps', 'tricep'],
      'forearms': ['forearm', 'wrist'],
      'abs': ['abs', 'abdominal', 'oblique', 'core', 'rectus'],
      'legs': [
        'quad', 'quadriceps', 'hamstring', 'calf', 'calves',
        'glute', 'adductor', 'thigh'
      ],
      'neck': ['neck'],
    };

    final groupKeywords = keywords[group] ?? [group];
    return groupKeywords.any((keyword) => muscleText.contains(keyword));
  }

  void _applyExerciseFilters() {
    final query = searchQuery.toLowerCase().trim();

    setState(() {
      _atlasCompact =
          _searchFocusNode.hasFocus || query.isNotEmpty || _listIsScrolled;
      filteredExercises = exercises.where((exercise) {
        final name = _englishValue(exercise['name']).toLowerCase();
        final bodyPart = _englishValue(exercise['body_part']).toLowerCase();
        final equipment = _englishValue(exercise['equipment']).toLowerCase();

        final searchableText = [
          exercise['name'],
          exercise['body_part'],
          exercise['equipment'],
          exercise['target'],
          exercise['muscle_group'],
          exercise['secondary_muscles'],
        ].map(_englishValue).join(' ').toLowerCase();

        final matchesSearch =
            query.isEmpty || searchableText.contains(query);

        final matchesBodyPart = selectedBodyPart == 'All' ||
            bodyPart == selectedBodyPart.toLowerCase();

        final matchesEquipment = selectedEquipment == 'All' ||
            equipment == selectedEquipment.toLowerCase();

        return matchesSearch &&
            matchesBodyPart &&
            matchesEquipment &&
            _matchesAtlasGroup(exercise);
      }).toList();
    });
  }

  // Called when an atlas muscle is tapped or the search text changes.
  void filterExercises(String value) {
    selectedMuscle = value;
    _applyExerciseFilters();
  }

  void _clearAllFilters() {
    searchController.clear();
    searchQuery = '';
    selectedBodyPart = 'All';
    selectedEquipment = 'All';
    selectedMuscle = 'All';
    selectedAtlasMuscleId = null;
    selectedAtlasMuscleGroupId = null;
    _applyExerciseFilters();
  }

  Widget _buildMuscleAtlas({required bool landscape}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: landscape ? 8 : 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MUSCLE MAP',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => isBack = !isBack),
                child: Text(
                  isBack ? 'BACK' : 'FRONT',
                  style: const TextStyle(color: lime),
                ),
              ),
            ],
          ),
          Expanded(
            child: AnimatedScale(
              scale: _atlasCompact ? .78 : 1.0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.center,
              child: BodyAtlasView<MuscleInfo>(
                view: isBack ? AtlasAsset.musclesBack : AtlasAsset.musclesFront,
                resolver: const MuscleResolver(),
                colorMapping: selectedAtlasMuscleGroupId == null
                    ? (selectedAtlasMuscleId == null
                    ? const {}
                    : {
                  MuscleCatalog.byIdOrThrow(selectedAtlasMuscleId!): lime,
                })
                    : {
                  for (final item in atlasMusclesForFitnessGroup(
                    selectedAtlasMuscleGroupId!,
                  ))
                    item: lime,
                },
                onTapElement: (muscle) {
                  final fitnessGroup = fitnessGroupForMuscle(muscle);
                  debugPrint('FitCore atlas muscle: ${muscle.id}; group: $fitnessGroup');
                  setState(() {
                    selectedAtlasMuscleId = muscle.id;
                    selectedAtlasMuscleGroupId = fitnessGroup;
                    selectedBodyPart = 'All';
                    selectedMuscle = fitnessGroup;
                  });
                  filterExercises(fitnessGroup);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseFilters({required bool compact}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 4 : 8, 16, compact ? 4 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: searchController,
            focusNode: _searchFocusNode,
            onTap: () {
              if (!_atlasCompact) setState(() => _atlasCompact = true);
            },
            onChanged: (value) {
              searchQuery = value;
              _applyExerciseFilters();
            },
            style: const TextStyle(color: Colors.white),
            cursorColor: lime,
            decoration: InputDecoration(
              hintText: 'Search exercise, muscle or equipment...',
              hintStyle: const TextStyle(color: muted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: lime),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.close_rounded, color: muted),
                onPressed: () {
                  searchController.clear();
                  searchQuery = '';
                  _applyExerciseFilters();
                },
              ),
              filled: true,
              fillColor: card,
              contentPadding: EdgeInsets.symmetric(vertical: compact ? 8 : 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: compact ? 5 : 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedBodyPart,
                  isExpanded: true,
                  dropdownColor: card,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Body part',
                    labelStyle: const TextStyle(color: muted, fontSize: 12),
                    filled: true,
                    fillColor: card,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: compact ? 5 : 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: bodyPartOptions
                      .map((part) => DropdownMenuItem(
                    value: part,
                    child: Text(part, overflow: TextOverflow.ellipsis),
                  ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedBodyPart = value;
                      selectedAtlasMuscleId = null;
                      selectedAtlasMuscleGroupId = null;
                      selectedMuscle = 'All';
                    });
                    _applyExerciseFilters();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedEquipment,
                  isExpanded: true,
                  dropdownColor: card,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Equipment',
                    labelStyle: const TextStyle(color: muted, fontSize: 12),
                    filled: true,
                    fillColor: card,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: compact ? 5 : 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: equipmentOptions
                      .map((equipment) => DropdownMenuItem(
                    value: equipment,
                    child: Text(
                      equipment,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedEquipment = value);
                    _applyExerciseFilters();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : 8),
          Row(
            children: [
              Text(
                '${filteredExercises.length} exercises',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearAllFilters,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('Clear filters'),
                style: TextButton.styleFrom(
                  foregroundColor: lime,
                  padding: EdgeInsets.zero,
                  visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseList() {
    if (filteredExercises.isEmpty) {
      return const Center(child: Text('No exercises found'));
    }
    return ListView.builder(
      controller: _exerciseListScrollController,
      itemCount: filteredExercises.length,
      itemBuilder: (context, index) {
        final exercise = filteredExercises[index];
        return Card(
          color: card,
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: const Color(0xFF00D4FF).withOpacity(.10)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            minLeadingWidth: 74,
            onTap: () {
              if (widget.selectMode) {
                String valueOf(dynamic value) {
                  if (value is Map) return (value['en'] ?? (value.values.isEmpty ? '' : value.values.first)).toString();
                  if (value is List) return value.join(', ');
                  return (value ?? '').toString();
                }
                final target = valueOf(exercise['target']).trim().isNotEmpty
                    ? valueOf(exercise['target'])
                    : valueOf(exercise['body_part']);
                Navigator.pop(context, {
                  'name': valueOf(exercise['name']),
                  'target': target.isEmpty ? 'General' : target,
                  'body_part': valueOf(exercise['body_part']),
                  'equipment': valueOf(exercise['equipment']),
                  'datasetId': exercise['id'],
                  'media_id': exercise['media_id'],
                  'image': exercise['image'],
                  'gif_url': exercise['gif_url'],
                });
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExerciseDetailsPage(exercise: exercise),
                ),
              );
            },
            leading: _fitCoreExerciseThumbnail(exercise, size: 72),
            title: Text(
              (exercise['name'] ?? 'Exercise').toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                height: 1.2,
              ),
            ),
            subtitle: Text(
              '${exercise['body_part'] ?? 'Other'} • '
                  '${exercise['equipment'] ?? 'No equipment'}',
              style: const TextStyle(color: muted, fontSize: 12, height: 1.25),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: lime, size: 23),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedAtlasSlot({required bool landscape}) {
    final isCompact = _atlasCompact;
    final atlasWidth = MediaQuery.of(context).size.width * 0.40;
    final atlasHeight = MediaQuery.of(context).size.height < 700 ? 190.0 : 260.0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
      alignment: landscape ? Alignment.centerLeft : Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: Align(
        alignment: landscape ? Alignment.centerLeft : Alignment.topCenter,
        widthFactor: landscape ? (isCompact ? 0.0 : 1.0) : null,
        heightFactor: landscape ? null : (isCompact ? 0.0 : 1.0),
        child: SizedBox(
          width: landscape ? atlasWidth : double.infinity,
          height: landscape ? null : atlasHeight,
          child: AnimatedOpacity(
            opacity: isCompact ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
            child: AnimatedSlide(
              offset: isCompact
                  ? (landscape ? const Offset(-0.08, 0) : const Offset(0, -0.08))
                  : Offset.zero,
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOutCubic,
              child: _buildMuscleAtlas(landscape: landscape),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: bg,
        title: Text(widget.selectMode ? 'ADD EXERCISE TO PLAN' : 'EXERCISE TRAINER'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: lime))
          : isLandscape
          ? Row(
        children: [
          _buildAnimatedAtlasSlot(landscape: true),
          Expanded(
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: _buildExerciseFilters(compact: true),
                ),
                // This Expanded list receives the exact width/height
                // released when the muscle atlas slot collapses.
                Expanded(child: _buildExerciseList()),
              ],
            ),
          ),
        ],
      )
          : Column(
        children: [
          _buildAnimatedAtlasSlot(landscape: false),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _buildExerciseFilters(compact: _atlasCompact),
          ),
          // Always fill all remaining vertical space after the
          // atlas and filters have taken only the height they need.
          Expanded(child: _buildExerciseList()),
        ],
      ),
    );
  }

}

class ExerciseDetailsPage extends StatelessWidget {
  final Map<String, dynamic> exercise;

  const ExerciseDetailsPage({
    super.key,
    required this.exercise,
  });

  String _text(dynamic value, {String fallback = 'Not specified'}) {
    if (value == null) return fallback;

    // Dataset translations are stored in a language map. Show English only.
    if (value is Map) value = value['en'];

    if (value == null) return fallback;
    if (value is String && value.trim().isEmpty) return fallback;

    if (value is List) {
      final items = value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
      return items.isEmpty ? fallback : items.join('\n\n');
    }

    return value.toString();
  }

  List<String> _englishInstructionSteps() {
    dynamic steps = exercise['instruction_steps'];
    if (steps is Map) steps = steps['en'];

    if (steps is List) {
      final englishSteps = steps
          .map((step) => step.toString().trim())
          .where((step) => step.isNotEmpty)
          .take(5)
          .toList();
      if (englishSteps.isNotEmpty) return englishSteps;
    }

    dynamic instructions = exercise['instructions'];
    if (instructions is Map) instructions = instructions['en'];
    if (instructions is String && instructions.trim().isNotEmpty) {
      return [instructions.trim()];
    }
    return [];
  }

  Widget _instructionSection(List<String> steps) {
    if (steps.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOW TO PERFORM',
            style: TextStyle(
              color: lime,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(steps.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. ',
                    style: const TextStyle(
                      color: lime,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      steps[index],
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _section(String title, String content) {
    if (content == 'Not specified') return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: lime,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              color: Colors.white,
              height: 1.5,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _text(exercise['name'], fallback: 'Exercise');
    final mediaId = _text(exercise['media_id'], fallback: '');

    // gif_url/image are relative file paths in this dataset, not HTTP URLs.
    // media_id maps to the ExerciseDB GIF endpoint.
    final imageUrl = mediaId.isNotEmpty
        ? 'https://static.exercisedb.dev/media/$mediaId.gif'
        : _text(
      exercise['gif_url'] ??
          exercise['image'] ??
          exercise['gif'] ??
          exercise['image_url'],
      fallback: '',
    );
    final hasImage = imageUrl.startsWith('http://') ||
        imageUrl.startsWith('https://');

    final instructions = _englishInstructionSteps();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('EXERCISE DETAILS'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 230,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 230,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const CircularProgressIndicator(color: lime),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _imagePlaceholder();
                  },
                ),
              )
            else
              _imagePlaceholder(),
            const SizedBox(height: 18),
            _section(
              'Target muscle',
              _text(
                exercise['target'] ?? exercise['muscle_group'],
              ),
            ),
            _section(
              'Equipment',
              _text(exercise['equipment'], fallback: 'Bodyweight'),
            ),
            _instructionSection(instructions),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: lime,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'ADD TO WORKOUT',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                onPressed: () async {
                  final alreadyAdded = fitCoreExercises.any(
                        (item) => item['name'] == name,
                  );

                  if (alreadyAdded) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This exercise is already in your workout.'),
                      ),
                    );
                    return;
                  }

                  fitCoreExercises.add({
                    'name': name,
                    'sets': 3,
                    'reps': 12,
                    'weight': 0.0,
                    'done': false,
                  });

                  await saveWorkoutData();

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exercise added to your workout!'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined, color: lime, size: 40),
          SizedBox(height: 10),
          Text(
            'Exercise demo unavailable',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}

