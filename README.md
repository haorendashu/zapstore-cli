# zapstore-cli

To install dependencies:

```bash
dart pub get
```

To run:

```bash
dart lib/main.dart
```

To build:

```bash
dart compile exe lib/main.dart -o zapstore
```

## Managing packages

```bash
zapstore install <package>
zapstore remove <package>
zapstore list
```

Run `zapstore --help` for more information.

## Publishing a package

Run `zapstore publish myapp` in a folder with a `zapstore.yaml` file.

Artifacts should be listed in `artifacts`, either as a list or as keys of a map for further options. It supports regular expressions to describe package paths.
For convenience, use `%v` as placeholder for a version. It will be replaced by `\d+\.\d+(\.\d+)?`. You can write any regex that matches your files.

If you previously published your package, app (kind 32267) will not be published again by default - just the release (kind 30063, 1063). To change this, use `--overwrite-app` and `--overwrite-release`.

For more run `zapstore help publish`.

### Android package

Example:

```yaml
go:
  android:
    identifier: com.getalby.mobile
    name: Alby Go
    description: A simple lightning mobile wallet interface that works great with Alby Hub.
    repository: https://github.com/getAlby/go
    license: MIT
    artifacts:
      - alby-go-v%v-android.apk
```

In the terminal, run `publish` and optionally specify the name of the app:

```bash
zapstore publish go
```

This will pull APKs from Github releases. If you would like to upload an APK (that will be stored at `cdn.zap.store` Blossom server) instead, use `-a` and `-r` like:

```bash
zapstore publish go -a ~/path/to/alby-go-v1.4.1-android.apk -r 1.4.1
```

If you have multiple artifacts, run this command once with multiple `-a` arguments.

If you want to add release notes, provide the release notes Markdown file to `-n`.

You will be prompted for your nsec, but you can also pass it via the `NSEC` environment variable. This is the only available option for signing at the moment. NIP-46 and NIP-07 signing are planned.

Note that `apktool` is required to extract APK information. If you don't have it in your path, you can install it via `zapstore install apktool`.

### CLI package

```yaml
myapp:
  cli:
    identifier: my app
    name: My App
    summary: the app world army knife
    repository: https://github.com/myself/myapp
    builder: npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6
    artifacts:
      nak-v%v-darwin-arm64:
        platform: darwin-arm64
      nak-v%v-linux-amd64:
        platform: linux-x86_64
```

Inside the map, use the `platform` key to specify the target platform. Formats are included as `f` tags in file metadata events and valid strings at this time are:

 - `darwin-arm64`
 - `darwin-x86_64`
 - `linux-x86_64`
 - `linux-aarch64`

More will be added soon and will be specified in a NIP. These are based off `uname -sm`, lowercased and dashed.

If your file is compressed (zip and tar.gz supported), uncompressing assumes it will find an executable with the exact identifier of your package.

Use the `executables` array only if the executable has a different name or path inside the compressed file, and/or it has multiple executables. Example:

```yaml
phoenixd:
  cli:
    identifier: phoenixd
    name: phoenixd
    repository: https://github.com/acinq/phoenixd
    artifacts:
      phoenix-%v-macos-arm64.zip:
        platform: darwin-arm64
        executables: [phoenix-%v-macos-arm64/phoenixd, phoenix-%v-macos-arm64/phoenix-cli]
```

Publishing is hard-coded to `relay.zap.store` for now. Your pubkey must be whitelisted by zap.store in order for your events to be accepted. Get in touch!