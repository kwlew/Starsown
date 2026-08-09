# TD Idle

## Features

![Version](https://img.shields.io/badge/version-v0.0.2-black?style=for-the-badge
)
![Build](https://img.shields.io/badge/build-passing-brightgreen?style=for-the-badge
)


- **Three tower types**, each with five upgrade levels — a fast single-target
  gun, a splash tower that slows what it hits, and a heavy cannon.
- **Idle progression** | waves advance and towers fight on their own, and time
  spent away from the game earns gold against your run's own pace.
- **Active tools** | call a wave early for a gold bonus, or trigger a burst of
  fire rate right when a tough wave needs it.
- **No game over** | running out of lives sets you back instead of wiping the
  run; your towers and gold carry on.
- **Nine color themes**, switchable any time from Options.
- **English, Spanish, and Portuguese** localization.
- Discord Rich Presence and an achievement tree (still under construction).

## Controls

| Input | Action |
|---|---|
| Click a tile | Build the selected tower there, or select the tower already on it |
| `1` `2` `3` | Pick a tower to build |
| `Space` | Call the next wave early |
| `E` | Trigger Overcharge |
| `U` | Upgrade the selected tower |
| `Delete` / `Backspace` | Sell the selected tower |
| Right-click | Cancel building / deselect |
| `Esc` | Pause |

## Playing it

Requires [LÖVE 11.5](https://love2d.org/). From the project root:

```
love src
```

Progress saves automatically — on a timer, when you pause, and when you quit.
