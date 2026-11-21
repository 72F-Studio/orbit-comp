// SPDX-License-Identifier: GPL-3.0-only

//! Orbit: blur the wallpaper and desktop icons behind a scrolling workspace.
//!
//! In Scrolling mode the strip of columns rarely covers the whole output, so
//! the desktop shows through the gaps and past the ends of the strip. A single
//! output-sized backdrop blur is drawn between the workspace's windows and the
//! bottom and background layer-shell surfaces, so those layers turn into a
//! soft wash instead of a wall of icons. Panels live on the top layer and are
//! not affected.

use std::sync::{
    Mutex,
    atomic::{AtomicBool, AtomicU32, Ordering},
};

use cosmic_comp_config::TilingEngine;
use smithay::{
    backend::renderer::{ImportAll, element::Id},
    desktop::layer_map_for_output,
    output::Output,
    utils::{Logical, Rectangle},
};

use crate::{
    backend::render::{
        BackdropShader,
        element::AsGlowRenderer,
        wayland::{
            SurfaceRenderElement,
            blur_effect::{BlurElement, BlurState},
        },
    },
    shell::Workspace,
    utils::{
        geometry::{Local, RectExt, SizeExt},
        prelude::OutputExt,
    },
};

/// Index into the blur parameter table (0..=14). High enough that desktop
/// icons and their labels can't be read through it.
const BACKDROP_BLUR_STRENGTH: usize = 12;

/// Follows the `scrolling.backdrop_blur` setting.
static BACKDROP_BLUR_ENABLED: AtomicBool = AtomicBool::new(true);

/// Turn the backdrop blur on or off for every output.
pub fn set_backdrop_blur_enabled(enabled: bool) {
    BACKDROP_BLUR_ENABLED.store(enabled, Ordering::Relaxed);
}

/// Follows `scrolling.offscreen_opacity`, stored as `f32` bits. 1.0 is off.
static OFFSCREEN_OPACITY: AtomicU32 = AtomicU32::new(0x3f80_0000); // 1.0

/// Set the opacity of windows that are partly off screen.
pub fn set_offscreen_opacity(opacity: f32) {
    OFFSCREEN_OPACITY.store(opacity.clamp(0.2, 1.0).to_bits(), Ordering::Relaxed);
}

/// Opacity for partly off-screen windows on scrolling workspaces.
pub fn offscreen_opacity() -> f32 {
    f32::from_bits(OFFSCREEN_OPACITY.load(Ordering::Relaxed))
}

/// Follows `scrolling.position_indicator`.
static POSITION_INDICATOR_ENABLED: AtomicBool = AtomicBool::new(true);

/// Turn the strip position indicator on or off.
pub fn set_position_indicator_enabled(enabled: bool) {
    POSITION_INDICATOR_ENABLED.store(enabled, Ordering::Relaxed);
}

/// Orbit: whether the strip overview (zoomed-out view) is shown.
static STRIP_OVERVIEW: AtomicBool = AtomicBool::new(false);

/// Toggle the strip overview.
pub fn toggle_strip_overview() {
    STRIP_OVERVIEW.fetch_xor(true, Ordering::Relaxed);
}

/// Leave the strip overview, for example when focus changes.
pub fn close_strip_overview() {
    STRIP_OVERVIEW.store(false, Ordering::Relaxed);
}

/// Whether the strip overview is shown.
pub fn strip_overview_open() -> bool {
    STRIP_OVERVIEW.load(Ordering::Relaxed)
}

/// Whether the strip position indicator should be drawn.
pub fn position_indicator_enabled() -> bool {
    POSITION_INDICATOR_ENABLED.load(Ordering::Relaxed)
}

/// Whether `workspace` should get the backdrop blur: tiling is on, it uses the
/// Scrolling engine, it has at least one tiled window, and nothing is
/// fullscreen (the lower layers aren't drawn then anyway).
pub fn wants_backdrop_blur(workspace: &Workspace) -> bool {
    BACKDROP_BLUR_ENABLED.load(Ordering::Relaxed)
        && workspace.tiling_enabled
        && workspace.tiling_layer.mode() == TilingEngine::Scrolling
        && workspace.fullscreen_surfaces.is_empty()
        && workspace.tiling_layer.mapped().next().is_some()
}

/// Builds the output-sized backdrop blur for `workspace`, or `None` when the
/// workspace doesn't want one.
pub fn backdrop_blur_element<R>(
    renderer: &mut R,
    output: &Output,
    workspace: &Workspace,
) -> Option<SurfaceRenderElement<R>>
where
    R: AsGlowRenderer + ImportAll,
    R::TextureId: Send + 'static,
{
    if !wants_backdrop_blur(workspace) {
        return None;
    }

    let size = output.geometry().size.as_logical().to_f64();
    let geometry = Rectangle::<f64, Logical>::from_size(size);
    let scale = output.current_scale().fractional_scale();

    let state = output
        .user_data()
        .get_or_insert_threadsafe(|| ScrollingBackdropBlur(Mutex::new(BlurState::default())));
    let mut state = state.0.lock().unwrap();

    match BlurElement::from_state(
        renderer,
        &mut state,
        geometry,
        scale,
        [0; 4],
        BACKDROP_BLUR_STRENGTH,
    ) {
        Ok(elem) => elem.map(SurfaceRenderElement::from),
        Err(err) => {
            tracing::warn!(?err, "Failed to build the scrolling backdrop blur");
            None
        }
    }
}

/// Per-output blur cache, kept in the output's user data so the blurred
/// texture is reused between frames.
struct ScrollingBackdropBlur(Mutex<BlurState>);

/// Element ids for the indicator, kept per output so damage tracking works.
struct IndicatorIds {
    track: Id,
    thumb: Id,
}

const INDICATOR_HEIGHT: i32 = 4;
const INDICATOR_MARGIN: i32 = 8;
const INDICATOR_MIN_THUMB: i32 = 24;

/// Where the indicator's track and thumb go, in output-local coordinates.
/// `zone` is the usable area; the bar sits just inside its bottom edge.
pub fn indicator_geometry(
    zone: Rectangle<i32, Local>,
    viewport_x: f64,
    viewport_width: i32,
    strip_width: f64,
) -> Option<(Rectangle<i32, Local>, Rectangle<i32, Local>)> {
    let track_width = zone.size.w - 2 * INDICATOR_MARGIN;
    if track_width <= INDICATOR_MIN_THUMB || strip_width <= viewport_width as f64 {
        return None;
    }
    let y = zone.loc.y + zone.size.h - INDICATOR_MARGIN - INDICATOR_HEIGHT;
    let track = Rectangle::new(
        (zone.loc.x + INDICATOR_MARGIN, y).into(),
        (track_width, INDICATOR_HEIGHT).into(),
    );
    let scale = track_width as f64 / strip_width;
    let thumb_width =
        ((viewport_width as f64 * scale).round() as i32).clamp(INDICATOR_MIN_THUMB, track_width);
    let thumb_x =
        ((viewport_x.max(0.0) * scale).round() as i32).clamp(0, track_width - thumb_width);
    let thumb = Rectangle::new(
        (track.loc.x + thumb_x, y).into(),
        (thumb_width, INDICATOR_HEIGHT).into(),
    );
    Some((track, thumb))
}

/// Orbit: PaperWM-style bar marking which part of the strip is on screen.
/// Drawn only while the strip is wider than the screen.
pub fn position_indicator_elements(
    renderer: &impl AsGlowRenderer,
    output: &Output,
    workspace: &Workspace,
    accent: [f32; 3],
) -> Vec<smithay::backend::renderer::gles::element::PixelShaderElement> {
    if !position_indicator_enabled()
        || !workspace.tiling_enabled
        || !workspace.fullscreen_surfaces.is_empty()
    {
        return Vec::new();
    }
    let Some((viewport_x, viewport_width, strip_width)) =
        workspace.tiling_layer.scrolling_strip_metrics()
    else {
        return Vec::new();
    };
    let zone = layer_map_for_output(output).non_exclusive_zone().as_local();
    let Some((track, thumb)) = indicator_geometry(zone, viewport_x, viewport_width, strip_width)
    else {
        return Vec::new();
    };
    let ids = output
        .user_data()
        .get_or_insert_threadsafe(|| IndicatorIds {
            track: Id::new(),
            thumb: Id::new(),
        });
    let radius = INDICATOR_HEIGHT as f32 / 2.0;
    vec![
        BackdropShader::element(renderer, ids.thumb.clone(), thumb, radius, 0.9, accent),
        BackdropShader::element(
            renderer,
            ids.track.clone(),
            track,
            radius,
            0.25,
            [0.5, 0.5, 0.5],
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn zone() -> Rectangle<i32, Local> {
        Rectangle::new((0, 0).into(), (1_016, 800).into())
    }

    #[test]
    fn indicator_thumb_tracks_the_viewport() {
        // Track is 1000 wide. A 2000-wide strip with a 1000-wide viewport at
        // 500 gives a 500-wide thumb starting 250 in.
        let (track, thumb) = indicator_geometry(zone(), 500.0, 1_000, 2_000.0).unwrap();
        assert_eq!(track.size.w, 1_000);
        assert_eq!(thumb.size.w, 500);
        assert_eq!(thumb.loc.x - track.loc.x, 250);
        assert_eq!(thumb.loc.y, 800 - INDICATOR_MARGIN - INDICATOR_HEIGHT);
    }

    #[test]
    fn indicator_is_hidden_when_the_strip_fits() {
        assert!(indicator_geometry(zone(), 0.0, 1_000, 900.0).is_none());
    }

    #[test]
    fn indicator_thumb_stays_inside_the_track() {
        let (track, thumb) = indicator_geometry(zone(), 99_000.0, 1_000, 100_000.0).unwrap();
        assert!(thumb.size.w >= INDICATOR_MIN_THUMB);
        assert!(thumb.loc.x + thumb.size.w <= track.loc.x + track.size.w);
        let (_, thumb) = indicator_geometry(zone(), -300.0, 1_000, 2_000.0).unwrap();
        assert_eq!(thumb.loc.x, INDICATOR_MARGIN);
    }
}
