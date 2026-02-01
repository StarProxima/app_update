import 'package:pub_semver/pub_semver.dart';

import '../../entities/update_platform.dart';
import '../../entities/update_source_name.dart';
import '../update_app_settings/update_app_settings_data.dart';
import '../update_content/update_content_data.dart';
import '../update_settings/update_settings_data.dart';

class Update {
  final Version version;
  final DateTime? date;
  final UpdateSourceName sourceName;
  final UpdatePlatform platform;
  final UpdateContentData rawContent;
  final UpdateContentData content;
  final UpdateSettingsData settings;
  final UpdateAppSettingsData appSettings;
  final Map<String, dynamic>? customParams;

  const Update({
    required this.version,
    required this.date,
    required this.sourceName,
    required this.platform,
    required this.rawContent,
    required this.content,
    required this.settings,
    required this.appSettings,
    required this.customParams,
  });

  /// <version>_<year>-<month>-<day>
  String get updateName =>
      '$version${date != null ? '_${date!.year}-${date!.month}-${date!.day}' : ''}';

  Update copyWith({
    Version? version,
    DateTime? date,
    UpdateSourceName? sourceName,
    UpdatePlatform? platform,
    UpdateContentData? rawContent,
    UpdateContentData? content,
    UpdateSettingsData? settings,
    UpdateAppSettingsData? appSettings,
    Map<String, dynamic>? customParams,
  }) =>
      Update(
        version: version ?? this.version,
        date: date ?? this.date,
        sourceName: sourceName ?? this.sourceName,
        platform: platform ?? this.platform,
        rawContent: rawContent ?? this.rawContent,
        content: content ?? this.content,
        settings: settings ?? this.settings,
        appSettings: appSettings ?? this.appSettings,
        customParams: customParams ?? this.customParams,
      );
}
