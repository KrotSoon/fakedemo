# Сторонние компоненты

FakeDemo скачивает и ставит в CS2 (не меняя их):

| Компонент | Версия | Лицензия | Откуда |
|---|---|---|---|
| Metamod:Source | 2.0.0-git1483 | zlib/libpng | https://www.metamodsource.net |
| CounterStrikeSharp (+ .NET runtime) | 1.0.378 | GPL-3.0 | https://github.com/roflmuffin/CounterStrikeSharp |
| CS2-Bot-Controller | 0.8.0 | AGPL-3.0 | https://github.com/XBribo/CS2-Bot-Controller |

FakeMimic использует API CS2-Bot-Controller; исходники FakeMimic, FakeMimicApi и FakeDirector лежат в `src/` этого репозитория.

Окно меню `overlay\FakeDemoOverlay.exe` содержит Microsoft WebView2 SDK 1.0.2903.40 (BSD-3-Clause, текст лицензии в `overlay\WebView2-LICENSE.txt`); сам WebView2 Runtime уже есть в Windows 10/11.
Точные условия смотри в лицензиях самих проектов.
