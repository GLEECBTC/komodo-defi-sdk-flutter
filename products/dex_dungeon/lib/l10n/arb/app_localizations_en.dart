// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get startVeryGoodGame => 'Start the Very Good Game';

  @override
  String get titleAppBarTitle => 'Dex Dungeon';

  @override
  String get titleButtonStart => 'Start';

  @override
  String loading(String label) {
    return 'Loading $label...';
  }

  @override
  String loadingPhaseLabel(String loadingPhase) {
    String _temp0 = intl.Intl.selectLogic(loadingPhase, {
      'audio': 'Delightful music',
      'images': 'Beautiful scenery',
      'other': ' ',
    });
    return '$_temp0';
  }

  @override
  String counterText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have tapped the unicorn $count times',
      one: 'You have tapped the unicorn 1 time',
    );
    return '$_temp0';
  }
}
