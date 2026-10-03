import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/locale_controller.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().locale.languageCode;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LanguageTile(
          code: 'en',
          title: context.tr('common_english'),
          subtitle: 'English',
          selected: locale == 'en',
        ),
        const SizedBox(height: 10),
        _LanguageTile(
          code: 'fa',
          title: context.tr('common_dari'),
          subtitle: 'دری',
          selected: locale == 'fa',
        ),
        const SizedBox(height: 10),
        _LanguageTile(
          code: 'ps',
          title: context.tr('common_pashto'),
          subtitle: 'پښتو',
          selected: locale == 'ps',
        ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.selected,
  });

  final String code;
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.language_outlined,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: selected
          ? null
          : () => context.read<LocaleController>().setLanguage(code),
    ),
  );
}
