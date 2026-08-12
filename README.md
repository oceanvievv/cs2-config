# cs2-config

A tool for creating, saving and installing your CS2 config.

[Русская версия](README.ru.md)

#### Which settings are covered

- Game configs (autoexec, your own ones)
- Crosshair
- Launch options
- Video settings
- A copy of the cloud settings (sensitivity, crosshair, binds and so on)
- The settings tied to the PC (radar, fov, volumes and so on)

## Building the config on your PC

[Download the installer](https://github.com/oceanvievv/cs2-config/releases/latest/download/setup.cmd)
and run it. It creates the config folder **next to wherever you ran it from**:

```
cs2-config\
   apply-config.cmd // Applies your settings
   apply-config-using-console.txt // Fallback through the CS2 console, when the script cannot run
   
   update-config.cmd // Updates your settings
   .gitattributes // Housekeeping: without it a downloaded apply-config.cmd will not run
   
   cfg\ // Game configs
   video\ // Screen resolution, refresh rate, picture quality and so on
   machine\ // What Steam Cloud does not carry: radar, fov, volumes, HUD scale and so on
   cloud-backup\ // A copy of what Steam Cloud normally holds: mouse sensitivity, crosshair, binds and so on
   
   README.md // Instructions
   README.ru.md // Instructions in Russian
```

Carry the folder on a USB stick, or [put it on GitHub](#the-config-in-the-cloud) to install the config on another
PC with one command.

## Updating the config

To update the config after changing your settings in the game, run `update-config.cmd`.

If the config is already on GitHub, upload the folder again the same way —
see [Updating the config in the cloud](#updating-the-config-in-the-cloud).

## Installing the config on another PC

Two ways, depending on how you keep the config:

1. [The config in the cloud](#the-config-in-the-cloud). Open your repository and use the link from its README to download the file that applies the config

2. The config folder on a USB stick: carry it to the other PC and run `apply-config.cmd`

   > If the script will not run, paste the contents of `apply-config-using-console.txt` into the CS2 console. Only your basic configs and the crosshair are applied.

## The config in the cloud

### Putting the config in the cloud
1. Sign in at [github.com](https://github.com)
2. Create a public repository (`cs2-config`, for example)
3. On the page that opens, click **uploading an existing file**
4. Drag the contents of the cs2-config folder onto the page
5. Click **Commit changes**

### Updating the config in the cloud
1. Open the repository holding your config
2. Click `Add file` and pick `Upload files`
3. Drag the contents of the cs2-config folder onto the page
4. Click **Commit changes**
