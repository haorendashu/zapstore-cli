import 'dart:convert';

import 'package:cli_spin/cli_spin.dart';
import 'package:collection/collection.dart';
import 'package:purplebase/purplebase.dart';
import 'package:zapstore_cli/commands/publish/local_parser.dart';
import 'package:zapstore_cli/main.dart';
import 'package:zapstore_cli/models/nostr.dart';
import 'package:http/http.dart' as http;
import 'package:zapstore_cli/utils.dart';

class GithubParser extends RepositoryParser {
  final RelayMessageNotifier relay;

  GithubParser({required this.relay});

  @override
  Future<(App, Release?, Set<FileMetadata>)> process({
    required App app,
    required bool overwriteRelease,
    String? releaseRepository,
    Map<String, dynamic>? artifacts,
  }) async {
    final repoName =
        Uri.parse(app.repository ?? releaseRepository!).path.substring(1);

    final headers = env['GITHUB_TOKEN'] != null
        ? {'Authorization': 'Bearer ${env['GITHUB_TOKEN']}'}
        : <String, String>{};

    final metadataSpinner = CliSpin(
      text: 'Fetching metadata...',
      spinner: CliSpinners.dots,
      isSilent: isDaemonMode,
    ).start();

    final latestReleaseUrl =
        'https://api.github.com/repos/$repoName/releases/latest';
    Map<String, dynamic>? latestReleaseJson =
        await http.get(Uri.parse(latestReleaseUrl), headers: headers).getJson();
    var assets = latestReleaseJson['assets'] as Iterable;
    final hasAsset = assets.any((a) => artifacts!.entries
        .any((e) => regexpFromKey(e.key).hasMatch(a['name'])));

    // If there's a message it's an error (or no matching assets were found)
    if (latestReleaseJson['message'] != null || !hasAsset) {
      final response = await http.get(
          Uri.parse('https://api.github.com/repos/$repoName/releases'),
          headers: headers);
      final releases = jsonDecode(response.body);

      if (releases is Map && releases['message'] != null || releases.isEmpty) {
        throw 'Error ${releases['message']} for $repoName, I\'m done here';
      }
      releases as Iterable;
      if (releases.isEmpty) {
        throw 'No releases available';
      }

      latestReleaseJson = _findRelease(releases, artifacts!);
      assets = latestReleaseJson?['assets'];
    }

    if (latestReleaseJson == null || assets.isEmpty) {
      final message = 'No packages in $repoName, I\'m done here';
      if (isDaemonMode) {
        print(message);
      }
      metadataSpinner.fail(message);
      throw GracefullyAbortSignal();
    }

    metadataSpinner.success('Fetched metadata from Github');

    final version = latestReleaseJson['tag_name']!.toString();

    final repoUrl = 'https://api.github.com/repos/$repoName';
    final repoJson =
        await http.get(Uri.parse(repoUrl), headers: headers).getJson();

    app = app.copyWith(
      content: app.content.isNotEmpty
          ? app.content
          : repoJson['description'] ?? repoJson['name'],
      identifier: app.identifier,
      name: app.name ?? repoJson['name'],
      url: app.url ??
          ((repoJson['homepage']?.isNotEmpty ?? false)
              ? repoJson['homepage']
              : null),
      license: app.license ?? repoJson['license']?['spdx_id'],
      tags: app.tags.isEmpty
          ? (repoJson['topics'] as Iterable).toSet().cast()
          : app.tags,
      pubkeys: app.pubkeys,
      zapTags: app.zapTags,
    );

    final fileMetadatas = <FileMetadata>{};
    for (var MapEntry(:key, :value) in artifacts!.entries) {
      final r = regexpFromKey(key);

      final asset = assets.firstWhereOrNull((a) =>
          r.hasMatch(a['name']) ||
          (a['label'] != null && r.hasMatch(a['label'])));

      final packageSpinner = CliSpin(
        text: 'Fetching package...',
        spinner: CliSpinners.dots,
        isSilent: isDaemonMode,
      ).start();

      if (asset == null) {
        final message = 'No asset matching ${r.pattern}';
        if (isDaemonMode) {
          print(message);
        }
        packageSpinner.fail(message);
        return (app, null, <FileMetadata>{});
      }

      final packageUrl = asset['browser_download_url'];
      packageSpinner.text = 'Fetching package $packageUrl...';

      // Check if we already processed this release
      final metadataOnRelay =
          await relay.query<FileMetadata>(search: packageUrl);

      // Search is full-text (not exact) so we double-check
      final metadataOnRelayCheck = metadataOnRelay
          .firstWhereOrNull((m) => m.urls.firstOrNull == packageUrl);
      if (metadataOnRelayCheck != null) {
        if (!overwriteRelease) {
          if (isDaemonMode) {
            print('$repoName OK, skip');
          }
          packageSpinner.success(
              'Latest $repoName release already in relay, nothing to do');
          throw GracefullyAbortSignal();
        }
      }

      final tempPackagePath = await fetchFile(packageUrl,
          headers: headers, spinner: packageSpinner);

      // Validate platforms
      final platforms = {...?value['platforms'] as Iterable?};
      if (!platforms
          .every((platform) => kSupportedPlatforms.contains(platform))) {
        throw 'Artifact ${asset['name']} has platforms $platforms but some are not in $kSupportedPlatforms';
      }

      final match = r.firstMatch(asset['name']);

      final (fileHash, filePath, _) = await renameToHash(tempPackagePath);
      final size = await runInShell('wc -c < $filePath');
      final fileMetadata = FileMetadata(
        content: '${app.name} $version',
        createdAt: DateTime.tryParse(latestReleaseJson['created_at']),
        urls: {packageUrl},
        mimeType: asset['content_type'],
        hash: fileHash,
        size: int.tryParse(size),
        platforms: platforms.toSet().cast(),
        version: version,
        pubkeys: app.pubkeys,
        zapTags: app.zapTags,
        additionalEventTags: {
          for (final e in (value['executables'] ?? []))
            ('executable', replaceInExecutable(e, match)),
        },
      );
      fileMetadata.transientData['apkPath'] = filePath;
      fileMetadatas.add(fileMetadata);
      packageSpinner.success('Fetched package: $packageUrl');
    }

    final release = Release(
      createdAt: DateTime.tryParse(latestReleaseJson['created_at']),
      content: latestReleaseJson['body'],
      identifier: '${app.identifier}@$version',
      url: latestReleaseJson['html_url'],
      pubkeys: app.pubkeys,
      zapTags: app.zapTags,
    );

    return (app, release, fileMetadatas);
  }
}

abstract class RepositoryParser {
  Future<(App, Release?, Set<FileMetadata>)> process({
    required App app,
    required bool overwriteRelease,
  });
}

Map<String, dynamic>? _findRelease(
    Iterable releases, Map<String, dynamic> artifacts) {
  for (final r in releases) {
    for (final asset in r['assets']) {
      for (final e in artifacts.entries) {
// print(
//                 'checking ${regexpFromKey(e.key)} match ${a['name']} - ${regexpFromKey(e.key).hasMatch(a['name'])}');
        if (regexpFromKey(e.key).hasMatch(asset['name'])) {
          return r;
        }
      }
    }
  }
  return null;
}
