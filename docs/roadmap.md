# Orbit roadmap

Candidate features, ranked by value. This list was drawn up in November 2026
from [PaperWM](https://github.com/paperwm/PaperWM) (GNOME) and
[Karousel](https://github.com/peterfajdiga/karousel) (KDE), with
[niri](https://github.com/YaLTeR/niri) as a tie-breaker. Effort: S small,
M medium, L large.

## Done

- Backdrop blur behind scrolling workspaces.
- New-window width presets (25/50/75/90%), custom width and per-app width
  rules (config file only so far).
- Focus follows scroll (opt-in, with a threshold).
- Maximize widens the column instead of floating the window.
- Centering policy (lazy, always, on overflow) and centring a lone column.
- New window position (next to focused, or at the end).
- Scroll the view by a column; focus first/last column.
- Move whole columns left/right and to the start/end.
- Equalize visible columns; expand to fill free space.
- Dim partly off-screen windows.
- Scratch layer toggle for floating windows.
- Strip position indicator.
- Focus crosses to the next monitor at the strip's edge.
- Strip overview (view-only).
- Tabbed columns, through COSMIC's existing window stacks (Super+S).

## Next

| Feature | Notes | Effort |
|---|---|---|
| Clickable overview | Map pointer input through the overview transform, so a click focuses a window | M |
| Applet editor for width rules | Add "open this app at its current width" to the applet | M |
| Focus or move by number | Super+1-9 belong to workspaces; needs another modifier, such as Super+Alt+1-9 | S |
| Squeeze a neighbour on screen | Karousel Meta+Ctrl+A/D | S |
| Per-workspace centering mode | PaperWM lets each workspace pick its own | M |
| Popup height | The applet popup is long while Scrolling is on; consider a scrollable or collapsible section | S |

## Maintenance

- Rebase `main` onto each COSMIC epoch tag (`git fetch upstream`, then
  `git rebase epoch-X.Y.Z`). Keep Orbit code in its own files
  (`src/shell/layout/scrolling/`, `src/backend/render/scrolling_backdrop.rs`)
  and keep hooks in upstream files small and marked `// Orbit:`.
- Move the `orbit-applets` dependency on `cosmic-comp-config` to a git URL
  once `orbit-comp` is published.
