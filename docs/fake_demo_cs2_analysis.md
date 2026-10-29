# Fake demo: CS:GO → CS2, разбор функций

Источник: конспект и транскрипт в `D:\I\Нейросеть\Промты\Гейм эдитинг`, видео Rikki «How to record fake demo in CSGO» (кадры 6:50 и 17:45 подтверждают таблицу биндов и меню Bot Mimic из конспекта).

Статусы: ✅ есть в CS2 штатно · 🟡 есть, но нужно проверить имя/поведение командой в игре · 🔧 есть через плагин CounterStrikeSharp (CSS) · ❌ аналога нет, надо строить.
Всё 🟡 взято из моих знаний, в игре не проверено.

## 1. Основа: сервер и запись
| CS:GO | Что делало | CS2 | Статус |
|---|---|---|---|
| migi + `-insecure` | локальный сервер с модами | listen-сервер: `-insecure` + `map de_mirage`. Плагины (Metamod:Source 2 + CounterStrikeSharp) надёжно работают на **локальном dedicated-сервере** (SteamCMD, `cs2.exe -dedicated`), к нему подключаемся клиентом | 🟡 listen / 🔧 dedicated |
| SourceMod + MetaMod | ядро плагинов | Metamod:Source 2.x + CounterStrikeSharp (плагины на C#) | 🔧 |
| `admin_simple.ini` | права | CSS `configs/admins.json` | 🔧 |
| `-tickrate 128` | 128 тиков | в CS2 subtick, демо 64 тика; ключ не нужен | ✅ (не нужно) |
| `fake` в меню: `tv_enable 1` | без этого нет демки | то же: `tv_enable 1` до `map`, потом `tv_record name` / `tv_stoprecord` | 🟡 |
| «убей 2–3 бота, иначе лаги» | баг CS:GO | неизвестно, проверить | 🟡 |

## 2. Бинды `_fake.cfg`
| Клавиша / функция | CS2 команда | Статус |
|---|---|---|
| F1 рестарт / разминка | `mp_restartgame 1`, `mp_warmup_start`, `mp_warmuptime 9999` | ✅ |
| Бесконечные патроны, без отдачи, банихоп | `sv_infinite_ammo 1`, `weapon_recoil_scale 0`, `sv_autobunnyhopping 1`, `sv_enablebunnyhopping 1` | ✅ |
| F2/F3 наборы оружия | `give weapon_ak47` и т.д., `give item_assaultsuit` | ✅ |
| X убрать декали | `r_cleardecals` | 🟡 |
| V noclip | `noclip` | ✅ |
| T buddha | `buddha` / `god` | 🟡 (god точно есть) |
| Backspace, `<` `>` кик/добавить ботов | `bot_kick`, `bot_add_ct`, `bot_add_t` | ✅ |
| Q респавн ботов | `mp_respawn_on_death_ct/t 1` или рестарт | 🟡 |
| O боты ходят / стоп | `bot_stop 1/0`, `bot_freeze` | ✅ |
| P поставить бота | `bot_place` | ✅ |
| K убить ботов | `bot_kill` | ✅ |
| Z ×10, Mouse5 ×0.5 | `host_timescale` (sv_cheats) | ✅ |
| Del стоп записи | `tv_stoprecord` | ✅ |
| RShift 3-е лицо | `thirdperson` / `firstperson`, `cam_idealdist` | 🟡 |
| Enter «maya»-режим | нет; заменяется HLAE-камерой уже на этапе демки | ❌ (не нужно) |

## 3. Bot Mimic (главное)
| Функция | CS2 | Статус |
|---|---|---|
| Записать своё движение, отдать боту, проиграть синхронно по Q | готового надёжного порта не знаю. Есть `bot_mimic 1` (бот повторяет твои действия **вживую**, не по записи) — для POV-боя не годится | ❌ |
| Категории, переименование, удаление, меню H | — | ❌ |

Путь: свой CSS-плагин «recorder/replayer»: каждый тик пишет позицию, углы, кнопки, оружие игрока в файл; при проигрыше телепортирует бота и жмёт за него кнопки. Это самая крупная работа во всём списке. HLAE mirv-script тут не помогает: он работает на стороне клиента и ботами сервера управлять не может.

## 4. Карты
| CS:GO | CS2 | Статус |
|---|---|---|
| Workshop → кастомная (BSPSource, переименование .bsp/.kv/.nav) | не нужно: `host_workshop_map <id>` / `map_workshop`, навигация `nav_generate`. Ограничение Bot Mimic на workshop в CS2 не переносится | ✅ |
| `buildcubemaps` | в CS2 отражения запечены, не нужно | ✅ (не нужно) |

## 5. Скины, ножи, перчатки, агенты, модели
| CS:GO | CS2 | Статус |
|---|---|---|
| Weapons & Knives + PTAH, Gloves (`!ws`, `!knife`, `!gloves`) | плагин CS2-WeaponPaints (CSS) — скины, ножи, перчатки, агенты; скины попадают в демку | 🔧 |
| Agents Chooser (`!agents`) | тот же WeaponPaints / агенты | 🔧 |
| `.kv` с моделями команд | нет | ❌ |
| Кастомные модели (Hu Tao) PlayerSkin + ArmsFix | только через addon-vpk + CSS-плагин замены модели, сложно | ❌ (тяжело) |
| nSkinz в HLAE | в CS2 нет | ❌ |

## 6. Мелочи
| CS:GO | CS2 | Статус |
|---|---|---|
| `sv_gravity` (пишется в демку) | `sv_gravity` | ✅ |
| `cl_ragdoll_gravity`, `cl_phys_timescale` | проверить `find ragdoll`, `find phys_timescale` | 🟡 |
| Револьвер без разброса (правка items_game) | `weapon_accuracy_nospread 1` для всего оружия | 🟡 |
| `sniper` / `nade` | `weapon_debug_spread_show`, `sv_grenade_trajectory_prac_pipreview 1` | 🟡 |
| `items`: шорткаты `ak`, `r8` | алиасы на `give` | ✅ |
| Weapons CleanUp | `weapon_auto_cleanup_time`, `weapon_max_before_cleanup` | 🟡 |
| Damage Mod `damage_deagle 10` | `mp_damage_scale_ct_body/head`, `mp_damage_scale_t_body/head` (по команде, не по оружию); по оружию — только плагин | 🟡 / 🔧 |
| DEMOPACK | демка + id workshop-карты, моделей нет | ✅ |
| «После обновления всё сломалось» | Metamod/CSS тоже ломаются после патчей CS2, обновлять | 🔧 |

## Итог: чего нет
1. **Записи и проигрыша движений ботами (Bot Mimic).** Главный пробел, нужен свой CSS-плагин.
2. **Скины/ножи/агенты** есть только через плагин WeaponPaints, нужен dedicated-сервер с Metamod+CSS.
3. **Кастомные модели игроков**: реально, но дорого; предлагаю отложить.
4. Всё остальное (бинды, читы, время, гравитация, урон, запись `tv_record`) собирается обычным cfg `fake.cfg` поверх v3.
