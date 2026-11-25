import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'theme.dart';

void toast(BuildContext context, String msg, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg,
          style: TextStyle(
              color: error ? cs.onErrorContainer : cs.onInverseSurface,
              fontWeight: FontWeight.w600)),
      backgroundColor: error ? cs.errorContainer : cs.inverseSurface,
    ));
}

class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double radius;
  const Avatar({super.key, required this.name, this.url, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    final colors = [HC.violet, HC.pink, HC.sky, HC.peach, HC.lime];
    final c = colors[name.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withOpacity(.9),
      foregroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: Text(letter,
          style: TextStyle(
              color: HC.ink,
              fontWeight: FontWeight.w800,
              fontSize: radius * .8)),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = HC.violet, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(.18),
            borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4)
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle = '',
      this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  gradient: HC.grad.scale(.35), shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: HC.violetSoft),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.65))),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load this',
        subtitle: error.toString().replaceFirst('Exception: ', ''),
        action: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again')),
      );
}

/// Pulsing placeholder for loading states.
class Skeleton extends StatefulWidget {
  final double height;
  const Skeleton({super.key, this.height = 72});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          height: widget.height,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHigh
                .withOpacity(.5 + _c.value * .5),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 6});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(count, (_) => const Skeleton()),
      );
}

/// Shows a banner whenever the device has no connection, so people know which
/// features (chat, updates, attendance) need internet and which (notes) don't.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key});
  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool online = true;
  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_set);
    Connectivity().onConnectivityChanged.listen(_set);
  }

  void _set(List<ConnectivityResult> r) {
    if (!mounted) return;
    setState(() => online = r.any((e) => e != ConnectivityResult.none));
  }

  @override
  Widget build(BuildContext context) {
    if (online) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: HC.peach,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Text(
        'Offline - chats, attendance & updates need internet. Study Tools still work.',
        style: TextStyle(color: HC.ink, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

extension GradScale on LinearGradient {
  LinearGradient scale(double o) => LinearGradient(
        colors: colors.map((c) => c.withOpacity(o)).toList(),
        begin: begin,
        end: end,
      );
}
