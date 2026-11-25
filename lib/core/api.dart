import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;
String? get uid => sb.auth.currentUser?.id;

class Profile {
  final String id, role, username, fullName;
  final String? avatarUrl, collegeId, departmentId, batch;
  final int? semester;
  final bool authorised;

  Profile({
    required this.id,
    required this.role,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.collegeId,
    this.departmentId,
    this.batch,
    this.semester,
    required this.authorised,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'],
        role: m['role'],
        username: m['username'],
        fullName: m['full_name'] ?? '',
        avatarUrl: m['avatar_url'],
        collegeId: m['college_id'],
        departmentId: m['department_id'],
        batch: m['batch'],
        semester: m['semester'],
        authorised: m['is_authorised'] ?? false,
      );

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isInstitution => role == 'institution';
}

Future<Profile?> loadProfile() async {
  final id = uid;
  if (id == null) return null;
  final m = await sb.from('profiles').select().eq('id', id).maybeSingle();
  return m == null ? null : Profile.fromMap(m);
}

/// Human-readable message from any backend / platform error.
String errText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is StorageException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

/// Current position, with permission + mock-location checks.
/// Used for QR attendance on both teacher and student devices.
Future<Position> getPosition({bool rejectMock = false}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Turn on location services to continue.');
  }
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) {
    p = await Geolocator.requestPermission();
  }
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
    throw Exception('Location permission is required for attendance.');
  }
  final pos = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
  if (rejectMock && pos.isMocked) {
    throw Exception('Mock / fake location detected. Attendance not marked.');
  }
  return pos;
}

String fmtDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}

String fmtTime(DateTime d) {
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour >= 12 ? 'PM' : 'AM'}';
}

String ago(DateTime d) {
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return fmtDate(d.toLocal());
}
