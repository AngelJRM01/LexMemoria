import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const ink = Color(0xff17365d);
const teal = Color(0xff0e9f91);

class Paper extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Paper(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xff1b2b3d)
          : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .12))),
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: padding,
          child: SizedBox(width: double.infinity, child: child)));
}

class Badge extends StatelessWidget {
  final String text;
  final bool warning;
  const Badge(this.text, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: warning ? const Color(0xffffefcf) : const Color(0xffe3f4f0),
          borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: warning
                  ? const Color(0xff76500c)
                  : const Color(0xff08665e))));
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                  children: children))));
}

/// Search controls stay visible while results scroll. Compact landscape layouts
/// let the whole page scroll so the keyboard never traps the results.
class SearchPageBody extends StatelessWidget {
  final List<Widget> header, children;
  final IndexedWidgetBuilder? resultBuilder;
  final int resultCount;
  final ScrollController? resultsController;
  const SearchPageBody(
      {super.key,
      required this.header,
      this.children = const [],
      this.resultBuilder,
      this.resultsController,
      this.resultCount = 0});
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: LayoutBuilder(builder: (context, size) {
                if (size.maxHeight < 440) {
                  return ListView.builder(
                      controller: resultsController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 56),
                      itemCount: header.length + children.length + resultCount,
                      itemBuilder: (context, i) => i < header.length
                          ? header[i]
                          : i < header.length + children.length
                              ? children[i - header.length]
                              : resultBuilder!(context,
                                  i - header.length - children.length));
                }
                return Column(children: [
                  ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: size.maxHeight * .48),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: header))),
                  Expanded(
                      child: ListView.builder(
                          controller: resultsController,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 56),
                          itemCount: children.length + resultCount,
                          itemBuilder: (context, i) => i < children.length
                              ? children[i]
                              : resultBuilder!(context, i - children.length))),
                ]);
              }))));
}

class Details extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const Details(this.title, {super.key, required this.children});
  @override
  Widget build(BuildContext context) => ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 20),
      title: Text(title),
      children: children
          .map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(alignment: Alignment.centerLeft, child: w)))
          .toList());
}

class Section extends StatelessWidget {
  final String title;
  final Widget? action;
  const Section(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 14),
      child: Row(children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null) action!
      ]));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final Widget? action;
  const EmptyState(
      {super.key,
      this.icon = Icons.auto_stories_outlined,
      required this.title,
      required this.detail,
      this.action});
  @override
  Widget build(BuildContext context) => Paper(
          child: Column(children: [
        Icon(icon, size: 42, color: teal),
        const SizedBox(height: 16),
        Text(title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 18), child: action!)
      ]));
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

Future<void> perform(BuildContext context, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) toast(context, success);
  } catch (e) {
    if (context.mounted) {
      toast(context, e.toString().replaceFirst('Bad state: ', ''));
    }
  }
}

Future<void> openSource(BuildContext context, String source) async {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme != 'https') {
    toast(context, 'La fuente debe ser una dirección HTTPS válida.');
    return;
  }
  await perform(context, () async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError(
          'No se puede abrir la fuente. Copia el enlace e inténtalo de nuevo.');
    }
  });
}

void push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
        context: context,
        builder: (c) =>
            AlertDialog(title: Text(title), content: Text(body), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Confirmar'))
            ])) ??
    false;
