import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/theme_service.dart';
import '../widgets/common.dart';

const String kPrivacyUrl =
    'https://onyecheretochukwu.github.io/quickcalc-privacy/';

/// Default / Light / Dark switch, used on the More tab and in Settings.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) {
        return SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('Default'),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {ThemeService.instance.mode},
          onSelectionChanged: (s) => ThemeService.instance.setMode(s.first),
        );
      },
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Theme')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Default follows your phone\'s light/dark setting.'),
          const SizedBox(height: 12),
          const ThemePicker(),
          const SizedBox(height: 28),
          Text('Accent colour', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: ThemeService.instance,
            builder: (context, _) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in ThemeService.accents.entries)
                    ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: e.value, radius: 8),
                      label: Text(e.key),
                      selected: ThemeService.instance.accent == e.key,
                      onSelected: (_) => ThemeService.instance.setAccent(e.key),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Divider(),
          if (AdService.supported)
            FutureBuilder<bool>(
              future: AdService.instance.privacyOptionsRequired(),
              builder: (context, snap) {
                if (snap.data != true) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Ad privacy choices'),
                  subtitle: const Text('Change your consent for personalised ads'),
                  onTap: AdService.instance.showPrivacyOptions,
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text(kPrivacyUrl),
            trailing: const Icon(Icons.copy, size: 18),
            onTap: () => copyText(context, kPrivacyUrl),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('QuickCalc'),
            subtitle: Text(
              'Scientific calculator, money tools, converters, '
              'formula library, timer and stopwatch. Works offline.',
            ),
          ),
        ],
      ),
    );
  }
}
