import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'app_icon.dart';
import 'design.dart';

/// Uses the app's own local browser on Linux, without an external dialog process.
Future<List<File>?> pickLocalFiles(BuildContext context, String home) =>
    showDialog<List<File>>(
      context: context,
      useRootNavigator: true,
      routeSettings: RouteSettings(name: '/send-files'),
      builder: (_) => _LocalFilePicker(home: home),
    );

class _LocalFilePicker extends StatefulWidget {
  const _LocalFilePicker({required this.home});
  final String home;
  @override
  State<_LocalFilePicker> createState() => _LocalFilePickerState();
}

class _LocalFilePickerState extends State<_LocalFilePicker> {
  late String directory;
  List<FileSystemEntity> entries = [];
  final selected = <String>{};
  bool loading = true;
  String? error;
  int request = 0;

  @override
  void initState() {
    super.initState();
    directory = widget.home;
    _load(directory);
  }

  Future<void> _load(String target) async {
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
      directory = target;
    });
    try {
      final list = await Directory(target)
          .list(followLinks: false)
          .where(
            (entry) =>
                !p.basename(entry.path).startsWith('.') &&
                (entry is Directory || entry is File),
          )
          .toList();
      list.sort((a, b) {
        if ((a is Directory) != (b is Directory)) {
          return a is Directory ? -1 : 1;
        }
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      if (mounted && current == request) {
        setState(() {
          entries = list;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && current == request) {
        setState(() {
          entries = [];
          loading = false;
          error = 'Cannot open folder: $e';
        });
      }
    }
  }

  void _toggle(String path) => setState(() {
    if (!selected.add(path)) selected.remove(path);
  });

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 720,
      height: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose files to send',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close file chooser',
                  onPressed: () => Navigator.pop(context),
                  icon: AppIcon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Parent folder',
                  onPressed: directory == p.dirname(directory) || loading
                      ? null
                      : () => _load(p.dirname(directory)),
                  icon: AppIcon(Icons.arrow_upward_rounded, size: 20),
                ),
                TextButton(
                  onPressed: loading ? null : () => _load(widget.home),
                  child: Text('Home'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    directory,
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (loading) LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: error != null
                ? EmptyState(
                    icon: Icons.folder_outlined,
                    title: 'Folder unavailable',
                    message: error!,
                  )
                : entries.isEmpty && !loading
                ? EmptyState(
                    icon: Icons.folder_outlined,
                    title: 'No files here',
                    message: 'Choose a different folder to find files.',
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final folder = entry is Directory;
                      return ListTile(
                        leading: AppIcon(
                          folder
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 20,
                          color: muted,
                        ),
                        title: Text(
                          p.basename(entry.path),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13),
                        ),
                        trailing: folder
                            ? AppIcon(Icons.chevron_right_rounded, size: 18)
                            : Checkbox(
                                value: selected.contains(entry.path),
                                onChanged: (_) => _toggle(entry.path),
                              ),
                        onTap: loading
                            ? null
                            : () => folder
                                  ? _load(entry.path)
                                  : _toggle(entry.path),
                      );
                    },
                  ),
          ),
          const Divider(),
          Padding(
            padding: EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  '${selected.length} selected',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          selected.map(File.new).toList(),
                        ),
                  child: Text('Send selected files'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
