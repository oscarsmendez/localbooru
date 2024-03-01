import 'dart:io';
import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:localbooru/api/index.dart';
import 'package:localbooru/components/context_menu.dart';
import 'package:localbooru/components/headers.dart';
import 'package:localbooru/components/window_frame.dart';
import 'package:localbooru/utils/constants.dart';
import 'package:localbooru/utils/shared_prefs_widget.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:media_kit/media_kit.dart'; // Provides [Player], [Media], [Playlist] etc.
import 'package:media_kit_video/media_kit_video.dart'; // Provides [VideoController] & [Video] etc.        

class ImageView extends StatelessWidget {
    const ImageView({super.key, required this.image});

    final BooruImage image;

    @override
    Widget build(BuildContext context) {
        return OrientationBuilder(
            builder: (context, orientation) {
                if(orientation == Orientation.portrait) {
                    return ListView(
                        children: [
                            ImageViewDisplay(image),
                            ImageViewProprieties(image)
                        ],
                    );
                } else {
                    return Row(
                        children: [
                            Expanded(
                                child: ImageViewDisplay(image)
                            ),
                            ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 400.0),
                                child: ListView(
                                    children: [
                                        ImageViewProprieties(image, renderObject: context.findRenderObject(),)
                                    ],
                                )
                            )
                            
                        ],
                    );
                }
            },
        );
    }
}

class ImageViewDisplay extends StatefulWidget {
    const ImageViewDisplay(this.image, {super.key});

    final BooruImage image;

    @override
    State<ImageViewDisplay> createState() => _ImageViewDisplayState();
}

class _ImageViewDisplayState extends State<ImageViewDisplay> {
    void openContextMenu(Offset offset) {
        final RenderObject? overlay = Overlay.of(context).context.findRenderObject();
        showMenu(
            context: context,
            position: RelativeRect.fromRect(
                Rect.fromLTWH(offset.dx, offset.dy, 10, 10),
                Rect.fromLTWH(0, 0, overlay!.paintBounds.size.width, overlay.paintBounds.size.height),
            ),
            items: imageShareItems(widget.image)
        );
    }

    @override
    Widget build(BuildContext context) {
        return SharedPreferencesBuilder(
            builder: (context, prefs) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                    child: lookupMimeType(widget.image.filename)!.startsWith("video/") || ((prefs.getBool("gif_video") ?? settingsDefaults["gif_video"]) && lookupMimeType(widget.image.filename) == "image/gif")
                        ? VideoView(widget.image.path)
                        : MouseRegion(
                            cursor: SystemMouseCursors.zoomIn,
                            child: GestureDetector(
                                onTap: () => {
                                    context.push("/dialogs/zoom_image/${widget.image.id}")
                                },
                                onLongPressEnd: (tap) => openContextMenu(getOffsetRelativeToBox(offset: tap.globalPosition, renderObject: context.findRenderObject()!)),
                                onSecondaryTapDown: (tap) => openContextMenu(getOffsetRelativeToBox(offset: tap.globalPosition, renderObject: context.findRenderObject()!)),
                                child: Image.file(widget.image.getImage(), fit: BoxFit.contain),
                            ),
                        ),
                    ),
                ),
        );
    }
}

class VideoView extends StatefulWidget {
  const VideoView(this.path, {Key? key}) : super(key: key);
  
  final String path;
  
  @override
  State<VideoView> createState() => VideoViewState();
}

class VideoViewState extends State<VideoView> {
    late final player = Player();

    late final controller = VideoController(player);

    @override
    void initState() {
        super.initState();

        player.open(Media(widget.path), play: lookupMimeType(widget.path) == "image/gif");
        player.setPlaylistMode(PlaylistMode.single);
    }

    @override
    void dispose() {
        player.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width,
            child: Video(controller: controller, fill: Colors.transparent),
        );
    }
}

class ImageViewZoom extends StatelessWidget {
    const ImageViewZoom(this.image, {super.key});

    final BooruImage image;

    final Color _appBarColor = const Color.fromARGB(150, 0, 0, 0);

    @override
    Widget build(BuildContext context) {
        return Theme(
            data: ThemeData.dark(),
            child: Scaffold(
                extendBodyBehindAppBar: true,
                backgroundColor: Colors.transparent,
                appBar: WindowFrameAppBar(
                    title: "Zoom",
                    backgroundColor: _appBarColor,
                    appBar: AppBar(
                        backgroundColor: _appBarColor,
                        elevation: 0,
                        title: Text(image.filename),
                        actions: [
                            PopupMenuButton(
                                itemBuilder: (context) => imageShareItems(image),
                            )
                        ],
                    ),
                ),
                body: InteractiveViewer(
                    minScale: 0.1,
                    maxScale: double.infinity,
                    boundaryMargin: EdgeInsets.all((MediaQuery.of(context).size.width + MediaQuery.of(context).size.height) / 4),
                    child: Center(
                        child: Image.file(image.getImage())
                    )
                ),
            ),
        );
    }
}

class ImageViewProprieties extends StatelessWidget {
    const ImageViewProprieties(this.image, {super.key, this.renderObject});
    
    final BooruImage image;
    final RenderObject? renderObject;

    @override
    Widget build(BuildContext context) {
        final TextStyle linkText = TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline, decorationColor: Theme.of(context).colorScheme.primary);
        
        return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    const Header("Tags", padding: EdgeInsets.zero),
                    FutureBuilder(
                        future: getCurrentBooru().then((booru) => booru.separateTagsByType(image.tags.split(" "))),
                        builder: (context, snapshot) {
                            if (snapshot.hasData) {
                                final tags = snapshot.data!;
                                return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                        if (tags["artist"] != null && tags["artist"]!.isNotEmpty) ...[
                                            const SmallHeader("Artist", padding: EdgeInsets.only(top: 4)),
                                            Wrap(children: List.from(tags["artist"]!..sort()).map((e) {
                                                return Tag(e, color: SpecificTagsColors.artist,);
                                            }).toList())
                                        ],
                                        if (tags["character"] != null && tags["character"]!.isNotEmpty) ...[
                                            const SmallHeader("Character", padding: EdgeInsets.only(top: 4)),
                                            Wrap(children: List.from(tags["character"]!..sort()).map((e) {
                                                return Tag(e, color: SpecificTagsColors.character,);
                                            }).toList())
                                        ],
                                        if (tags["copyright"] != null && tags["copyright"]!.isNotEmpty) ...[
                                            const SmallHeader("Copyright", padding: EdgeInsets.only(top: 4)),
                                            Wrap(children: List.from(tags["copyright"]!..sort()).map((e) {
                                                return Tag(e, color: SpecificTagsColors.copyright,);
                                            }).toList())
                                        ],
                                        if (tags["species"] != null && tags["species"]!.isNotEmpty) ...[
                                            const SmallHeader("Species", padding: EdgeInsets.only(top: 4)),
                                            Wrap(children: List.from(tags["species"]!..sort()).map((e) {
                                                return Tag(e, color: SpecificTagsColors.species,);
                                            }).toList())
                                        ],
                                        const SmallHeader("Generic", padding: EdgeInsets.only(top: 4)),
                                        Wrap(children: List.from(tags["generic"]!..sort()).map((e) {
                                            return Tag(e);
                                        }).toList())
                                    ],
                                );
                            }
                            return const CircularProgressIndicator();
                        }
                    ),

                    const Header("Sources"),
                    image.sources == null || image.sources!.isEmpty ? const Text("None") : Column(
                        children: image.sources!.map((e) {
                            void openContextMenu(Offset offset) {
                                final RenderObject? overlay = Overlay.of(context).context.findRenderObject();
                                showMenu(
                                    context: context,
                                    position: RelativeRect.fromRect(
                                        Rect.fromLTWH(offset.dx, offset.dy, 10, 10),
                                        Rect.fromLTWH(0, 0, overlay!.paintBounds.size.width, overlay.paintBounds.size.height),
                                    ),
                                    items: urlItems(e)
                                );
                            }
                            return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                    onTap: () => launchUrlString(e),
                                    onLongPressEnd: (tap) => openContextMenu(getOffsetRelativeToBox(offset: tap.globalPosition, renderObject: renderObject ?? context.findRenderObject()!)),
                                    onSecondaryTapDown: (tap) => openContextMenu(getOffsetRelativeToBox(offset: tap.globalPosition, renderObject: renderObject ?? context.findRenderObject()!)),
                                    child: Text(e, style: linkText)
                                )
                            );
                        }).toList()
                    ),

                    const Header("Other"),
                    FutureBuilder<Map>(
                        future: (() async => {
                            "dimensions": lookupMimeType(image.filename)!.startsWith("video/") ? null : await decodeImageFromList(await File(image.path).readAsBytes()),
                            "size": await File(image.path).length()
                        })(),
                        builder: (context, snapshot) {
                            if(snapshot.hasData || snapshot.hasError) {
                                final hasDimensionsMetadata = snapshot.data?["dimensions"] == null;

                                final bytes = snapshot.data!["size"]!;
                                const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
                                var i = (m.log(bytes) / m.log(1000)).floor();
                                final formattedSize = '${(bytes / m.pow(1000, i)).toStringAsFixed(2)} ${suffixes[i]}';

                                return SelectableText.rich(
                                    TextSpan(
                                        text: "Path: ${image.path}\n",
                                        children: [
                                            if(!hasDimensionsMetadata) TextSpan(text: "Dimensions: ${snapshot.data?["dimensions"]?.width}x${snapshot.data?["dimensions"]?.height}\n"),
                                            TextSpan(text: "Size: $formattedSize"),
                                        ]
                                    )
                                );
                            }
                            return const CircularProgressIndicator();
                        },
                    )
                ],
            ),
        );
    }
}

class Tag extends StatefulWidget {
    const Tag(this.tag, {super.key, this.color = SpecificTagsColors.generic});

    final String tag;
    final Color color;

    @override
    State<Tag> createState() => _TagState();
}
class _TagState extends State<Tag> {
    bool _isHovering = false;

    @override
    Widget build(BuildContext context) {
        return GestureDetector(
            onTap: () => context.push("/search/?tag=${widget.tag}"),
            child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (details) => setState(() => _isHovering = true),
                onExit: (details) => setState(() => _isHovering = false),
                child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(widget.tag, style: TextStyle(color: widget.color, decoration: _isHovering ? TextDecoration.underline : null, decorationColor: widget.color)),
                ),
            )
        );
    }
}