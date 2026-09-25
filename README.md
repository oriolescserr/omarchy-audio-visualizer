# Audio Visualizer

An **Omarchy** bar widget that visualizes whatever you're listening to as a row of **spectrum bars**, with smooth movement and a subtle **fade in** / **fade out** when playback starts or stops.

[Cava](https://github.com/karlstav/cava) reads the **PipeWire** audio output, allowing the bars to react to the music in real time. The widget takes up **no space at all** when nothing is playing and automatically uses the bar's own **foreground colour**.

<div align="center">
    <img src="preview.png" alt="Audio Visualizer preview" width="700">
</div>

## Install

```bash
omarchy pkg add cava
omarchy plugin add https://github.com/oriolescserr/omarchy-audio-visualizer --enable
```

## Use

It works with anything that supports MPRIS: Spotify, browsers, mpv, VLC, and more.

| Action           | Result                                                                        |
| ---------------- | ----------------------------------------------------------------------------- |
| **Hover**        | Title over artist, in a bar-native tooltip. Long titles scroll like a ticker. |
| **Left click**   | A card with album art, album, progress and previous / play-pause / next       |
| **Middle click** | Pause                                                                         |

Album art is only loaded while the card is open. Players that send an `https` link (Spotify, browsers) have it downloaded with `curl`, limited to 4 MiB, 10 seconds and JPEG, PNG or WebP images up to 4096 px; anything else shows a placeholder.

### Keyboard

You can use the following keyboard shortcuts while the player is open:

| Key                  | Action                        |
| -------------------- | ----------------------------- |
| **Space** / **Enter** | Play / pause                  |
| **←** **→** (h l)    | Back / forward 5 seconds      |
| **↑** **↓** (k j)    | Player volume up / down       |
| **N** / **P**        | Next / previous track         |
| **0** - **9**          | Jump to 0 %–90 % of the track |
| **Esc**              | Close                         |

To open it without the mouse, bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + M", "Music Visualizer Card", "omarchy-shell oriolus.audio-visualizer toggle")
```

The same target also supports `open`, `close`, `playPause`, `next`, `previous`, `forward`, and `back` (10 seconds), so each of them can have its own key.

## Settings

The bar count is defined in the widget's entry in `~/.config/omarchy/shell.json`, between **4** and **32**:

```bash
omarchy bar set oriolus.audio-visualizer bars 14
```

## Uninstall

```bash
omarchy plugin remove oriolus.audio-visualizer
```

Drop `cava` with `omarchy pkg drop cava` if nothing else is using it.