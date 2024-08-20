import 'dart:convert';
import 'dart:io';

import 'package:cli_spin/cli_spin.dart';
import 'package:collection/collection.dart';
import 'package:interact_cli/interact_cli.dart';
import 'package:purplebase/purplebase.dart';
import 'package:zapstore_cli/models.dart';
import 'package:http/http.dart' as http;
import 'package:zapstore_cli/utils.dart';
import 'package:path/path.dart' as path;

class LocalParser {
  final App app;
  final List<String> artifacts;
  final String version;
  final RelayMessageNotifier relay;
  LocalParser(
      {required this.app,
      required this.artifacts,
      required this.version,
      required this.relay});

  Future<(Release, Set<FileMetadata>)> process({
    required String os,
    required Map<String, dynamic> yamlArtifacts,
  }) async {
    final releaseCreatedAt = DateTime.now();

    final fileMetadatas = <FileMetadata>{};
    for (var MapEntry(key: regexpKey, :value) in yamlArtifacts.entries) {
      regexpKey = regexpKey.replaceAll('%v', r'(\d+\.\d+(\.\d+)?)');
      final r = RegExp(regexpKey);
      final artifact =
          artifacts.firstWhereOrNull((a) => r.hasMatch(path.basename(a)));

      if (artifact == null) {
        final continueWithout =
            Confirm(prompt: 'No artifact matching $regexpKey. Continue?')
                .interact();
        if (continueWithout) {
          continue;
        } else {
          throw GracefullyAbortSignal();
        }
      }

      final artifactFile = File(artifact);
      if (!await artifactFile.exists()) {
        throw 'No artifact file found at $artifact';
      }

      final uploadSpinner = CliSpin(
        text: 'Uploading artifact: $artifact...',
        spinner: CliSpinners.dots,
      ).start();

      final tempArtifactPath =
          path.join(Directory.systemTemp.path, path.basename(artifact));
      await artifactFile.copy(tempArtifactPath);
      final (artifactHash, newFilePath, mimeType) =
          await renameToHash(tempArtifactPath);

      var artifactUrl = 'https://cdn.zap.store/$artifactHash';

      // Check if we already processed this release
      final metadataOnRelay = await relay.query<FileMetadata>(tags: {
        '#x': [artifactHash]
      });

      if (metadataOnRelay.isNotEmpty) {
        if (Platform.environment['OVERWRITE'] == null) {
          uploadSpinner
              .fail('Release version $version already in relay, nothing to do');
          throw GracefullyAbortSignal();
        }
      }

      final headResponse = await http.head(Uri.parse(artifactUrl));
      if (headResponse.statusCode != 200) {
        final bytes = await artifactFile.readAsBytes();
        final response = await http.post(
          Uri.parse('https://cdn.zap.store/upload'),
          body: bytes,
          headers: {
            'Content-Type': mimeType,
            'X-Filename': path.basename(newFilePath),
          },
        );

        final responseMap =
            Map<String, dynamic>.from(jsonDecode(response.body));
        artifactUrl = responseMap['url'];

        if (response.statusCode != 200 ||
            artifactHash != responseMap['sha256']) {
          uploadSpinner.fail(
              'Error uploading $artifact: status code ${response.statusCode}, hash: $artifactHash, server hash: ${responseMap['sha256']}');
          continue;
        }
      }

      final match = r.firstMatch(artifact);
      final matchedVersion = (match?.groupCount ?? 0) > 0
          ? r.firstMatch(artifact)?.group(1)
          : version;

      // Validate platforms
      final platforms = {...?value['platforms'] as Iterable?};
      if (!platforms
          .every((platform) => kSupportedPlatforms.contains(platform))) {
        throw 'Artifact $artifact has platforms $platforms but some are not in $kSupportedPlatforms';
      }

      final size = await runInShell('wc -c < $newFilePath');

      fileMetadatas.add(
        FileMetadata(
            content: '${app.name} $version',
            createdAt: releaseCreatedAt,
            urls: {artifactUrl},
            mimeType: mimeType,
            hash: artifactHash,
            size: int.tryParse(size),
            platforms: platforms.toSet().cast(),
            version: version,
            pubkeys: app.pubkeys,
            zapTags: app.zapTags,
            additionalEventTags: {
              for (final b in (value['executables'] ?? []))
                (
                  'executable',
                  matchedVersion != null
                      ? b.toString().replaceFirst('%v', matchedVersion)
                      : b
                ),
            }),
      );
      uploadSpinner.success('Uploaded artifact: $artifact to $artifactUrl');
    }

    final release = Release(
      createdAt: releaseCreatedAt,
      content: '${app.name} $version',
      identifier: '${app.identifier}@$version',
      pubkeys: app.pubkeys,
      zapTags: app.zapTags,
    );

    return (release, fileMetadatas);
  }
}
