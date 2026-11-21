use cosmic_settings_config::shortcuts::State as KeyState;
use cosmic_settings_config::shortcuts::{self, Modifiers};
use smithay::input::keyboard::{Keysym, ModifiersState};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Action {
    /// Behaviors managed internally by cosmic-comp.
    Private(PrivateAction),
    /// Behaviors managed via cosmic-settings.
    Shortcut(shortcuts::Action),
}

#[derive(Clone, Debug, Eq, PartialEq)]
// Behaviors which are internally defined and emitted.
pub enum PrivateAction {
    Escape,
    CenterScrollingColumn,
    /// Orbit: strip actions (scroll view, first/last, move column, ...).
    Strip(crate::shell::layout::scrolling::StripAction),
    /// Orbit: hide or show the workspace's floating windows.
    ToggleScratchLayer,
    /// Orbit: zoom out to see the whole strip.
    ToggleStripOverview,
    /// Orbit: open the focused window's app at its current width from now on.
    RememberWidth,
    Resizing(
        shortcuts::action::ResizeDirection,
        shortcuts::action::ResizeEdge,
        shortcuts::State,
    ),
}

/// Default compositor-private binding which is not yet represented by the
/// public cosmic-settings shortcut action enum.
pub fn center_scrolling_binding() -> shortcuts::Binding {
    shortcuts::Binding {
        modifiers: Modifiers {
            logo: true,
            ..Modifiers::default()
        },
        keycode: None,
        key: Some(Keysym::c),
        description: None,
    }
}

/// Orbit: shortcuts that only apply on a tiled Scrolling workspace, and only
/// when no configured COSMIC shortcut uses the same keys. None of these clash
/// with COSMIC's defaults (Super+1-9 and Super+Escape are taken, so focus by
/// number and PaperWM's Super+Escape scratch toggle use other keys).
pub fn scrolling_bindings() -> Vec<(shortcuts::Binding, PrivateAction)> {
    use crate::shell::layout::scrolling::StripAction;
    let bind_with = |alt: bool, shift: bool, key: Keysym| shortcuts::Binding {
        modifiers: Modifiers {
            logo: true,
            alt,
            shift,
            ..Modifiers::default()
        },
        keycode: None,
        key: Some(key),
        description: None,
    };
    let bind = |shift: bool, key: Keysym| bind_with(false, shift, key);
    const DIGITS: [Keysym; 9] = [
        Keysym::_1,
        Keysym::_2,
        Keysym::_3,
        Keysym::_4,
        Keysym::_5,
        Keysym::_6,
        Keysym::_7,
        Keysym::_8,
        Keysym::_9,
    ];
    vec![
        (
            center_scrolling_binding(),
            PrivateAction::CenterScrollingColumn,
        ),
        (
            bind(false, Keysym::Page_Up),
            PrivateAction::Strip(StripAction::ScrollView(-1)),
        ),
        (
            bind(false, Keysym::Page_Down),
            PrivateAction::Strip(StripAction::ScrollView(1)),
        ),
        (
            bind(false, Keysym::Home),
            PrivateAction::Strip(StripAction::FocusEdge(false)),
        ),
        (
            bind(false, Keysym::End),
            PrivateAction::Strip(StripAction::FocusEdge(true)),
        ),
        (
            bind(true, Keysym::Page_Up),
            PrivateAction::Strip(StripAction::MoveColumn(-1)),
        ),
        (
            bind(true, Keysym::Page_Down),
            PrivateAction::Strip(StripAction::MoveColumn(1)),
        ),
        (
            bind(true, Keysym::Home),
            PrivateAction::Strip(StripAction::MoveColumnToEdge(false)),
        ),
        (
            bind(true, Keysym::End),
            PrivateAction::Strip(StripAction::MoveColumnToEdge(true)),
        ),
        (
            bind(false, Keysym::e),
            PrivateAction::Strip(StripAction::Equalize),
        ),
        (
            bind(true, Keysym::e),
            PrivateAction::Strip(StripAction::Expand),
        ),
        (
            bind(false, Keysym::grave),
            PrivateAction::ToggleScratchLayer,
        ),
        (bind(true, Keysym::o), PrivateAction::ToggleStripOverview),
        (
            bind(false, Keysym::bracketleft),
            PrivateAction::Strip(StripAction::Squeeze(-1)),
        ),
        (
            bind(false, Keysym::bracketright),
            PrivateAction::Strip(StripAction::Squeeze(1)),
        ),
        (
            bind_with(true, false, Keysym::w),
            PrivateAction::RememberWidth,
        ),
        (
            bind_with(true, false, Keysym::c),
            PrivateAction::Strip(StripAction::CycleCentering),
        ),
    ]
    .into_iter()
    .chain(DIGITS.iter().enumerate().flat_map(|(index, key)| {
        [
            (
                bind_with(true, false, *key),
                PrivateAction::Strip(StripAction::FocusIndex(index)),
            ),
            (
                bind_with(true, true, *key),
                PrivateAction::Strip(StripAction::MoveToIndex(index)),
            ),
        ]
    }))
    .collect()
}

/// Orbit: actions you can bind in COSMIC Settings, under Custom shortcuts,
/// with the command `orbit <action>`. Orbit runs these itself instead of
/// launching a program. Outside Orbit nothing is called `orbit`, so the
/// shortcut does nothing.
pub fn parse_orbit_command(command: &str) -> Option<PrivateAction> {
    use crate::shell::layout::scrolling::StripAction;
    let mut words = command.split_whitespace();
    if words.next()? != "orbit" {
        return None;
    }
    let action = words.next()?;
    let rest = words.collect::<Vec<_>>();
    // Either no argument, or exactly one column number starting at 1.
    let number = match rest.as_slice() {
        [] => None,
        [word] => Some(word.parse::<usize>().ok().filter(|n| *n >= 1)?),
        _ => return None,
    };
    let strip = PrivateAction::Strip;
    Some(match (action, number) {
        ("center", None) => PrivateAction::CenterScrollingColumn,
        ("scroll-left", None) => strip(StripAction::ScrollView(-1)),
        ("scroll-right", None) => strip(StripAction::ScrollView(1)),
        ("focus-first", None) => strip(StripAction::FocusEdge(false)),
        ("focus-last", None) => strip(StripAction::FocusEdge(true)),
        ("move-column-left", None) => strip(StripAction::MoveColumn(-1)),
        ("move-column-right", None) => strip(StripAction::MoveColumn(1)),
        ("move-column-first", None) => strip(StripAction::MoveColumnToEdge(false)),
        ("move-column-last", None) => strip(StripAction::MoveColumnToEdge(true)),
        ("equalize", None) => strip(StripAction::Equalize),
        ("expand", None) => strip(StripAction::Expand),
        ("squeeze-left", None) => strip(StripAction::Squeeze(-1)),
        ("squeeze-right", None) => strip(StripAction::Squeeze(1)),
        ("focus-column", Some(n)) => strip(StripAction::FocusIndex(n - 1)),
        ("move-to-column", Some(n)) => strip(StripAction::MoveToIndex(n - 1)),
        ("scratch", None) => PrivateAction::ToggleScratchLayer,
        ("overview", None) => PrivateAction::ToggleStripOverview,
        ("remember-width", None) => PrivateAction::RememberWidth,
        ("centering", None) => strip(StripAction::CycleCentering),
        _ => return None,
    })
}

/// Convert `cosmic_settings_config::shortcuts::State` to `smithay::backend::input::KeyState`.
pub fn cosmic_keystate_to_smithay(value: KeyState) -> smithay::backend::input::KeyState {
    match value {
        KeyState::Pressed => smithay::backend::input::KeyState::Pressed,
        KeyState::Released => smithay::backend::input::KeyState::Released,
    }
}

/// Convert `smithay::backend::input::KeyState` to `cosmic_settings_config::shortcuts::State`.
pub fn cosmic_keystate_from_smithay(value: smithay::backend::input::KeyState) -> KeyState {
    match value {
        smithay::backend::input::KeyState::Pressed => KeyState::Pressed,
        smithay::backend::input::KeyState::Released => KeyState::Released,
    }
}

/// Compare `cosmic_settings_config::shortcuts::Modifiers` to `smithay::input::keyboard::ModifiersState`.
pub fn cosmic_modifiers_eq_smithay(this: &Modifiers, other: &ModifiersState) -> bool {
    this.ctrl == other.ctrl
        && this.alt == other.alt
        && this.shift == other.shift
        && this.logo == other.logo
}

/// Convert `smithay::input::keyboard::ModifiersState` to `cosmic_settings_config::shortcuts::Modifiers`
pub fn cosmic_modifiers_from_smithay(value: ModifiersState) -> Modifiers {
    Modifiers {
        ctrl: value.ctrl,
        alt: value.alt,
        shift: value.shift,
        logo: value.logo,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orbit_commands_parse() {
        use crate::shell::layout::scrolling::StripAction;
        assert_eq!(
            parse_orbit_command("orbit focus-first"),
            Some(PrivateAction::Strip(StripAction::FocusEdge(false)))
        );
        assert_eq!(
            parse_orbit_command("  orbit   move-to-column 3 "),
            Some(PrivateAction::Strip(StripAction::MoveToIndex(2)))
        );
        assert_eq!(parse_orbit_command("orbit focus-column 0"), None);
        assert_eq!(parse_orbit_command("orbit focus-column"), None);
        assert_eq!(parse_orbit_command("orbit overview extra"), None);
        assert_eq!(parse_orbit_command("orbitx overview"), None);
        assert_eq!(parse_orbit_command("firefox"), None);
        assert_eq!(parse_orbit_command("orbit nonsense"), None);
    }

    #[test]
    fn orbit_bindings_are_unique() {
        let bindings = scrolling_bindings();
        for (index, (binding, _)) in bindings.iter().enumerate() {
            for (other, _) in &bindings[index + 1..] {
                assert!(
                    !(binding.key == other.key && binding.modifiers == other.modifiers),
                    "duplicate binding {binding:?}"
                );
            }
        }
    }

    #[test]
    fn scrolling_center_uses_super_c_without_extra_modifiers() {
        let binding = center_scrolling_binding();
        assert_eq!(binding.key, Some(Keysym::c));
        assert!(binding.modifiers.logo);
        assert!(!binding.modifiers.ctrl);
        assert!(!binding.modifiers.alt);
        assert!(!binding.modifiers.shift);
    }
}
