# cs2-config

Create, update and apply named CS2 settings profiles from a Windows CMD launcher.
The interface is in English. Profile names can use any language.

[Русская версия](README.ru.md)

## Create your config

[Download setup.cmd](https://github.com/oceanvievv/cs2-config/releases/latest/download/setup.cmd), put it in a writable folder, and run it. Sign in to Steam first.
To capture settings, choose them in CS2 and exit the game. Enter a profile name,
review the settings and destination, then choose **Create profile**. You can enter
custom Steam, CS2 installation and output paths when needed.

```text
cs2-config/
  profiles.json       Complete saved profiles; no default profile
  apply-config.cmd    Main menu; all profiles are also embedded
  update-config.cmd   Update an explicitly selected profile
  setup.cmd           Create another profile
  console/            A console command file for each profile
  README.md           Instructions and links to console files
```

There are no predefined profile names. Even a single profile requires explicit
selection. **Back** returns one screen; **Back to main menu** returns to the main menu.
No backup or restore workflow is created.

## Apply a profile

1. Close CS2 and sign in to Steam with the account you will use.
2. Run `apply-config.cmd` and choose **Apply profile**.
3. Choose the profile, review the settings, then choose **Apply**.
4. Review the result. Paste the displayed launch options into
   **Steam > CS2 > Properties > General > Launch Options**, then start CS2.

The CMD contains all profiles and can run on its own. If `profiles.json` is beside it,
that file is authoritative. A damaged JSON file never triggers a silent fallback to
an older embedded copy.

Application creates missing account settings folders and prepares video settings
using the target display adapter's identity, without requiring a preliminary CS2
launch. If the fullscreen refresh rate exceeds the maximum available **at the
requested resolution**, that maximum is used and reported. The stored profile is
unchanged. Unsupported resolutions are skipped.

Independent settings continue when another group cannot be written. Success means
files were saved and checked; it does not claim that the game has already accepted
them. Review skipped settings and check the result in CS2.

## Update or add a profile

Change your settings in CS2, exit it, and run `update-config.cmd`. Select the profile,
review changes, then choose **Save changes**. Steam launch options are captured
without filtering or appending arguments. Other profiles are unchanged.

Use **Create profile** in the main menu or run the generated `setup.cmd` to add another
profile. Updating replaces the selected profile; previous versions are not retained.

To migrate a flat config folder, put the new `setup.cmd` beside its old `cfg`, `video`,
`machine` and `cloud-backup` folders. Name the existing profile when prompted. Legacy
crosshair sizes must first be converted or saved by the current CS2 version.

To upgrade the utility inside an existing profile pack, download the latest `setup.cmd`
into that pack's folder and create or update a profile with it. This rebuilds its
launchers. Profile updates use the embedded utility and do not download code automatically.

## Console alternative

Open your config's README and follow the link for the desired profile. Paste commands
into the CS2 console in small batches, then check your settings in CS2.

Supported settings: crosshair, mouse, audio and controls.

## Share or update a published config

Upload the generated folder contents to your GitHub repository using
**Add file > Upload files**, then **Commit changes**. Repeat after updating profiles.
Download a fresh `apply-config.cmd` on another PC; old downloads keep their embedded
settings. This utility never uploads anything automatically.

## Development

The shared PowerShell 5.1 implementation is in `src`. `setup.cmd` is generated:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/crosshair.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/profiles.ps1
```

Tests use temporary directories and do not modify installed Steam or CS2 settings.
See [implementation notes](docs/profiles.md) for format and verification limits.
