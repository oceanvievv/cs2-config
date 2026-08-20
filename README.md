# CS2 config

Packed by [cs2-config](https://github.com/oceanvievv/cs2-config).

## Installing the config on another PC

Any one of these three. Take the first that works on that PC — they are alternatives, not
steps.

#### Installation file
Download [apply-config.cmd](https://github.com/oceanvievv/cs2-config-oceanvievv/blob/main/apply-config.cmd) and launch it.

#### Copy configs manually
Copy the files from `cfg\` into:

```
...\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\
```

Then restart CS2. `autoexec.cfg` runs on startup and pulls in the rest. If the game is
already open, `exec autoexec` in the console does the same thing once.

#### Use CS2 console
Open `apply-config-using-console.txt` and copy everything, then paste into the CS2 console.

For a PC where you cannot write files at all. Configs and crosshair only.

## Launch options

Steam > CS2 > Properties > General.

Portable version, safe on unknown hardware:

```
+fps_max 0 -forcenovsync -nojoy -novid +engine_low_latency_sleep_after_client_tick true -language english -w 1440 -h 1080 -fullscreen +exec autoexec
```

Your full version, for home:

```
+fps_max 0 -high -forcenovsync -softparticlesdefaultoff +mat_disable_fancy_blending 1 -nojoy -threads 8 -novid +engine_low_latency_sleep_after_client_tick true -language english
```

## What is in here

```
apply-config.cmd                 Applies the settings; your configs are embedded in it
apply-config-using-console.txt   One line to paste into the CS2 console
update-config.cmd                Re-reads your settings and rebuilds this folder
.gitattributes                   Keeps the line endings that a downloaded .cmd needs
cfg\autoexec.cfg                 Runs automatically on startup
cfg\crosshair.cfg                Your crosshair
cfg\knife.cfg
cfg\oceanvievv.cfg               Your main config
cfg\training.cfg
video\cs2_video.txt              Resolution and quality
machine\cs2_machine_convars.vcfg  Radar, fov, volumes: what Steam Cloud does not carry
cloud-backup\cs2_user_convars_0_slot0.vcfg  What Steam Cloud normally brings
cloud-backup\cs2_user_keys_0_slot0.vcfg  What Steam Cloud normally brings
```

The crosshair is applied as convars, so there is nothing to paste. The share code, if you
want it anyway:

```
CSGO-v2QEv-LYcjt-cyv7q-Yhiow-YpybE
```

`cloud-backup\` is a copy of what Steam Cloud normally delivers. You usually never need
it: logging into Steam brings your sensitivity, crosshair and binds down by itself.