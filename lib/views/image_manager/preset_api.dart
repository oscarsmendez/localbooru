import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:localbooru/api/index.dart';
import 'package:html/parser.dart' show parse;

final cache = DefaultCacheManager();


class PresetImage {
    const PresetImage({this.image, this.tags, this.sources, this.replaceID});

    final File? image;
    final Map<String, List<String>>? tags;
    final List<String>? sources;
    final String? replaceID;

    static Future<PresetImage> fromExistingImage(BooruImage image) async {
        final Booru booru = await getCurrentBooru();
        
        return PresetImage(
            image: File(image.path),
            sources: image.sources,
            tags: await booru.separateTagsByType(image.tags.split(" ")),
            replaceID: image.id
        );
    }
}

Future<PresetImage> urlToPreset(String url) {
    Uri uri = Uri.parse(url);
    if(uri.host.endsWith("donmai.us")) return danbooruToPreset(url);
    if(uri.host.endsWith("e621.net") || uri.host.endsWith("e926.net")) return e621ToPreset(url);
    if( uri.host.endsWith("gelbooru.com") || //0.2.5
        uri.host.endsWith("safebooru.org") || uri.host.endsWith("rule34.xxx") || uri.host.endsWith("xbooru.com") // 0.2.0
    ) return gelbooruToPreset(url);
    throw "Unknown URL";
}

Future<PresetImage> danbooruToPreset(String url) async {
    Uri uri = Uri.parse(url);
    final res = await http.get(Uri.parse("${[uri.origin, uri.path].join("/")}.json"));
    final bodyRes = jsonDecode(res.body);

    final downloadedFileInfo = await cache.downloadFile(bodyRes["file_url"]);

    return PresetImage(
        image: downloadedFileInfo.file,
        sources: [bodyRes["source"], [uri.origin, uri.path].join("")].whereType<String>().toList(),
        tags: {
            "generic": bodyRes["tag_string_general"].split(" "),
            "artist": bodyRes["tag_string_artist"].split(" "),
            "character": bodyRes["tag_string_character"].split(" "),
            "copyright": bodyRes["tag_string_copyright"].split(" "),
        }
    );
}

Future<PresetImage> e621ToPreset(String url) async {
    Uri uri = Uri.parse(url);
    final res = await http.get(Uri.parse("${[uri.origin, uri.path].join("/")}.json"));
    final postRes = jsonDecode(res.body)["post"];

    final downloadedFileInfo = await cache.downloadFile(postRes["file"]["url"]);

    return PresetImage(
        image: downloadedFileInfo.file,
        sources: [...(postRes["sources"] ?? []), [uri.origin, uri.path].join("")],
        tags: {
            "generic": List<String>.from(postRes["tags"]["general"]),
            "artist": List<String>.from(postRes["tags"]["artist"]),
            "character": List<String>.from(postRes["tags"]["character"]),
            "copyright": List<String>.from(postRes["tags"]["copyright"]),
            "species": List<String>.from(postRes["tags"]["species"]),
        }
    );
}

final Map<int, String> gelbooruTagMap = {
    0: "generic",
    1: "artist",
    // 2: "unused",
    3: "copyright",
    4: "character",
    // 5: "metadata",
};

// wtf is this api
Future<PresetImage> gelbooruToPreset(String url) async {
    Uri uri = Uri.parse(url);
    final String imageID = uri.queryParameters["id"]!;

    final res = await http.get(Uri.parse([uri.origin, "index.php?page=dapi&s=post&q=index&json=1&id=$imageID"].join("/")));
    final json = jsonDecode(res.body);
    final bool is020 = json is List;
    final Map<String, dynamic> post = !is020 ? json["post"][0] : json[0]; // api differences, first one 0.2.5, second 0.2.0

    final String tags = post["tags"];

    Map<String, List<String>> tagList = {
        "generic": [],
        "artist": [],
        "copyright": [],
        "character": [],
    };
    String imageURL;
    if(is020) {
        // probably 0.2.0, grab html documents
        debugPrint("gelbooru 0.2.0");
        
        final webpage = await http.get(Uri.parse([uri.origin, "index.php?page=post&s=view&id=$imageID"].join("/")));
        final document = parse(webpage.body);

        final tagsElements = document.getElementsByClassName("tag");

        debugPrint(tagsElements.length.toString());

        for (var tag in tagsElements) {
            final nameRedirectUri = Uri.parse(tag.children[0].attributes["href"]!);
            final name = nameRedirectUri.queryParameters["tags"] ?? nameRedirectUri.queryParameters["search"];
            String type = tag.classes.first.substring("tag-type-".length);
            if(type == "general") type = "generic";
            if(name != null && tagList[type] != null) tagList[type]!.add(name);
        }

        final imageElement = document.getElementById("image");

        imageURL = imageElement!.attributes["src"]!;

    } else {
        // probably 0.2.5, use their api instead
        debugPrint("gelbooru 0.2.5");

        final tagTypesRes = await http.get(Uri.parse([uri.origin, "index.php?page=dapi&s=tag&q=index&json=1&names=$tags"].join("/")));
        
        final List<dynamic> tagTypes = jsonDecode(tagTypesRes.body)["tag"];

        for (var tag in tagTypes) {
            final type = gelbooruTagMap[tag["type"]];
            if(type != null) tagList[type]!.add(tag["name"]);
        }

        imageURL = post["file_url"];
    }

    final downloadedFileInfo = await cache.downloadFile(imageURL);
    debugPrint("hi");

    return PresetImage(
        image: downloadedFileInfo.file,
        sources: [post["source"], [uri.origin, uri.path].join("")].whereType<String>().toList(),
        tags: {
            "generic": List<String>.from(tagList["generic"]!),
            "artist": List<String>.from(tagList["artist"]!),
            "character": List<String>.from(tagList["character"]!),
            "copyright": List<String>.from(tagList["copyright"]!),
        }
    );
}