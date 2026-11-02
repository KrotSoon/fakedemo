# CS2 / HLAE editing config v3

Собран для HLAE 2.192.8 (FFmpeg 8+, ставится вместе с HLAE). Fake demo / fake server сюда не входят.

## Установка
1. Скопировать все `*.cfg` в папку moviemaking-конфигов HLAE (лаунчер HLAE -> CS2 -> Custom config folder)
   либо в `...\Counter-Strike Global Offensive\game\csgo\cfg`.
2. Один раз в консоли: `exec v3` (или добавить `exec v3` в свой `autoexec.cfg`).
3. В главном меню `exec v3` (задаёт `fps_max 120`, в демке его менять нельзя), затем `playdemo name` и в демке `fe`.
4. Список клавиш и команд: `fehelp`.

Ошибки `Unknown command` при первой загрузке допустимы. Редактировать нужно только `v3_user.cfg`.

## Файлы
| Файл | Назначение |
|---|---|
| `v3.cfg` | вход, алиасы `fe`, `reset`, `fehelp`, `r_user` |
| `v3_user.cfg` | **все ваши настройки**: путь записи, кодеки, FOV, вьюмодель, звук, скорости |
| `v3_unlock.cfg` | разблокировка команд, сброс состояния демки, `mirv_fix` |
| `v3_ffmpeg.cfg` | пресеты вывода: utTrue, prores, good, Prores4444, ffDepth (10-bit depth), median depth, blur |
| `v3_streams.cfg` | потоки: screen, beauty, depth8, depthexr, depth10, depthmed, 6 alpha-matte, audio, cam, campath + пресеты `s_*` |
| `v3_playback.cfg` | скорость демки, пауза, перемотки `mirv_skip` |
| `v3_camera.cfg` | POV / free cam, скорость камеры, ориентация |
| `v3_campath.cfg` | кампат: точки, выбор, правка, интерполяция, слоты сохранения |
| `v3_killfeed.cfg` | `mirv_deathmsg`: фильтры, подсветка, цвета CT/T |
| `v3_visual.cfg` | HUD, bloom, DOF, небо, дым, флешка |
| `v3_record.cfg` | старт и стоп записи, blur, `mirv_cmd`; **применяет `v3_user.cfg`** |
| `v3_help.cfg`, `v3_h_*.cfg`, `v3_reset.cfg`, `v3_logsLow/Default.cfg` | справка (меню `fehelp` и страницы `h_play`, `h_cam`, `h_path`, `h_rec`, `h_streams`, `h_vis`, `h_kf`, `h_cmd`, `h_all`), сброс биндов, уровень логов |

## Что записывать в AE / Blender / C4D
| Нужно | Пресет | Что получите |
|---|---|---|
| Картинка + depth + камера | `s_edit` | beauty (ProRes 4444), depth8 (lossless avi), `.cam`, campath |
| Depth высокой точности | `s_exr` или `s_d10` | EXR-последовательность или 10-bit ProRes |
| Чистый depth без крапинок | `s_med` | depth с медианным фильтром (два потока в один файл) |
| Слои с альфой | `s_matte` | world, weapons, players, viewmodel, particles black/white |
| Всё сразу | `s_all` | + screen |

- Камеру (`.cam`) пишет поток `cam`, импортёры: страница related-tools в репозитории HLAE
  (Blender: "HLAE camera motion and Blender", C4D: "HLAE Cam 2 Cinema4D", AE: HLAE Cam Importer).
- Кодеки на поток меняются в `v3_user.cfg`, алиас `applyPresets1/2`.
- Motion blur: `INS` (`blur_on`), потом запись на высоком fps (`1000fps` + blur 24 = ~42 сэмпла).

## Что изменено относительно старых конфигов
- Убраны CS:GO-команды, опечатки и незакрытые кавычки из MVMCS2 (`cl_drawhud 0qsstsssssssa`, `mat_suppress`, `sv_nomvp`, `fog_*`, `mirv_cvar_hack`, `mirv_deathmsg cfg noticeLifeTime`).
- Убран отладочный бинд `]` -> `demo_goto 92198` (перебивал снятие выделения точки кампата).
- Пресеты потоков стали явными (`s_*` выключают всё и включают нужное) и не «переворачиваются» при повторном `fe`.
- Корректные сообщения у `campathPlayback` (раньше текст был наоборот).
- Все настройки в одном файле, порядок загрузки зафиксирован, дубли удалены.
- Добавлены: alpha-matte потоки, 10-bit depth, median depth, слоты кампата + автобэкап, `mirv_cmd` (`at_*`, `cmdsave/cmdload`), цвета киллфида, `mirv_sky`, дым и флешка, перемотка вперёд.
- Не перенесены: `utSplit`/`EXRSplit`/`utTrueSplit` (сплит цвет+depth в один avi). Заменены отдельными потоками.

## Проверьте в игре
Часть команд взята из документации без проверки на вашей версии CS2. Если что-то выдаёт `Unknown command`, введите команду без аргументов и посмотрите справку:
- `mirv_noflash` (`flash0/1`), `sc_setclassflags SmokeVolumeObject` (`smoke0/1`), значение 8 взято по аналогии с SkinnedObject.
- `mirv_cmd add ...` в алиасах `at_*`, `mirv_cmd clear`.
- `mirv_fov handleZoom enabled 1`.
- Не включены (смотрите справку HLAE): `mirv_endofmatch`, `mirv_panorama`, `mirv_glow`, `mirv_reshade`, `mirv_replace_name`, `mirv_script_*`.
