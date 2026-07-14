use anyhow::{Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use inotify::{Inotify, WatchMask};
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

/// Minimum milliseconds between hotkey activations to prevent key-repeat spam
const DEBOUNCE_MS: u64 = 500;
/// Maximum recording duration in seconds before auto-stop
const MAX_RECORDING_SECS: u64 = 60;

const SAMPLE_RATE: u32 = 16000;
const MAX_BUFFER_SAMPLES: usize = SAMPLE_RATE as usize * MAX_RECORDING_SECS as usize;
const ICON_SIZE: i32 = 22;

fn make_circle_icon(r: u8, g: u8, b: u8) -> ksni::Icon {
    let size = ICON_SIZE as usize;
    let mut data = Vec::with_capacity(size * size * 4);
    let center = size as f32 / 2.0;
    let radius = center - 1.0;

    for y in 0..size {
        for x in 0..size {
            let dx = x as f32 - center;
            let dy = y as f32 - center;
            let dist = (dx * dx + dy * dy).sqrt();

            if dist <= radius {
                data.extend_from_slice(&[255, r, g, b]);
            } else if dist <= radius + 1.0 {
                let alpha = ((radius + 1.0 - dist) * 255.0) as u8;
                data.extend_from_slice(&[alpha, r, g, b]);
            } else {
                data.extend_from_slice(&[0, 0, 0, 0]);
            }
        }
    }

    ksni::Icon {
        width: ICON_SIZE,
        height: ICON_SIZE,
        data,
    }
}

struct DictationTray {
    recording: Arc<AtomicBool>,
    smart_punctuation: Arc<AtomicBool>,
    pause_media: Arc<AtomicBool>,
}

impl ksni::Tray for DictationTray {
    fn id(&self) -> String {
        "dictation-daemon".to_string()
    }

    fn title(&self) -> String {
        if self.recording.load(Ordering::Relaxed) {
            "Dictation (Recording...)".to_string()
        } else {
            "Dictation (Ready)".to_string()
        }
    }

    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        if self.recording.load(Ordering::Relaxed) {
            vec![make_circle_icon(220, 40, 40)]
        } else {
            vec![make_circle_icon(40, 180, 40)]
        }
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        let status = if self.recording.load(Ordering::Relaxed) {
            "Recording..."
        } else {
            "Ready (Ctrl+Shift+Space)"
        };

        let smart_punct_label = if self.smart_punctuation.load(Ordering::Relaxed) {
            "Smart Punctuation: ON"
        } else {
            "Smart Punctuation: OFF"
        };

        let pause_media_label = if self.pause_media.load(Ordering::Relaxed) {
            "Pause Media on Record: ON"
        } else {
            "Pause Media on Record: OFF"
        };

        vec![
            ksni::MenuItem::Standard(ksni::menu::StandardItem {
                label: status.to_string(),
                enabled: false,
                ..Default::default()
            }),
            ksni::MenuItem::Separator,
            ksni::MenuItem::Standard(ksni::menu::StandardItem {
                label: smart_punct_label.to_string(),
                activate: Box::new(|tray: &mut Self| {
                    let current = tray.smart_punctuation.load(Ordering::SeqCst);
                    tray.smart_punctuation.store(!current, Ordering::SeqCst);
                    let state = if !current { "ON" } else { "OFF" };
                    println!("Smart Punctuation: {state}");
                }),
                ..Default::default()
            }),
            ksni::MenuItem::Standard(ksni::menu::StandardItem {
                label: pause_media_label.to_string(),
                activate: Box::new(|tray: &mut Self| {
                    let current = tray.pause_media.load(Ordering::SeqCst);
                    tray.pause_media.store(!current, Ordering::SeqCst);
                    let state = if !current { "ON" } else { "OFF" };
                    println!("Pause Media on Record: {state}");
                }),
                ..Default::default()
            }),
            ksni::MenuItem::Separator,
            ksni::MenuItem::Standard(ksni::menu::StandardItem {
                label: "Quit".to_string(),
                activate: Box::new(|_| std::process::exit(0)),
                ..Default::default()
            }),
        ]
    }
}

fn main() -> Result<()> {
    let model_path = std::env::args().nth(1).unwrap_or_else(|| {
        let home = std::env::var("HOME").unwrap_or_default();
        format!("{home}/whisper-models/ggml-base.en.bin")
    });

    println!("Loading Whisper model from {model_path}...");
    let ctx = WhisperContext::new_with_params(&model_path, WhisperContextParameters::default())
        .context("Failed to load Whisper model")?;
    println!("Model loaded.");

    let recording = Arc::new(AtomicBool::new(false));
    let audio_buf: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(Vec::new()));
    let smart_punctuation = Arc::new(AtomicBool::new(true));
    let pause_media = Arc::new(AtomicBool::new(true));
    let shutdown = Arc::new(AtomicBool::new(false));

    // Register signal handlers: SIGTERM (systemd stop/restart) and SIGINT (Ctrl+C)
    signal_hook::flag::register(signal_hook::consts::SIGTERM, shutdown.clone())
        .context("Failed to register SIGTERM handler")?;
    signal_hook::flag::register(signal_hook::consts::SIGINT, shutdown.clone())
        .context("Failed to register SIGINT handler")?;

    // System tray icon
    let tray = DictationTray {
        recording: recording.clone(),
        smart_punctuation: smart_punctuation.clone(),
        pause_media: pause_media.clone(),
    };
    let tray_service = ksni::TrayService::new(tray);
    let tray_handle = tray_service.handle();
    tray_service.spawn();

    // Refresh tray icon on state changes
    let tray_rec = recording.clone();
    std::thread::spawn(move || {
        let mut was_recording = false;
        loop {
            std::thread::sleep(std::time::Duration::from_millis(200));
            let is_recording = tray_rec.load(Ordering::Relaxed);
            if is_recording != was_recording {
                tray_handle.update(|_tray: &mut DictationTray| {});
                was_recording = is_recording;
            }
        }
    });

    // Audio capture setup
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .context("No input device available")?;
    println!("Using input device: {}", device.name().unwrap_or_default());

    let config = cpal::StreamConfig {
        channels: 1,
        sample_rate: cpal::SampleRate(SAMPLE_RATE),
        buffer_size: cpal::BufferSize::Default,
    };

    let rec_flag = recording.clone();
    let buf_handle = audio_buf.clone();
    let stream = device.build_input_stream(
        &config,
        move |data: &[f32], _: &cpal::InputCallbackInfo| {
            if rec_flag.load(Ordering::Relaxed) {
                if let Ok(mut buf) = buf_handle.lock() {
                    if buf.len() < MAX_BUFFER_SAMPLES {
                        let remaining = MAX_BUFFER_SAMPLES - buf.len();
                        let take = data.len().min(remaining);
                        buf.extend_from_slice(&data[..take]);
                        if buf.len() >= MAX_BUFFER_SAMPLES {
                            rec_flag.store(false, Ordering::SeqCst);
                            eprintln!("Max recording duration ({MAX_RECORDING_SECS}s) reached, auto-stopping.");
                        }
                    }
                }
            }
        },
        |err| eprintln!("Audio stream error: {err}"),
        None,
    )?;
    stream.play()?;

    println!("\n=== Dictation Daemon Ready (Whisper) ===");
    println!("Hotkey: Ctrl + Shift + Space");
    println!("Press the hotkey to start/stop recording.");
    println!("Transcribed text will be typed into the focused window.");
    println!("Press Ctrl+C to quit.\n");

    // Global hotkey listener: raw evdev, one thread per keyboard-capable
    // input device, plus a watcher that picks up newly connected keyboards
    // (docking a laptop, plugging in a USB keyboard, etc.) without needing
    // a restart. This sees every keystroke at the kernel level, so it works
    // no matter which window has focus and regardless of whether that
    // window is a native Wayland client or an XWayland one -- unlike an
    // X11-based grab (rdev's only Linux backend as of the published 0.5.x
    // releases), which only ever sees XWayland-routed windows.
    //
    // Requires this account to be in the `input` group:
    //   sudo usermod -aG input $USER
    // then log out and back in (group membership is applied at login).
    // Until then, evdev::enumerate() can't open any devices and this
    // degrades to a no-op with a warning below, rather than failing loudly.
    let state = HotkeyState {
        ctrl: Arc::new(AtomicBool::new(false)),
        shift: Arc::new(AtomicBool::new(false)),
        recording: recording.clone(),
        audio_buf: audio_buf.clone(),
        ctx: Arc::new(ctx),
        last_toggle: Arc::new(AtomicU64::new(0)),
        processing: Arc::new(AtomicBool::new(false)),
        smart_punctuation: smart_punctuation.clone(),
        pause_media: pause_media.clone(),
        media_was_playing: Arc::new(AtomicBool::new(false)),
    };

    let mut keyboard_count = 0;
    for (path, device) in evdev::enumerate() {
        if !is_keyboard(&device) {
            continue;
        }
        keyboard_count += 1;
        spawn_keyboard_listener(path, device, state.clone());
    }
    spawn_hotplug_watcher(state);

    if keyboard_count == 0 {
        eprintln!(
            "WARNING: no readable keyboard devices found under /dev/input. The hotkey \
             won't work until this account is in the `input` group: run \
             `sudo usermod -aG input $USER`, then log out and back in."
        );
    } else {
        println!(
            "Listening for the hotkey on {keyboard_count} keyboard device(s), \
             and watching for newly connected ones."
        );
    }

    // Wait for shutdown signal, then clean up
    while !shutdown.load(Ordering::SeqCst) {
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    println!("\nShutting down...");
    release_keys();
    drop(stream);
    println!("Goodbye.");
    Ok(())
}

/// Shared state a keyboard listener thread needs to track modifiers and
/// trigger the same toggle_dictation() regardless of which physical device
/// the Ctrl+Shift+Space came from. Cloning is cheap: every field is an Arc.
#[derive(Clone)]
struct HotkeyState {
    ctrl: Arc<AtomicBool>,
    shift: Arc<AtomicBool>,
    recording: Arc<AtomicBool>,
    audio_buf: Arc<Mutex<Vec<f32>>>,
    ctx: Arc<WhisperContext>,
    last_toggle: Arc<AtomicU64>,
    processing: Arc<AtomicBool>,
    smart_punctuation: Arc<AtomicBool>,
    pause_media: Arc<AtomicBool>,
    media_was_playing: Arc<AtomicBool>,
}

fn is_keyboard(device: &evdev::Device) -> bool {
    device
        .supported_keys()
        .is_some_and(|keys| keys.contains(evdev::KeyCode::KEY_LEFTCTRL))
}

/// Spawns the thread that reads one device's raw key events and toggles
/// dictation on Ctrl+Shift+Space. Exits quietly if the device disappears
/// (unplugged) -- the hotplug watcher will pick up its replacement, if any.
fn spawn_keyboard_listener(path: PathBuf, mut device: evdev::Device, state: HotkeyState) {
    std::thread::spawn(move || loop {
        let events = match device.fetch_events() {
            Ok(events) => events,
            Err(e) => {
                eprintln!("evdev: lost {}: {e}", path.display());
                return;
            }
        };
        for event in events {
            let evdev::EventSummary::Key(_, key, value) = event.destructure() else {
                continue;
            };
            match key {
                evdev::KeyCode::KEY_LEFTCTRL | evdev::KeyCode::KEY_RIGHTCTRL => {
                    state.ctrl.store(value != 0, Ordering::Relaxed);
                }
                evdev::KeyCode::KEY_LEFTSHIFT | evdev::KeyCode::KEY_RIGHTSHIFT => {
                    state.shift.store(value != 0, Ordering::Relaxed);
                }
                evdev::KeyCode::KEY_SPACE if value == 1 => {
                    if !state.ctrl.load(Ordering::Relaxed) || !state.shift.load(Ordering::Relaxed) {
                        continue;
                    }
                    // Skip if currently transcribing/injecting
                    if state.processing.load(Ordering::SeqCst) {
                        continue;
                    }
                    // Debounce: ignore if too soon after last toggle
                    let now = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis() as u64;
                    let last = state.last_toggle.load(Ordering::SeqCst);
                    if now.saturating_sub(last) < DEBOUNCE_MS {
                        continue;
                    }
                    state.last_toggle.store(now, Ordering::SeqCst);
                    toggle_dictation(
                        &state.recording,
                        &state.audio_buf,
                        &state.ctx,
                        &state.processing,
                        &state.smart_punctuation,
                        &state.pause_media,
                        &state.media_was_playing,
                    );
                }
                _ => {}
            }
        }
    });
}

/// Watches /dev/input for newly created device nodes (USB keyboard plugged
/// in, laptop docked, etc.) and starts listening on any that turn out to be
/// keyboard-capable, without needing to restart the daemon. Best-effort: if
/// inotify itself can't be set up, this logs why and the daemon still runs
/// with whatever devices were present at startup.
fn spawn_hotplug_watcher(state: HotkeyState) {
    std::thread::spawn(move || {
        let mut inotify = match Inotify::init() {
            Ok(i) => i,
            Err(e) => {
                eprintln!(
                    "evdev: hotplug watcher disabled (inotify init failed: {e}); newly \
                     connected keyboards will need a daemon restart to be picked up."
                );
                return;
            }
        };
        if let Err(e) = inotify.watches().add("/dev/input", WatchMask::CREATE) {
            eprintln!(
                "evdev: hotplug watcher disabled (couldn't watch /dev/input: {e}); newly \
                 connected keyboards will need a daemon restart to be picked up."
            );
            return;
        }

        let mut buffer = [0; 1024];
        loop {
            let events = match inotify.read_events_blocking(&mut buffer) {
                Ok(events) => events,
                Err(e) => {
                    eprintln!("evdev: hotplug watcher stopped unexpectedly: {e}");
                    return;
                }
            };
            for event in events {
                let Some(name) = event.name else { continue };
                let name = name.to_string_lossy();
                if !name.starts_with("event") {
                    continue; // ignore by-id/by-path symlinks, only react to the real node
                }
                let path = PathBuf::from("/dev/input").join(name.as_ref());

                // A just-created device node can take a moment to become
                // readable while udev finishes applying permissions, so
                // retry briefly instead of giving up on the first failure.
                let mut opened = None;
                for _ in 0..10 {
                    match evdev::Device::open(&path) {
                        Ok(d) => {
                            opened = Some(d);
                            break;
                        }
                        Err(_) => std::thread::sleep(Duration::from_millis(200)),
                    }
                }
                let Some(device) = opened else { continue };
                if !is_keyboard(&device) {
                    continue;
                }

                println!("New keyboard device detected: {}", path.display());
                spawn_keyboard_listener(path, device, state.clone());
            }
        }
    });
}

fn toggle_dictation(
    recording: &AtomicBool,
    audio_buf: &Mutex<Vec<f32>>,
    ctx: &WhisperContext,
    processing: &AtomicBool,
    smart_punctuation: &AtomicBool,
    pause_media: &AtomicBool,
    media_was_playing: &AtomicBool,
) {
    let was_recording = recording.load(Ordering::SeqCst);
    if was_recording {
        recording.store(false, Ordering::SeqCst);
        processing.store(true, Ordering::SeqCst);
        println!("Recording stopped. Transcribing...");

        let should_resume = media_was_playing.load(Ordering::SeqCst);

        let samples: Vec<f32> = {
            let mut b = audio_buf.lock().unwrap();
            std::mem::take(&mut *b)
        };

        if samples.is_empty() {
            println!("No audio captured.");
            if should_resume {
                media_play();
            }
            processing.store(false, Ordering::SeqCst);
            return;
        }

        let mut state = ctx.create_state().expect("Failed to create Whisper state");
        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_n_threads(4);
        params.set_language(Some("en"));
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_suppress_nst(true);

        state
            .full(params, &samples)
            .expect("Whisper transcription failed");

        let num_segments = state.full_n_segments();
        let mut text = String::new();
        for i in 0..num_segments {
            if let Some(segment) = state.get_segment(i) {
                if let Ok(s) = segment.to_str() {
                    text.push_str(s);
                }
            }
        }
        let text = text.trim();

        if text.is_empty() {
            println!("No speech detected.");
        } else {
            let skip_punct = smart_punctuation.load(Ordering::Relaxed);
            let processed = process_text(text, skip_punct);
            println!("Transcribed: {text}");
            println!("Processed:   {processed}");
            inject_text(&processed);
        }
        if should_resume {
            media_play();
        }
        processing.store(false, Ordering::SeqCst);
    } else {
        let should_pause = pause_media.load(Ordering::Relaxed);
        let was_playing = should_pause && media_is_playing();
        media_was_playing.store(was_playing, Ordering::SeqCst);
        if was_playing {
            media_pause();
        }
        {
            let mut b = audio_buf.lock().unwrap();
            b.clear();
        }
        recording.store(true, Ordering::SeqCst);
        println!("Recording started... speak now!");
    }
}

// --- Text processing ---

/// Check if words starting at `pos` match a punctuation/coding command.
/// Returns (replacement string, number of words consumed) or None.
///
/// When `skip_punctuation` is true (Smart Punctuation ON), basic punctuation
/// commands are ignored since Whisper already inserts them automatically.
/// Coding/special commands are always active.
fn match_command(words: &[&str], pos: usize, skip_punctuation: bool) -> Option<(&'static str, usize)> {
    let w1 = words[pos].to_lowercase();

    // Try three-word matches
    if pos + 2 < words.len() {
        let w2 = words[pos + 1].to_lowercase();
        let w3 = words[pos + 2].to_lowercase();
        let triple = format!("{w1} {w2} {w3}");
        let matched = match triple.as_str() {
            "exclamation mark" | "exclamation point" if !skip_punctuation => Some("!"),
            "open curly brace" | "open curly bracket" => Some("{"),
            "close curly brace" | "close curly bracket" => Some("}"),
            "open square bracket" => Some("["),
            "close square bracket" => Some("]"),
            "double equal sign" | "double equals sign" => Some("=="),
            "not equal sign" | "not equals sign" => Some("!="),
            "fat arrow sign" => Some("=>"),
            "thin arrow sign" => Some("->"),
            _ => None,
        };
        if let Some(p) = matched {
            return Some((p, 3));
        }
    }

    // Try two-word matches
    if pos + 1 < words.len() {
        let w2 = words[pos + 1].to_lowercase();
        let pair = format!("{w1} {w2}");
        let matched = match pair.as_str() {
            // Punctuation (skipped when Smart Punctuation is ON)
            "question mark" if !skip_punctuation => Some("?"),
            "exclamation mark" | "exclamation point" if !skip_punctuation => Some("!"),
            "full stop" if !skip_punctuation => Some("."),
            "semi colon" if !skip_punctuation => Some(";"),
            "open quote" | "open quotes" if !skip_punctuation => Some("\""),
            "close quote" | "close quotes" if !skip_punctuation => Some("\""),
            "open paren" | "open parenthesis" if !skip_punctuation => Some("("),
            "close paren" | "close parenthesis" if !skip_punctuation => Some(")"),
            "at sign" if !skip_punctuation => Some("@"),
            "new line" if !skip_punctuation => Some("\n"),
            "new paragraph" if !skip_punctuation => Some("\n\n"),
            // Coding - always active
            "open brace" | "open braces" | "left brace" => Some("{"),
            "close brace" | "close braces" | "right brace" => Some("}"),
            "open bracket" | "left bracket" => Some("["),
            "close bracket" | "right bracket" => Some("]"),
            "double equals" | "double equal" => Some("=="),
            "not equals" | "not equal" => Some("!="),
            "fat arrow" => Some("=>"),
            "thin arrow" | "arrow function" => Some("->"),
            "plus equals" => Some("+="),
            "minus equals" => Some("-="),
            "pipe pipe" | "double pipe" => Some("||"),
            "and and" | "double ampersand" => Some("&&"),
            "left shift" => Some("<<"),
            "right shift" => Some(">>"),
            "scope resolution" | "double colon" => Some("::"),
            "pull request" => Some("PR"),
            _ => None,
        };
        if let Some(p) = matched {
            return Some((p, 2));
        }
    }

    // Single-word matches
    let matched = match w1.as_str() {
        // Punctuation (skipped when Smart Punctuation is ON)
        "period" if !skip_punctuation => Some("."),
        "comma" | "karma" if !skip_punctuation => Some(","),
        "colon" if !skip_punctuation => Some(":"),
        "semicolon" if !skip_punctuation => Some(";"),
        "dash" | "hyphen" if !skip_punctuation => Some("-"),
        "ellipsis" if !skip_punctuation => Some("..."),
        "apostrophe" if !skip_punctuation => Some("'"),
        "newline" if !skip_punctuation => Some("\n"),
        "bang" if !skip_punctuation => Some("!"),
        // Coding/special - always active
        "hashtag" | "hash" => Some("#"),
        "ampersand" => Some("&"),
        "slash" => Some("/"),
        "backslash" => Some("\\"),
        "underscore" => Some("_"),
        "tilde" => Some("~"),
        "backtick" => Some("`"),
        "caret" => Some("^"),
        "pipe" => Some("|"),
        "asterisk" | "star" => Some("*"),
        "percent" => Some("%"),
        "dollar" => Some("$"),
        "equals" => Some("="),
        "plus" => Some("+"),
        "minus" => Some("-"),
        "parens" => Some("()"),
        "braces" => Some("{}"),
        "brackets" => Some("[]"),
        "angles" => Some("<>"),
        _ => None,
    };
    matched.map(|p| (p, 1))
}

/// Map common dev terms to their proper casing/format.
fn fix_dev_term(word: &str) -> Option<&'static str> {
    match word.to_lowercase().as_str() {
        "api" => Some("API"),
        "apis" => Some("APIs"),
        "github" => Some("GitHub"),
        "gitlab" => Some("GitLab"),
        "bitbucket" => Some("Bitbucket"),
        "javascript" => Some("JavaScript"),
        "typescript" => Some("TypeScript"),
        "python" => Some("Python"),
        "rust" => Some("Rust"),
        "golang" | "go lang" => Some("Go"),
        "html" => Some("HTML"),
        "css" => Some("CSS"),
        "json" => Some("JSON"),
        "yaml" => Some("YAML"),
        "toml" => Some("TOML"),
        "sql" => Some("SQL"),
        "graphql" => Some("GraphQL"),
        "restful" => Some("RESTful"),
        "rest" => Some("REST"),
        "http" => Some("HTTP"),
        "https" => Some("HTTPS"),
        "url" => Some("URL"),
        "urls" => Some("URLs"),
        "uri" => Some("URI"),
        "cli" => Some("CLI"),
        "gui" => Some("GUI"),
        "ui" => Some("UI"),
        "ux" => Some("UX"),
        "ci" => Some("CI"),
        "cd" => Some("CD"),
        "pr" => Some("PR"),
        "prs" => Some("PRs"),
        "ide" => Some("IDE"),
        "sdk" => Some("SDK"),
        "npm" => Some("npm"),
        "tcp" => Some("TCP"),
        "udp" => Some("UDP"),
        "ip" => Some("IP"),
        "dns" => Some("DNS"),
        "ssh" => Some("SSH"),
        "ssl" => Some("SSL"),
        "tls" => Some("TLS"),
        "aws" => Some("AWS"),
        "gcp" => Some("GCP"),
        "oauth" => Some("OAuth"),
        "jwt" => Some("JWT"),
        "uuid" => Some("UUID"),
        "ascii" => Some("ASCII"),
        "utf" => Some("UTF"),
        "regex" => Some("regex"),
        "stdin" => Some("stdin"),
        "stdout" => Some("stdout"),
        "stderr" => Some("stderr"),
        "nginx" => Some("nginx"),
        "redis" => Some("Redis"),
        "postgres" | "postgresql" => Some("PostgreSQL"),
        "mysql" => Some("MySQL"),
        "mongodb" => Some("MongoDB"),
        "docker" => Some("Docker"),
        "kubernetes" => Some("Kubernetes"),
        "linux" => Some("Linux"),
        "macos" => Some("macOS"),
        "ios" => Some("iOS"),
        "android" => Some("Android"),
        "wasm" => Some("WASM"),
        "webassembly" => Some("WebAssembly"),
        "localhost" => Some("localhost"),
        "kubectl" => Some("kubectl"),
        "keycloak" => Some("Keycloak"),
        "saltpig" => Some("Saltpig"),
        "mcp" => Some("MCP"),
        "zephly" | "zephli" => Some("Zephly"),
        "maine" => Some("main"),
        _ => None,
    }
}

fn process_text(text: &str, skip_punctuation: bool) -> String {
    let words: Vec<&str> = text.split_whitespace().collect();
    let mut result = String::new();
    let mut capitalize_next = !skip_punctuation;
    let mut i = 0;

    while i < words.len() {
        if let Some((replacement, consumed)) = match_command(&words, i, skip_punctuation) {
            result.push_str(replacement);
            if matches!(replacement, "." | "?" | "!" | "..." | "\n" | "\n\n") {
                capitalize_next = true;
            }
            i += consumed;
        } else {
            // Regular word - check for dev term first
            let word = if let Some(term) = fix_dev_term(words[i]) {
                term
            } else {
                words[i]
            };

            if !result.is_empty()
                && !result.ends_with('\n')
                && !result.ends_with('(')
                && !result.ends_with('"')
                && !result.ends_with('{')
                && !result.ends_with('[')
            {
                result.push(' ');
            }

            if capitalize_next && fix_dev_term(words[i]).is_none() {
                let mut chars = word.chars();
                if let Some(first) = chars.next() {
                    result.extend(first.to_uppercase());
                    result.push_str(chars.as_str());
                }
                capitalize_next = false;
            } else {
                result.push_str(word);
                capitalize_next = false;
            }
            i += 1;
        }
    }

    result
}

/// Check if any MPRIS media player is currently playing.
fn media_is_playing() -> bool {
    Command::new("playerctl")
        .args(["status"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "Playing")
        .unwrap_or(false)
}

/// Pause all playing MPRIS media players. Uses playerctl, falls back to dbus-send.
fn media_pause() {
    match Command::new("playerctl").args(["--all-players", "pause"]).status() {
        Ok(status) if status.success() => {
            println!("Media paused via playerctl.");
        }
        _ => {
            // Fallback: pause via dbus-send to the MPRIS interface
            let _ = Command::new("dbus-send")
                .args([
                    "--type=method_call",
                    "--dest=org.mpris.MediaPlayer2.playerctld",
                    "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2.Player.Pause",
                ])
                .status();
        }
    }
}

/// Resume playback on MPRIS media players. Uses playerctl, falls back to dbus-send.
fn media_play() {
    match Command::new("playerctl").args(["play"]).status() {
        Ok(status) if status.success() => {
            println!("Media resumed via playerctl.");
        }
        _ => {
            let _ = Command::new("dbus-send")
                .args([
                    "--type=method_call",
                    "--dest=org.mpris.MediaPlayer2.playerctld",
                    "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2.Player.Play",
                ])
                .status();
        }
    }
}

fn release_keys() {
    // Release Space (57), Left Ctrl (29), Right Ctrl (97), Left Shift (42), Right Shift (54)
    let _ = Command::new("ydotool")
        .args(["key", "57:0", "29:0", "97:0", "42:0", "54:0"])
        .status();
}

fn inject_text(text: &str) {
    match Command::new("ydotool")
        .args(["type", "--", text])
        .status()
    {
        Ok(status) if status.success() => {
            println!("Text injected via ydotool.");
        }
        _ => {
            match Command::new("wtype").arg(text).status() {
                Ok(status) if status.success() => {
                    println!("Text injected via wtype.");
                }
                _ => {
                    eprintln!("Failed to inject text. Install ydotool or wtype.");
                }
            }
        }
    }
}
