import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const ink = Color(0xff17365d);
const teal = Color(0xff0e9f91);

class Paper extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Paper({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xff1b2b3d) : Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .12))),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: SizedBox(width: double.infinity, child: child)));

}
class Badge extends StatelessWidget {
  final String text;
  final bool warning;
  const Badge(this.text, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: warning ? const Color(0xffffefcf) : const Color(0xffe3f4f0), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: warning ? const Color(0xff76500c) : const Color(0xff08665e))));
}
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 840),
    child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: children)));
}
class Section extends StatelessWidget {
  final String title;
  final Widget? action;
  const Section(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 28, bottom: 14),
    child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), if (action != null) action!]));
}
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final Widget? action;
  const EmptyState({super.key, this.icon = Icons.auto_stories_outlined, required this.title, required this.detail, this.action});
  @override
  Widget build(BuildContext context) => Paper(child: Column(children: [Icon(icon, size: 42, color: teal),
    const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
    const SizedBox(height: 8), Text(detail, textAlign: TextAlign.center), if (action != null) Padding(padding: const EdgeInsets.only(top: 18), child: action!)]));
}
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
Future<void> perform(BuildContext context, Future<void> Function() action, {String? success}) async {
  try { await action(); if (context.mounted && success != null) toast(context, success); }
  catch (e) { if (context.mounted) toast(context, e.toString().replaceFirst('Bad state: ', '')); }
}
Future<void> openSource(BuildContext context, String source) async {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme != 'https') { toast(context, 'La fuente debe ser una dirección HTTPS válida.'); return; }
  await perform(context, () async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('No se puede abrir la fuente. Copia el enlace e inténtalo de nuevo.');
  });
}
void push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
Future<bool> confirm(BuildContext context, String title, String body) async => await showDialog<bool>(context: context,
  builder: (c) => AlertDialog(title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar'))])) ?? false;
