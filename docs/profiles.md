# Implementation notes

Schema version 1: a pack has `name` and `profiles`, without a default or last-selected
profile. Each profile contains an ID, arbitrary unique name, timestamp, game CFG
contents, user convars, machine convars, bindings, video values and exact Steam launch
options. Setting values are strings. Imported data is never evaluated as PowerShell.

The active Steam account is usable before its `730/local/cfg` directory exists.
Otherwise the user selects a saved account explicitly. Folder age is never used to
choose an account. Capture requires saved settings; application creates directories.

Video preparation separates adapter metadata from profile settings. Windows display
enumeration supplies the adapter identity and available modes. No GPU vendor ranking
is used. Hybrid-GPU laptops require an in-game check: the desktop adapter may differ
from the GPU selected for the game in Windows graphics preferences.

Fullscreen rates above the maximum are reduced at the same resolution and reported.
Other unsupported display combinations are skipped. The profile remains unchanged.
On a PC without an existing video file, an unavailable display prevents video
initialization, while independent player settings can still be written.

Files are written through temporary files in their destination directories, replaced
without retaining backups, and read back. Pack export prepares outputs before writing.
`profiles.json` remains authoritative if rebuilding a derived launcher fails; retry
export to repair it. A stale standalone executable cannot discover newer profiles.

The startup overlay runs after custom autoexec commands so newly captured settings
take precedence over stale CFG values. Crosshair size commands precede
`cl_crosshair_screen_height`. Hidden legacy crosshair values are not captured.

## Sources and verification

Video enumerations were checked on 2026-10-10 against Valve's extracted
[settings_video.xml](https://github.com/SteamTracking/GameTracking-CS2/blob/master/game/csgo/pak01_dir/panorama/layout/settings/settings_video.xml).
Anisotropic 2x = 2; medium texture/shadows = 1; HDR Quality = -1;
FSR Disabled (Highest Quality) = 0. Ultra Quality = 1 is different.
MSAA 4x uses 4 samples with CMAA disabled.

Windows display modes come from EnumDisplayDevices and EnumDisplaySettings. The latter
reports integer refresh rates; fractional rates within 1.1 Hz remain unchanged.
Reduced rates use a denominator of 1000.

Windows PowerShell 5.1 tests cover parsing, profile isolation, command extraction,
standalone regeneration, explicit selection, custom paths, new-account directories,
adapter identity, partial writes and refresh reduction. They do not launch CS2.
The full first-launch behaviour still needs checking on a club PC, including graphics
driver behaviour and Steam synchronization. Disk verification is not in-game proof.
