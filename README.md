<div align="center">
    <img src="icon_rounded.png" alt="NeoFreeBird-BHTwitter" width="130" height="130">

# NeoFreeBird-BHTwitter (tweak)

<i>The ultimate way to tweak your Twitter/X experience.</i>

</div>
<br>

|                                                   |                                                   |                                                   |
| :-----------------------------------------------: | :-----------------------------------------------: | :-----------------------------------------------: |
| <img width="1604" alt="Screenshot 1" src="1.png"> | <img width="1604" alt="Screenshot 2" src="2.png"> | <img width="1604" alt="Screenshot 3" src="3.png"> |

# Compiling NeoFreeBird-BHTwitter

## Using your computer

1. Install [Theos](https://github.com/theos/theos).

> Sideloaded and TrollStore builds inject and re-sign with [patina](https://github.com/theacrat/patina), which is downloaded automatically if it isn't in `PATH` (or set `PATINA` to a binary or a local checkout). deb (rootless/rootful) builds don't need it.

2. Clone the NeoFreeBird-BHTwitter repository:

```bash
git clone --recursive https://github.com/NeoFreeBird/tweak
cd tweak
```

3. Run the script with your preferred option:

```bash
./build.py [OPTIONS]
```

Available options:

```
--sideloaded: for sideloading.
--trollstore: for TrollStore users.
--rootless: for rootless jailbreaks.
--rootful: for rootful jailbreaks.
(combine them to build several at once, e.g. --sideloaded --trollstore)
--release: build optimised and stripped, as the workflows do; otherwise builds unoptimised with symbols.
--clean: wipe previous build output instead of building incrementally.
--package-only: skip compiling and package the dylibs from a previous build (IPA builds only).
--rebrand [DIR|ZIP]: rebrand the app from a patina config bundle (IPA builds only).
--help: for help
```

## Using GitHub Actions

1. Fork this repository.
2. Open the "Actions" tab and enable workflows.
3. Run either workflow:
   - **Build Tweak** builds one format and uploads it as an artifact. Pick a deployment format, and give a decrypted IPA URL for sideloaded and TrollStore builds.
   - **Release** builds every format, branded and unbranded, and collects them into a draft release. It always needs a decrypted IPA URL.
4. Take the packages from the run's artifacts, or from the "Releases" tab for a release run.

# Examples

## Build for Sideloading

1. Get a decrypted IPA for Twitter/X.
2. Rename it to `base.ipa` and move it to the `packages` folder.

```bash
./build.py --sideloaded
```

Result: `packages/<tweak>-sideloaded-X_<tweak version>_<app version>.ipa`, named after the tweak in `tweak.json`.

## Build for TrollStore

Follow the same steps as sideloading, then run:

```bash
./build.py --trollstore
```

Result: `packages/<tweak>-trollstore-X_<tweak version>_<app version>.tipa`.

## Build for Rootless Jailbreaks

Just run:

```bash
./build.py --rootless
```

Result: `packages/<tweak>-rootless_<tweak version>.deb`.

## Build for Rootful Jailbreaks

Just run:

```bash
./build.py --rootful
```

Result: `packages/<tweak>-rootful_<tweak version>.deb`.

# Branding

Name and icon branding is applied while building an IPA, and shows up in the output filename:

```bash
./build.py --sideloaded --rebrand
```

Result: the same IPA with the bundle's name in place of the app's own, so `...-sideloaded-Twitter_...` rather than `...-sideloaded-X_...`, carrying the name and icons it sets.

The branding lives in a [patina](https://github.com/theacrat/patina) config bundle — a folder (or a zip of it, so it can be hosted) laid out as patina expects:

```
config.json    settings, e.g. the app name
icon.png       the app icon
alt-icons/     alternate icons, named after the file
car/*.png      images swapped inside the app's asset catalogue
overlay/**     files merged into the app, laid out as they are in the app
```

`--rebrand` uses `patina/` by default; pass a path to use another bundle.

# Configuring the tweak

`tweak.json` is the only build file to edit. The deb control and the Substrate filter plist are generated from it, so neither is in the repo, and the Makefile takes every setting from it through the environment.

Top-level keys become deb control fields. `filter.bundles` is the app the tweak loads into, and `build` holds the compile settings:

```
archs, sdk_version, target_version    what to build for
subprojects, sideload_subprojects     Theos projects under deps/, the latter
                                      built for sideloading but never packaged
frameworks, private_frameworks, extra_frameworks
obj_files, cflags
```

Resources go in `bundle/`, installed as `<name>/<name>.bundle` under Application Support and reachable from the app as `TWEAK_NAME_STRING`.

A dependency is a name plus where to get it, so sideloaded and TrollStore builds can carry what a jailbreak would install:

```json
{
  "name": "ws.hbang.common",
  "url": "https://github.com/hbang/libcephei/releases/download/2.0/ws.hbang.common_2.0_iphoneos-arm64.deb"
}
```

Use `path` instead of `url` for a local `.deb` (relative to the repo). Setting both takes the local one, which is how a package you built yourself is tested in place of the published one. A plain string declares a dependency without bundling it.

# Translating

Every language lives in `bundle/strings.json`, one entry per string key with a value per language:

```json
{
  "Localizable": {
    "MODERN_SETTINGS_LAYOUT_TITLE": {
      "en": "General",
      "de": "Allgemein",
      "fr": "Général"
    }
  }
}
```

`build.py` writes each table into `<name>.bundle/Localizations.bundle/<language>.lproj/<table>.strings` as it stages the bundle, so there are no `.lproj` folders to edit. `Localizable` is Cocoa's default table and holds the interface strings, setting the languages the tweak ships: a key missing one falls back to English, and the build says which. Every other table is optional and strictly per-language, never falling back — `RenameWords` and `RenameOverrides` are two, driving the "Restore Twitter names" feature.

`strings.schema.json` completes language codes and flags typos and empty values as you type. It lists the ISO 639-1 designators plus the script and region variants iOS resolves; iOS takes any BCP 47 designator, so add one there if you need it. Neither file is shipped.
