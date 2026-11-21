# Orbit roadmap

Candidate features, ranked by value. This list was drawn up in November 2026
from [PaperWM](https://github.com/paperwm/PaperWM) (GNOME) and
[Karousel](https://github.com/peterfajdiga/karousel) (KDE), with
[niri](https://github.com/YaLTeR/niri) as a tie-breaker. Effort: S small,
M medium, L large.

## Done

- Backdrop blur behind scrolling workspaces.
- New-window width presets (25/50/75/90%) and custom width.
- Focus follows scroll (opt-in, with a threshold).
- Maximize widens the column instead of floating the window.

## Next

| # | Feature | Seen in | Effort |
|---|---|---|---|
| 1 | **Centering policy** as a setting: only scroll as needed (current), always centre the focused column, or centre when it fits. Plus "centre a lone window" | Karousel `scrollingLazy` / `scrollingCentered` / `scrollingGrouped`; PaperWM focus modes; niri `center-focused-column` | S |
| 2 | **New window position**: right of focused (current) or end of strip | PaperWM `open-window-position` | S |
| 3 | **Keyboard and mouse-wheel scrolling** of the view without moving focus; first/last column on Super+Home/End | Karousel Meta+Alt+PgUp/PgDn, Home/End | S |
| 4 | **Move whole columns** left/right and to start/end | Karousel Meta+Ctrl+Shift+arrows | S |
| 5 | **Focus or move by index**: Super+N, Super+Shift+N | Karousel | S |
| 6 | **Squeeze and equalize**: fit the neighbour on screen, equalize visible widths, expand to fill | Karousel Meta+Ctrl+A/D/X; niri `expand-column-to-available-width` | S–M |
| 7 | **Dim off-screen windows** | Karousel `offScreenOpacity` | S |
| 8 | **Tabbed columns**: show one window of a column, the rest as tabs | Karousel Meta+X; niri tabbed display | M |
| 9 | **Window rules**: always float, or open at a set width, by app ID or title | Karousel `windowRules`; PaperWM winprops `preferredWidth` | M |
| 10 | **Scratch layer** toggle per workspace | PaperWM Super+Escape | M |
| 11 | **Strip position indicator** in the panel applet | PaperWM window position bar | M |
| 12 | **Multi-monitor**: focus and move across the output edge | PaperWM | M |
| 13 | **Overview / zoom-out** of the whole strip | niri, PaperWM minimap | L |

Dialogs and transients already float centred on their parent through
COSMIC's existing dialog handling.

## Maintenance

- Rebase `main` onto each COSMIC epoch tag (`git fetch upstream`, then
  `git rebase epoch-X.Y.Z`). Keep Orbit code in its own files
  (`src/shell/layout/scrolling/`, `src/backend/render/scrolling_backdrop.rs`)
  and keep hooks in upstream files small and marked `// Orbit:`.
- Move the `orbit-applets` dependency on `cosmic-comp-config` to a git URL
  once `orbit-comp` is published.
