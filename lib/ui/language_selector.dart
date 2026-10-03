import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../l10n/locale_controller.dart';

class LanguageSelectorButton extends StatelessWidget {
  const LanguageSelectorButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<AppLocaleController>();

    return PopupMenuButton<String>(
      tooltip: L10n.text('Language'),
      initialValue: locale.code,
      onSelected: (code) => context.read<AppLocaleController>().setLocale(code),
      itemBuilder: (_) => [
        _item('en', 'English', locale.code),
        _item('fa', 'Dari', locale.code),
        _item('ps', 'Pashto', locale.code),
      ],
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_outlined, size: 20),
                  const SizedBox(width: 6),
                  Text(_label(locale.code)),
                ],
              ),
            )
          : ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text('Language'),
              subtitle: Text(_label(locale.code)),
              trailing: const Icon(Icons.chevron_right),
            ),
    );
  }

  PopupMenuItem<String> _item(String code, String label, String selected) =>
      PopupMenuItem<String>(
        value: code,
        child: Row(
          children: [
            Icon(
              code == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      );

  String _label(String code) => switch (code) {
    'fa' => 'Dari',
    'ps' => 'Pashto',
    _ => 'English',
  };
}
