// ignore_for_file: unnecessary_string_escapes

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact_cli/interact_cli.dart';
import 'package:tint/tint.dart';
import 'package:zapstore_cli/commands/install.dart';
import 'package:zapstore_cli/commands/list.dart';
import 'package:zapstore_cli/commands/publish.dart';
import 'package:zapstore_cli/commands/remove.dart';
import 'package:zapstore_cli/utils.dart';

const kZapstorePubkey =
    '78ce6faa72264387284e647ba6938995735ec8c7d5c5a65737e55130f026307d';
const kVersion = '0.0.2';

void main(List<String> args) async {
  var wasError = false;
  try {
    final runner = CommandRunner("zapstore",
        "$figure\nThe permissionless app store powered by your social network")
      ..addCommand(InstallCommand())
      ..addCommand(ListCommand())
      ..addCommand(RemoveCommand())
      ..addCommand(PublishCommand());
    runner.argParser.addFlag('version', abbr: 'v', negatable: false);
    final argResults = runner.argParser.parse(args);

    final version = argResults['version'];
    if (version) {
      print('zap.store CLI $kVersion');
      return;
    }
    await runner.run(args);
  } on GracefullyAbortSignal {
    // silently exit with no error
  } catch (e, stack) {
    print('${'ERROR'.red()} $e');
    print(stack);
    wasError = true;
    reset();
  } finally {
    exit(wasError ? 127 : 0);
  }
}

class InstallCommand extends Command {
  InstallCommand() {
    argParser.addFlag('trust',
        abbr: 't', help: 'Trust the signer, do not prompt for a WoT check.');
  }

  @override
  String get name => 'install';

  @override
  String get description => 'Install a package';

  @override
  List<String> get aliases => ['i'];

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Please provide a package to install');
    }
    final [value] = argResults!.rest;
    await install(value, skipWot: argResults!.flag('trust'));
  }
}

class ListCommand extends Command {
  @override
  String get name => 'list';

  @override
  String get description => 'List installed packages';

  @override
  List<String> get aliases => ['l'];

  @override
  Future<void> run() async => list();
}

class RemoveCommand extends Command {
  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a package';

  @override
  List<String> get aliases => ['r'];

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Please provide a package to remove');
    }
    final [value] = argResults!.rest;
    await remove(value);
  }
}

class PublishCommand extends Command {
  @override
  String get name => 'publish';

  @override
  String get description => 'Publish a package';

  @override
  List<String> get aliases => ['p'];

  @override
  Future<void> run() async {
    final value = argResults!.rest.firstOrNull;
    await publish(value);
  }
}

const figure = r'''
                     _                 
                    | |                
 ______ _ _ __   ___| |_ ___  _ __ ___ 
|_  / _` | '_ \ / __| __/ _ \| '__/ _ \
 / / (_| | |_) |\__ \ || (_) | | |  __/
/___\__,_| .__(_)___/\__\___/|_|  \___|
         | |                           
         |_|                                               
''';
