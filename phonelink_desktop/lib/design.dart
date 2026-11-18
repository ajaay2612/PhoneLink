import 'package:flutter/material.dart';
import 'fs_api.dart';
import 'app_icon.dart';

final desktopDarkMode = ValueNotifier<bool>(false);
Color get ink =>
    desktopDarkMode.value ? const Color(0xFFE8E8E7) : const Color(0xFF182D29);
Color get muted =>
    desktopDarkMode.value ? const Color(0xFFA7AAA8) : const Color(0xFF63726C);
Color get accent =>
    desktopDarkMode.value ? const Color(0xFF91D4B1) : const Color(0xFF23634D);
Color get canvas =>
    desktopDarkMode.value ? const Color(0xFF101112) : const Color(0xFFF6F7F3);
Color get surface =>
    desktopDarkMode.value ? const Color(0xFF191B1C) : Colors.white;
Color get line =>
    desktopDarkMode.value ? const Color(0xFF252728) : const Color(0xFFEAEEE8);
Color get selection =>
    desktopDarkMode.value ? const Color(0xFF2A302D) : const Color(0xFFE1EEE5);
Color get onAccent =>
    desktopDarkMode.value ? const Color(0xFF143526) : Colors.white;

ThemeData phoneLinkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: desktopDarkMode.value ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: accent,
        onPrimary: onAccent,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: muted,
        outline: line,
        outlineVariant: line,
        surfaceContainerHighest: selection,
        error: desktopDarkMode.value
            ? const Color(0xFFFFB4AB)
            : const Color(0xFFB3261E),
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  final label = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  final controlStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    shape: WidgetStatePropertyAll(shape),
    textStyle: WidgetStatePropertyAll(label),
    iconSize: const WidgetStatePropertyAll(18),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Manrope',
    iconTheme: IconThemeData(size: 20, color: muted),
    splashFactory: InkRipple.splashFactory,
    hoverColor: ink.withValues(alpha: .05),
    focusColor: accent.withValues(alpha: .12),
    highlightColor: ink.withValues(alpha: .04),
    splashColor: accent.withValues(alpha: .10),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
      labelLarge: label,
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      toolbarHeight: 56,
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(style: controlStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: controlStyle.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? muted.withValues(alpha: .45)
              : ink,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused) ? accent : line,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: controlStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(accent),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        iconSize: const WidgetStatePropertyAll(20),
        shape: WidgetStatePropertyAll(shape),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
      minLeadingWidth: 20,
      horizontalTitleGap: 12,
      iconColor: muted,
      textColor: ink,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        height: 1.5,
        color: muted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: canvas,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: muted, fontSize: 14),
      labelStyle: TextStyle(color: muted, fontSize: 14),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: .48),
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: line),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        height: 1.5,
        color: muted,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line),
      ),
      textStyle: TextStyle(fontFamily: 'Manrope', color: ink, fontSize: 14),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: TextStyle(
        color: canvas,
        fontFamily: 'Manrope',
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: surface,
      indicatorColor: selection,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(fontFamily: 'Manrope', fontSize: 12, color: canvas),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: AppIcon(Icons.link_rounded, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 10),
      const Flexible(
        child: Text(
          'Fonelink',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            letterSpacing: -.7,
          ),
        ),
      ),
    ],
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.connected, this.label});
  final bool connected;
  final String? label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: connected
            ? (desktopDarkMode.value ? Color(0xFF2B4032) : Color(0xFFE5F0E7))
            : (desktopDarkMode.value ? Color(0xFF3C382A) : Color(0xFFF0EDE3)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            Icons.circle,
            size: 7,
            color: connected
                ? accent
                : (desktopDarkMode.value
                      ? Color(0xFFDBC180)
                      : Color(0xFF8A6A2C)),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label ?? (connected ? 'Connected' : 'Not connected'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: connected
                    ? accent
                    : (desktopDarkMode.value
                          ? Color(0xFFDBC180)
                          : Color(0xFF806126)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    this.subtitle = '',
    this.trailing,
  });
  final String title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: muted, height: 1.5)),
            ],
          ],
        );
        if (trailing != null && bounds.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(alignment: Alignment.centerLeft, child: heading),
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          ),
        );
      },
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (desktopDarkMode.value
                    ? Color(0xFF2B4032)
                    : Color(0xFFEAF0E8)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AppIcon(icon, color: accent, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.6),
            ),
            if (action != null) ...[SizedBox(height: 20), action!],
          ],
        ),
      ),
    ),
  );
}

void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class FileBrowser extends StatelessWidget {
  const FileBrowser({
    super.key,
    required this.device,
    required this.available,
    required this.busy,
    required this.path,
    required this.entries,
    required this.status,
    required this.onRefresh,
    required this.onUpload,
    required this.onUp,
    required this.onOpen,
    this.extraActions = const [],
    required this.showHidden,
    required this.onToggleHidden,
    this.onPair,
  });
  final String device, path, status;
  final bool available, busy;
  final bool showHidden;
  final VoidCallback onToggleHidden;
  final List<FEntry> entries;
  final VoidCallback onRefresh, onUpload, onUp;
  final void Function(FEntry) onOpen;
  final List<Widget> extraActions;
  final VoidCallback? onPair;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (extraActions.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: extraActions),
        const SizedBox(height: 20),
      ],
      Expanded(
        child: Surface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelHeader(
                horizontalPadding: 12,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Parent folder',
                      onPressed: available && path != '/' && !busy
                          ? onUp
                          : null,
                      icon: AppIcon(Icons.arrow_upward_rounded, size: 20),
                    ),
                    const SizedBox(width: 6),
                    AppIcon(Icons.folder_outlined, color: muted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$device  /  ${path == '/' ? 'Shared storage' : path.replaceFirst(RegExp(r'^/'), '')}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '${entries.length} items',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      clipBehavior: Clip.antiAlias,
                      tooltip: 'File options',
                      icon: AppIcon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: muted,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case 'hidden':
                            onToggleHidden();
                          case 'refresh':
                            onRefresh();
                          case 'send':
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) onUpload();
                            });
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'hidden',
                          child: Text(
                            showHidden
                                ? 'Hide hidden files'
                                : 'Show hidden files',
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'refresh',
                          enabled: available && !busy,
                          child: Row(
                            children: [
                              AppIcon(Icons.refresh_rounded, size: 18),
                              SizedBox(width: 12),
                              Text('Refresh'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'send',
                          child: Row(
                            children: [
                              AppIcon(Icons.add_rounded, size: 18),
                              SizedBox(width: 12),
                              Text('Send files'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (busy) LinearProgressIndicator(minHeight: 2),
              if (status.isNotEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Semantics(
                    liveRegion: true,
                    child: SelectableText(
                      status,
                      style: TextStyle(color: muted),
                    ),
                  ),
                ),
              Expanded(
                child: !available
                    ? EmptyState(
                        icon: Icons.devices_rounded,
                        title: 'Your files, within reach',
                        message:
                            'Connect your $device on the same network to browse and transfer files.',
                        action: onPair == null
                            ? null
                            : OutlinedButton(
                                onPressed: onPair,
                                child: Text('Connect a device'),
                              ),
                      )
                    : entries.isEmpty
                    ? EmptyState(
                        icon: Icons.folder_open_rounded,
                        title: busy ? 'Opening folder…' : 'No files to show',
                        message: busy
                            ? 'Reading the folder on your $device.'
                            : 'Refresh to load this folder, or send a file here.',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const Divider(indent: 68, endIndent: 20),
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          return ListTile(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 3,
                            ),
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: e.isDir
                                    ? (desktopDarkMode.value
                                          ? Color(0xFF3B3222)
                                          : Color(0xFFF7EDDA))
                                    : (desktopDarkMode.value
                                          ? Color(0xFF303334)
                                          : Color(0xFFEDF1ED)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: AppIcon(
                                e.isDir
                                    ? Icons.folder_rounded
                                    : Icons.insert_drive_file_outlined,
                                color: e.isDir
                                    ? (desktopDarkMode.value
                                          ? Color(0xFFDBC180)
                                          : Color(0xFFA57B32))
                                    : muted,
                                size: 21,
                              ),
                            ),
                            title: Text(
                              e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              e.isDir ? 'Folder' : fmtSize(e.size),
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            trailing: AppIcon(
                              e.isDir
                                  ? Icons.chevron_right_rounded
                                  : Icons.download_rounded,
                              color: muted,
                              size: 20,
                            ),
                            onTap: busy ? null : () => onOpen(e),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The connected phone, without an extra PC illustration.
class PhoneMockup extends StatelessWidget {
  const PhoneMockup({super.key, required this.connected, this.battery});
  final bool connected;
  final int? battery;
  @override
  Widget build(BuildContext context) => Semantics(
    label: connected ? 'Connected phone' : 'Disconnected phone',
    child: Container(
      width: 84,
      height: 140,
      padding: EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: desktopDarkMode.value ? Color(0xFF353A3D) : Color(0xFFDCE6DC),
        border: Border.all(color: muted, width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: desktopDarkMode.value
              ? Color(0xFF0D1110)
              : connected
              ? Color(0xFF182D29)
              : Color(0xFFBAC5BA),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          children: [
            const SizedBox(height: 7),
            Container(
              width: 22,
              height: 4,
              decoration: BoxDecoration(
                color: desktopDarkMode.value
                    ? Color(0xFF69746E)
                    : Color(0xFF91A99A),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Spacer(),
            AppIcon(
              connected ? Icons.link_rounded : Icons.link_off_rounded,
              size: 26,
              color: desktopDarkMode.value
                  ? (connected ? accent : muted)
                  : Color(0xFFD8EBCD),
            ),
            const Spacer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

class PhoneBatteryIcon extends StatelessWidget {
  const PhoneBatteryIcon({super.key, required this.level});
  final int? level;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 12,
    child: Row(
      children: [
        Container(
          width: 18,
          height: 11,
          padding: EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            border: Border.all(color: muted, width: 1.2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (level ?? 0).clamp(0, 100) / 100,
              child: Container(
                color: level != null && level! <= 15
                    ? Color(0xFFB3261E)
                    : muted,
              ),
            ),
          ),
        ),
        const SizedBox(width: 1),
        Container(width: 2, height: 5, color: muted),
      ],
    ),
  );
}

/// Compact visual toggle with a full keyboard and touch target.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: value,
    enabled: onChanged != null,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 48,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 22,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? accent : line,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: value ? onAccent : muted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// App-owned dialogs share the same padding, type, action spacing and clipping.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DefaultTextStyle(
                style: Theme.of(context).textTheme.titleLarge!,
                child: title,
              ),
              const SizedBox(height: 12),
              DefaultTextStyle(
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(color: muted),
                child: content,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// One header rhythm for side-by-side workspace panels.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.child,
    this.horizontalPadding = 16,
  });
  final Widget child;
  final double horizontalPadding;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 4),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  );
}
