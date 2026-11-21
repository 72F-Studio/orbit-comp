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
- Strip overview; click a window to go to it.
- Focus and move columns by number (Super+Alt+1-9).
- Squeeze a neighbour on screen.
- Per-app widths from the focused window (Super+Alt+W), listed in the applet.
- Every Orbit action can be rebound in COSMIC Settings as an `orbit ...`
  custom shortcut.
- Collapsible Scrolling section in the applet.
- Tabbed columns, through COSMIC's existing window stacks (Super+S).

## Next

| Feature | Notes | Effort |
|---|---|---|
| Hover in the overview | Pointer motion still goes to the unzoomed positions; only clicks are mapped | S |
| Per-workspace centering mode | PaperWM lets each workspace pick its own | M |
| Orbit page in COSMIC Settings | Needs a fork of pop-os/cosmic-settings; the applet covers the same settings | L |

## Maintenance

- Rebase `main` onto each COSMIC epoch tag (`git fetch upstream`, then
  `git rebase epoch-X.Y.Z`). Keep Orbit code in its own files
  (`src/shell/layout/scrolling/`, `src/backend/render/scrolling_backdrop.rs`)
  and keep hooks in upstream files small and marked `// Orbit:`.
- Move the `orbit-applets` dependency on `cosmic-comp-config` to a git URL
  once `orbit-comp` is published.
