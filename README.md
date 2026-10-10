# cs2-config

Create, update, rename and apply named CS2 settings profiles from one portable Windows executable.
The interface uses Spectre.Console and is in English. Profile names can use any language.

[Русская версия](README.ru.md)

## Download and run

[Download cs2-config.exe](https://github.com/oceanvievv/cs2-config/releases/latest/download/cs2-config.exe), put it in a writable folder and open it.
Windows 10/11 with its built-in Windows PowerShell 5.1 and .NET Framework 4.8 is required.
No SDK, PowerShell 7, extra runtime installation or network download is needed at launch.

Use **Up/Down** and **Enter** to choose an action. Type a name or number to filter options.
**Back** returns one screen; **Back to main menu** returns to the main menu.
Profile choice is always explicit. There is no default profile.

## Apply a profile

1. Close CS2 and sign in to the Steam account you will use.
2. Choose **Apply profile**, then choose your profile.
3. Review the display summary. **View all settings** opens the full profile.
4. Choose **Apply** and review any adjustments or skipped settings.
5. Paste the copied launch options into **Steam > CS2 > Properties > General > Launch Options**.

Application prepares missing account folders and video adapter identity without a preliminary game launch.
If the requested fullscreen refresh rate exceeds the maximum at the requested resolution, that maximum
is used and reported. The stored profile stays unchanged. Unsupported resolutions are skipped.
Independent settings continue when another group cannot be written. Success means files were saved
and checked; check the actual result after launching CS2.

## Create, update and rename

Set your preferences in CS2, exit it, then choose **Create profile** or **Update profile**.
Review captured settings and save. Steam launch options are captured unchanged.
Custom Steam, CS2 and destination paths can be entered when needed.

**Rename config** changes its display name. **Rename profile** changes the selected profile name.
Names may contain spaces and non-Latin characters. Names must be unique within a config.
Renaming preserves settings; console file links are updated. The folder and repository retain their names.
No backup or restore workflow is created.

## Portable config

- **cs2-config.exe**: the single entry point, with the utility and profiles embedded.
- **profiles.json**: editable profiles; this file takes precedence when beside the executable.
- **console/**: profile command files for the CS2 console alternative.
- **README.md**: instructions and profile links.

A damaged profiles.json never triggers a silent fallback to the embedded copy.
Saving a profile or renaming rebuilds the executable with current data.
Use the executable from this repository's latest release to upgrade an existing folder,
then create, update or rename a profile to embed the latest data in it.
To migrate an old flat config, put the executable beside its cfg/video/machine/cloud-backup folders.

## Console alternative and publishing

Follow a profile's command-file link in your config README, paste the commands into the CS2 console,
and check the result. Supported settings: crosshair, mouse, audio and controls.

Upload the updated config folder to your GitHub repository. Download a fresh executable on another PC;
old downloads retain their embedded settings. The utility never uploads automatically.

## Development

The portable EXE is a small C# launcher with a compressed PowerShell settings engine and bundled
Spectre.Console 0.57.2 assemblies. It uses the existing Windows runtime. The temporary engine file
is removed on exit. The launcher releases its own file after handoff so profile saves can rebuild it.
There are no user-facing CMD or PS1 launchers. See [third-party licenses](THIRD-PARTY-NOTICES.txt).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/crosshair.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/profiles.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/spectre.ps1
```

Tests use isolated fixtures and do not modify installed Steam or CS2 settings.
