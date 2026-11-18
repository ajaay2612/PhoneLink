import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'app_icon.dart';
import 'design.dart';
import 'fs_api.dart';

class RecentImagesPanel extends StatelessWidget {
  const RecentImagesPanel({
    super.key,
    required this.fs,
    required this.images,
    required this.loading,
    required this.error,
    required this.onDownload,
    required this.onLoadMore,
    required this.hasMore,
    required this.revision,
  });
  final RemoteFs? fs;
  final int revision;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final List<RemoteImage> images;
  final bool loading;
  final String? error;
  final Future<void> Function(RemoteImage)? onDownload;

  Widget _image(RemoteImage image, {bool thumbnail = true}) =>
      FutureBuilder<Uint8List>(
        future: fs!.imageBytes(
          image.path,
          thumbnail: thumbnail,
          version: '${image.modified}-${image.size}-$revision',
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: AppIcon(
                Icons.insert_drive_file_outlined,
                size: 24,
                color: muted,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Image.memory(
            snapshot.data!,
            fit: thumbnail ? BoxFit.cover : BoxFit.contain,
            cacheWidth: thumbnail ? 480 : 1600,
            errorBuilder: (_, _, _) => Center(
              child: AppIcon(Icons.insert_drive_file_outlined, color: muted),
            ),
          );
        },
      );

  Future<void> _preview(BuildContext context, RemoteImage image) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: SizedBox(
            width: 800,
            height: 640,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          image.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close image',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: AppIcon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: _image(image, thumbnail: false),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: onDownload == null
                        ? null
                        : () {
                            Navigator.pop(dialogContext);
                            onDownload!(image);
                          },
                    icon: AppIcon(Icons.download_rounded, size: 18),
                    label: Text('Save to PhoneLink downloads'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Surface(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent images',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${images.length}${hasMore ? '+' : ''}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        const Divider(),
        if (loading) LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: fs == null
              ? EmptyState(
                  icon: Icons.devices_rounded,
                  title: 'Photos from your phone',
                  message: 'Connect your phone to see its recent images.',
                )
              : error != null
              ? EmptyState(
                  icon: Icons.info_outline_rounded,
                  title: 'Cannot load images',
                  message: error!,
                )
              : images.isEmpty
              ? EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: loading
                      ? 'Finding recent images…'
                      : 'No recent images',
                  message: loading
                      ? 'Reading your phone’s photo folders.'
                      : 'Photos from DCIM, Pictures and Downloads appear here. Use Refresh in the file menu to check again.',
                )
              : GridView.builder(
                  key: ValueKey('recent-images-$revision'),
                  padding: EdgeInsets.all(12),
                  itemCount: images.length + (hasMore ? 1 : 0),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    if (index == images.length) {
                      return Center(
                        child: TextButton(
                          onPressed: loading ? null : onLoadMore,
                          child: Text(loading ? 'Loading…' : 'Load more'),
                        ),
                      );
                    }
                    final image = images[index];
                    return Semantics(
                      label: image.name,
                      button: true,
                      child: Material(
                        color: canvas,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _image(image),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _preview(context, image),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
