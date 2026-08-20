# Конфиг CS2

Собран утилитой [cs2-config](https://github.com/oceanvievv/cs2-config).

## Установка конфига на другом компьютере

Любой из трёх способов. Бери первый, который сработает на этом ПК: это варианты, а не
шаги.

#### Файл установки
Скачай [apply-config.cmd](https://github.com/oceanvievv/cs2-config-oceanvievv/blob/main/apply-config.cmd) и запусти его.

#### Скопировать конфиги вручную
Скопируй файлы из `cfg\` в папку:

```
...\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\
```

Потом перезапусти CS2: `autoexec.cfg` выполняется при старте и подтягивает остальное.
Если игра уже открыта, то же самое сделает `exec autoexec` в консоли.

#### Через консоль CS2
Открой `apply-config-using-console.txt`, скопируй всё и вставь в консоль CS2.

Для ПК, где записывать файлы нельзя вообще. Только конфиги и прицел.

## Параметры запуска

Steam > CS2 > «Свойства» > «Общие».

Переносимый вариант, безопасный на незнакомом железе:

```
+fps_max 0 -forcenovsync -nojoy -novid +engine_low_latency_sleep_after_client_tick true -language english -w 1440 -h 1080 -fullscreen +exec autoexec
```

Твой полный вариант, домашний:

```
+fps_max 0 -high -forcenovsync -softparticlesdefaultoff +mat_disable_fancy_blending 1 -nojoy -threads 8 -novid +engine_low_latency_sleep_after_client_tick true -language english
```

## Что лежит внутри

```
apply-config.cmd                 Применяет настройки; конфиги лежат внутри него же
apply-config-using-console.txt   Одна строка для вставки в консоль CS2
update-config.cmd                Перечитывает настройки и пересобирает эту папку
.gitattributes                   Хранит переводы строк, нужные скачанному .cmd
cfg\autoexec.cfg                 Запускается сам при старте игры
cfg\crosshair.cfg                Твой прицел
cfg\knife.cfg
cfg\oceanvievv.cfg               Твой главный конфиг
cfg\training.cfg
video\cs2_video.txt              Разрешение и качество картинки
machine\cs2_machine_convars.vcfg  Радар, fov, громкости: то, что не возит Steam Cloud
cloud-backup\cs2_user_convars_0_slot0.vcfg  То, что обычно приносит Steam Cloud
cloud-backup\cs2_user_keys_0_slot0.vcfg  То, что обычно приносит Steam Cloud
```

Прицел применяется через консольные переменные, вставлять ничего не нужно. Код обмена,
если он всё же нужен:

```
CSGO-v2QEv-LYcjt-cyv7q-Yhiow-YpybE
```

`cloud-backup\` — копия того, что обычно приносит Steam Cloud. Обычно она не нужна:
вход в Steam сам подтянет чувствительность, прицел и бинды.