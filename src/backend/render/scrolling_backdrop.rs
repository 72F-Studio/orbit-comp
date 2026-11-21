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
    atomic::{AtomicBool, Ordering},
};

use cosmic_comp_config::TilingEngine;
use smithay::{
    backend::renderer::ImportAll,
    output::Output,
    utils::{Logical, Rectangle},
};

use crate::{
    backend::render::{
        element::AsGlowRenderer,
        wayland::{
            SurfaceRenderElement,
            blur_effect::{BlurElement, BlurState},
        },
    },
    shell::Workspace,
    utils::{geometry::SizeExt, prelude::OutputExt},
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
