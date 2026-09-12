# Starsown

## Features

![Version](https://img.shields.io/badge/version-v0.2.0-black?style=for-the-badge
)
![Build](https://img.shields.io/badge/build-passing-brightgreen?style=for-the-badge
)


- **Twelve color themes**, switchable any time from Options.
- **English, Spanish, Portuguese, and Russian** localization.
- Discord Rich Presence.

The gameplay itself is still in game design phase.

## Playing it

Requires [LÖVE 11.5](https://love2d.org/). From the project root:

```
love src
```

## UI checks

On Linux with LÖVE installed, run `bash tools/check-ui.sh`. It uses an isolated
copy and save directory under `/tmp`, disables external services, and checks
settings layouts with real fonts/rendering at five window sizes in all four
languages. It also checks scrolling, focus, dialogs, and save flows, and prints
the location of its screenshots. Display transactions use a simulated driver, including rejected modes, fallback
values, missing monitors, and saves during an unconfirmed preview. Monitor
switching and fullscreen Keep/Revert still need an interactive check.
The script uses SDL's offscreen driver by default; set `SDL_VIDEODRIVER` to use
another driver.
