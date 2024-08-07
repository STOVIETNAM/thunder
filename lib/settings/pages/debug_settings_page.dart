import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import 'package:path/path.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:extended_image/extended_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:thunder/core/enums/local_settings.dart';
import 'package:thunder/core/singletons/preferences.dart';
import 'package:thunder/notification/enums/notification_type.dart';
import 'package:thunder/notification/shared/android_notification.dart';
import 'package:thunder/notification/shared/notification_server.dart';
import 'package:thunder/notification/utils/local_notifications.dart';

import 'package:thunder/shared/dialogs.dart';
import 'package:thunder/shared/divider.dart';
import 'package:thunder/shared/snackbar.dart';
import 'package:thunder/thunder/bloc/thunder_bloc.dart';
import 'package:thunder/settings/widgets/settings_list_tile.dart';
import 'package:thunder/utils/cache.dart';
import 'package:thunder/utils/constants.dart';
import 'package:unifiedpush/unifiedpush.dart';

class DebugSettingsPage extends StatefulWidget {
  final LocalSettings? settingToHighlight;

  const DebugSettingsPage({super.key, this.settingToHighlight});

  @override
  State<DebugSettingsPage> createState() => _DebugSettingsPageState();
}

class _DebugSettingsPageState extends State<DebugSettingsPage> {
  NotificationType? inboxNotificationType = NotificationType.none;
  bool areNotificationsAllowed = false;
  String? unifiedPushDistributorApp;
  int unifiedPushDistributorAppCount = 0;
  String? pushNotificationServer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final SharedPreferences prefs = (await UserPreferences.instance).sharedPreferences;
      inboxNotificationType = NotificationType.values.byName(prefs.getString(LocalSettings.inboxNotificationType.name) ?? NotificationType.none.name);

      if (!kIsWeb && Platform.isAndroid) {
        AndroidFlutterLocalNotificationsPlugin? androidFlutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        areNotificationsAllowed = await androidFlutterLocalNotificationsPlugin?.areNotificationsEnabled() ?? false;

        unifiedPushDistributorApp = await UnifiedPush.getDistributor();
        unifiedPushDistributorAppCount = (await UnifiedPush.getDistributors()).length;
      } else if (!kIsWeb && Platform.isIOS) {
        IOSFlutterLocalNotificationsPlugin? iosFlutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

        // TODO: Not sure if this is the right check for iOS.
        areNotificationsAllowed = (await iosFlutterLocalNotificationsPlugin?.checkPermissions())?.isEnabled ?? false;
      }

      pushNotificationServer = prefs.getString(LocalSettings.pushNotificationServer.name) ?? THUNDER_SERVER_URL;

      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(l10n.debug),
            centerTitle: false,
            toolbarHeight: 70.0,
            pinned: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0, bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.resetPreferencesAndData, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8.0),
                  Text(
                    l10n.debugDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsListTile(
              icon: Icons.co_present_rounded,
              description: l10n.deleteLocalPreferences,
              widget: const SizedBox(
                height: 42.0,
                child: Icon(Icons.chevron_right_rounded),
              ),
              onTap: () async {
                showThunderDialog<void>(
                  context: context,
                  title: l10n.deleteLocalPreferences,
                  contentText: l10n.deleteLocalPreferencesDescription,
                  onSecondaryButtonPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
                  secondaryButtonText: l10n.cancel,
                  onPrimaryButtonPressed: (dialogContext, _) {
                    SharedPreferences.getInstance().then((prefs) async {
                      await prefs.clear();

                      if (context.mounted) {
                        context.read<ThunderBloc>().add(UserPreferencesChangeEvent());
                        showSnackbar(AppLocalizations.of(context)!.clearedUserPreferences);
                      }
                    });

                    Navigator.of(dialogContext).pop();
                  },
                  primaryButtonText: l10n.clearPreferences,
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
          SliverToBoxAdapter(
            child: SettingsListTile(
              icon: Icons.data_array_rounded,
              description: l10n.deleteLocalDatabase,
              widget: const SizedBox(
                height: 42.0,
                child: Icon(Icons.chevron_right_rounded),
              ),
              onTap: () async {
                showThunderDialog<void>(
                  context: context,
                  title: l10n.deleteLocalDatabase,
                  contentText: l10n.deleteLocalDatabaseDescription,
                  onSecondaryButtonPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
                  secondaryButtonText: l10n.cancel,
                  onPrimaryButtonPressed: (dialogContext, _) async {
                    String path = join(await getDatabasesPath(), 'thunder.db');

                    final dbFolder = await getApplicationDocumentsDirectory();
                    final file = File(join(dbFolder.path, 'thunder.sqlite'));

                    await databaseFactory.deleteDatabase(file.path);

                    if (context.mounted) {
                      showSnackbar(AppLocalizations.of(context)!.clearedDatabase);
                      Navigator.of(context).pop();
                    }
                  },
                  primaryButtonText: l10n.clearDatabase,
                );
              },
            ),
          ),
          const ThunderDivider(sliver: true),
          SliverToBoxAdapter(
            child: FutureBuilder<int>(
              future: getExtendedImageCacheSize(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return SettingsListTile(
                    icon: Icons.data_saver_off_rounded,
                    description: l10n.clearCache('${(snapshot.data! / (1024 * 1024)).toStringAsFixed(2)} MB'),
                    widget: const SizedBox(
                      height: 42.0,
                      child: Icon(Icons.chevron_right_rounded),
                    ),
                    onTap: () async {
                      await clearDiskCachedImages();
                      if (context.mounted) showSnackbar(l10n.clearedCache);
                      setState(() {}); // Trigger a rebuild to refresh the cache size
                    },
                  );
                }
                return Container();
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.notifications(2), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8.0),
                  Text(
                    l10n.debugNotificationsDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 6.0, bottom: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(l10n.status, style: theme.textTheme.titleSmall)],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsListTile(
              icon: Icons.info_rounded,
              description: l10n.currentNotificationsMode(inboxNotificationType.toString()),
              widget: Container(),
              onTap: null,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
          SliverToBoxAdapter(
            child: SettingsListTile(
              icon: Icons.info_rounded,
              description: l10n.areNotificationsAllowedBySystem(areNotificationsAllowed ? l10n.yes : l10n.no),
              widget: Container(),
              onTap: null,
            ),
          ),
          if (!kIsWeb && Platform.isAndroid && kDebugMode) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
            SliverToBoxAdapter(
              child: SettingsListTile(
                icon: Icons.info_rounded,
                description: l10n.unifiedPushDistributorApp(unifiedPushDistributorApp ?? l10n.none, unifiedPushDistributorAppCount),
                widget: Container(),
                onTap: null,
              ),
            ),
          ],
          if (!kIsWeb && Platform.isAndroid) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 6.0, bottom: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(l10n.localNotifications, style: theme.textTheme.titleSmall)],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsListTile(
                icon: Icons.notifications_rounded,
                description: l10n.sendTestLocalNotification,
                widget: const SizedBox(
                  height: 42.0,
                  child: Icon(Icons.chevron_right_rounded),
                ),
                onTap: inboxNotificationType == NotificationType.local
                    ? () {
                        showTestAndroidNotification();
                      }
                    : null,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
            SliverToBoxAdapter(
              child: SettingsListTile(
                icon: Icons.circle_notifications_rounded,
                description: l10n.sendBackgroundTestLocalNotification,
                widget: const SizedBox(
                  height: 42.0,
                  child: Icon(Icons.chevron_right_rounded),
                ),
                onTap: inboxNotificationType == NotificationType.local
                    ? () async {
                        bool result = false;

                        await showThunderDialog(
                          context: context,
                          title: l10n.confirm,
                          contentWidgetBuilder: (setPrimaryButtonEnabled) => Text(l10n.testBackgroundNotificationDescription),
                          primaryButtonText: l10n.confirm,
                          primaryButtonInitialEnabled: true,
                          onPrimaryButtonPressed: (dialogContext, setPrimaryButtonEnabled) {
                            dialogContext.pop();
                            result = true;
                          },
                          secondaryButtonText: l10n.cancel,
                          onSecondaryButtonPressed: (dialogContext) => dialogContext.pop(),
                        );

                        if (result) {
                          // Hook up a callback to generate a background notification.
                          // The next time Thunder starts, this will get reset
                          await disableBackgroundFetch();
                          await initTestBackgroundFetch();
                          initTestHeadlessBackgroundFetch();

                          SystemNavigator.pop();
                        }
                      }
                    : null,
              ),
            ),
            if (kDebugMode) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 6.0, bottom: 6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(l10n.unifiedpush, style: theme.textTheme.titleSmall)],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SettingsListTile(
                  icon: Icons.notifications_rounded,
                  description: l10n.sendTestUnifiedPushNotification,
                  widget: const SizedBox(
                    height: 42.0,
                    child: Icon(Icons.chevron_right_rounded),
                  ),
                  onTap: inboxNotificationType == NotificationType.unifiedPush
                      ? () async {
                          if (await requestTestNotification()) {
                            showSnackbar(l10n.sentRequestForTestNotification);
                          } else {
                            showSnackbar(l10n.failedToCommunicateWithThunderNotificationServer(pushNotificationServer ?? ''));
                          }
                        }
                      : null,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
              SliverToBoxAdapter(
                child: SettingsListTile(
                  icon: Icons.circle_notifications_rounded,
                  description: l10n.sendBackgroundTestUnifiedPushNotification,
                  widget: const SizedBox(
                    height: 42.0,
                    child: Icon(Icons.chevron_right_rounded),
                  ),
                  onTap: inboxNotificationType == NotificationType.unifiedPush
                      ? () async {
                          bool result = false;

                          await showThunderDialog(
                            context: context,
                            title: l10n.confirm,
                            contentWidgetBuilder: (setPrimaryButtonEnabled) => Text(l10n.testBackgroundUnifiedPushNotificationDescription),
                            primaryButtonText: l10n.confirm,
                            primaryButtonInitialEnabled: true,
                            onPrimaryButtonPressed: (dialogContext, setPrimaryButtonEnabled) {
                              dialogContext.pop();
                              result = true;
                            },
                            secondaryButtonText: l10n.cancel,
                            onSecondaryButtonPressed: (dialogContext) => dialogContext.pop(),
                          );

                          if (result) {
                            if (await requestTestNotification()) {
                              showSnackbar(l10n.sentRequestForTestNotification);
                            } else {
                              showSnackbar(l10n.failedToCommunicateWithThunderNotificationServer(pushNotificationServer ?? ''));
                            }

                            SystemNavigator.pop();
                          }
                        }
                      : null,
                ),
              ),
            ],
          ],
          const ThunderDivider(sliver: true),
          SliverToBoxAdapter(
            child: SettingsListTile(
              icon: Icons.edit_notifications_rounded,
              description: l10n.changeNotificationSettings,
              widget: const SizedBox(
                height: 42.0,
                child: Icon(Icons.chevron_right_rounded),
              ),
              onTap: () {
                GoRouter.of(context).push(SETTINGS_GENERAL_PAGE, extra: [
                  context.read<ThunderBloc>(),
                  LocalSettings.inboxNotificationType,
                ]);
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}
