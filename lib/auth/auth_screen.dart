import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool register = false, busy = false, hide = true;
  String role = 'student';
  final email = TextEditingController();
  final pass = TextEditingController();
  final username = TextEditingController();
  final fullName = TextEditingController();
  final batch = TextEditingController();
  String? collegeId, deptId;
  int semester = 1;
  List<Map<String, dynamic>> colleges = [], depts = [];
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadColleges();
  }

  Future<void> _loadColleges() async {
    try {
      final r = await sb.from('colleges').select('id,name').order('name');
      if (mounted) setState(() => colleges = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  Future<void> _loadDepts(String cid) async {
    final r = await sb.from('departments').select('id,name').eq('college_id', cid).order('name');
    if (mounted) setState(() => depts = List<Map<String, dynamic>>.from(r));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (register) {
        final u = username.text.trim().toLowerCase();
        final ok = await sb.rpc('username_available', params: {'u': u});
        if (ok != true) throw Exception('That username is taken. Try another.');
        final res = await sb.auth.signUp(
          email: email.text.trim(),
          password: pass.text,
          data: {
            'username': u,
            'full_name': fullName.text.trim(),
            'role': role,
            'college_id': collegeId ?? '',
            'department_id': deptId ?? '',
            'semester': '$semester',
            'batch': batch.text.trim(),
          },
        );
        if (res.session == null && mounted) {
          toast(context, 'Check your email to confirm your account, then log in.');
          setState(() => register = false);
        }
      } else {
        await sb.auth.signInWithPassword(
            email: email.text.trim(), password: pass.text);
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
              center: const Alignment(-.8, -1),
              radius: 1.3,
              colors: [HC.violet.withOpacity(.35), cs.surface]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => HC.grad.createShader(r),
                        child: const Text('HUDDLE',
                            style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                color: Colors.white)),
                      ),
                      Text('your campus, in one place.',
                          style: TextStyle(
                              color: cs.onSurface.withOpacity(.7),
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 28),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('Log in')),
                          ButtonSegment(value: true, label: Text('Sign up')),
                        ],
                        selected: {register},
                        onSelectionChanged: (s) =>
                            setState(() => register = s.first),
                      ),
                      const SizedBox(height: 20),
                      if (register) ...[
                        Row(children: [
                          _roleChip('student', 'Student', Icons.school_rounded),
                          const SizedBox(width: 10),
                          _roleChip('teacher', 'Teacher', Icons.badge_rounded),
                        ]),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: username,
                          decoration: const InputDecoration(
                              labelText: 'Username',
                              helperText:
                                  'This is what others see - never your phone or email',
                              prefixIcon: Icon(Icons.alternate_email_rounded)),
                          validator: (v) => RegExp(r'^[a-zA-Z0-9_.]{3,24}$')
                                  .hasMatch(v ?? '')
                              ? null
                              : '3-24 chars: letters, numbers, _ or .',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: fullName,
                          maxLength: 80,
                          decoration: const InputDecoration(
                              labelText: 'Full name', counterText: ''),
                          validator: (v) => (v ?? '').trim().length < 2
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: collegeId,
                          decoration: const InputDecoration(labelText: 'College'),
                          items: colleges
                              .map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(c['name'])))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              collegeId = v;
                              deptId = null;
                              depts = [];
                            });
                            if (v != null) _loadDepts(v);
                          },
                          validator: (v) => v == null ? 'Pick your college' : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: deptId,
                          decoration:
                              const InputDecoration(labelText: 'Department'),
                          items: depts
                              .map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(c['name'])))
                              .toList(),
                          onChanged: (v) => setState(() => deptId = v),
                          validator: (v) =>
                              v == null ? 'Pick your department' : null,
                        ),
                        if (role == 'student') ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: semester,
                                decoration:
                                    const InputDecoration(labelText: 'Semester'),
                                items: List.generate(
                                    8,
                                    (i) => DropdownMenuItem(
                                        value: i + 1, child: Text('Sem ${i + 1}'))),
                                onChanged: (v) => setState(() => semester = v ?? 1),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: batch,
                                maxLength: 20,
                                decoration: const InputDecoration(
                                    labelText: 'Batch / class',
                                    hintText: 'A',
                                    counterText: ''),
                                validator: (v) => (v ?? '').trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline_rounded)),
                        validator: (v) =>
                            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                                ? null
                                : 'Enter a valid email',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: pass,
                        obscureText: hide,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                              icon: Icon(hide
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded),
                              onPressed: () => setState(() => hide = !hide)),
                        ),
                        validator: (v) => (v ?? '').length < 8
                            ? 'At least 8 characters'
                            : null,
                      ),
                      if (register && role == 'teacher')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              'Teacher accounts are checked by your institution before attendance tools unlock.',
                              style: TextStyle(
                                  color: HC.peach,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5))
                            : Text(register ? 'Create account' : 'Log in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleChip(String v, String label, IconData icon) {
    final sel = role == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => role = v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: sel ? HC.grad : null,
            color: sel ? null : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: sel ? Colors.white : null),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : null)),
          ]),
        ),
      ),
    );
  }
}
