# Notice

Orbit is a modified version of [cosmic-comp](https://github.com/pop-os/cosmic-comp),
the COSMIC compositor by System76. It is not a System76 project and is not
supported by the COSMIC developers.

## Licence

GPL-3.0-only, the same as upstream. See [LICENSE](LICENSE). The upstream
copyright notices and SPDX headers are kept unchanged.

## Modifications (GPL-3.0 section 5(a))

This version adds a horizontally scrolling tiling layout to cosmic-comp:

- `src/shell/layout/scrolling/` is new.
- Its integration touches the tiling layout, shell, input, gesture, key binding
  and config code, and adds a `tiling_engine` setting to `cosmic-comp-config`.

| Date       | Change                                                                 |
|------------|------------------------------------------------------------------------|
| 2026-09-14 | Scrolling prototype written by miguel-das on top of upstream `8304b18` (epoch-1.6.0 + 4). |
| 2026-11-15 | Imported into this fork and rebased onto upstream `epoch-1.11.0`.      |

`git log upstream/master..main` lists every change in this fork.

## Origin and credit

The scrolling layout started as
[miguel-das/cosmic_scrolling_prototype](https://github.com/miguel-das/cosmic_scrolling_prototype).
That project describes itself as an unmaintained proof of concept and invites
forks. According to its README, it was AI-generated (GPT 5.6 Sol) step by step
and tested by its author. The import commit keeps miguel-das as its author.

The companion panel applet lives in the `orbit-applets` fork of
[cosmic-applets](https://github.com/pop-os/cosmic-applets), and has the same
origin.
