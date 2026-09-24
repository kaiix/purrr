use koe_asr::{AsrConfig, AsrEvent, AsrProvider, DoubaoImeProvider, TranscriptAggregator};
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::PathBuf;
use std::ptr;
use std::sync::Mutex;
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;
use tokio::time::timeout;

const EVENT_CONNECTING: i32 = 0;
const EVENT_READY: i32 = 1;
const EVENT_INTERIM: i32 = 2;
const EVENT_FINAL: i32 = 3;
const EVENT_ERROR: i32 = 4;
const EVENT_CANCELLED: i32 = 5;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PurrrAsrCallbacks {
    context: *mut c_void,
    on_event: Option<extern "C" fn(*mut c_void, u64, i32, *const c_char)>,
}

#[derive(Clone, Copy)]
struct CallbackState {
    context: usize,
    on_event: Option<extern "C" fn(*mut c_void, u64, i32, *const c_char)>,
}

impl CallbackState {
    fn emit(&self, session_id: u64, kind: i32, message: &str) {
        let Some(callback) = self.on_event else {
            return;
        };
        let sanitized = message.replace('\0', "");
        let value = CString::new(sanitized).unwrap_or_default();
        callback(
            self.context as *mut c_void,
            session_id,
            kind,
            value.as_ptr(),
        );
    }
}

enum Command {
    Audio(Vec<u8>),
    Finish,
    Cancel,
}

struct ActiveSession {
    sender: mpsc::UnboundedSender<Command>,
}

pub struct PurrrAsrHandle {
    runtime: Runtime,
    callbacks: CallbackState,
    credential_path: PathBuf,
    active: Mutex<Option<ActiveSession>>,
}

fn config(credential_path: &std::path::Path) -> AsrConfig {
    let mut custom_headers = HashMap::new();
    custom_headers.insert(
        "credential_path".to_string(),
        credential_path.to_string_lossy().to_string(),
    );

    AsrConfig {
        url: String::new(),
        app_key: String::new(),
        access_key: String::new(),
        api_key: String::new(),
        resource_id: String::new(),
        sample_rate_hz: 16_000,
        connect_timeout_ms: 5_000,
        final_wait_timeout_ms: 8_000,
        enable_ddc: false,
        enable_itn: false,
        enable_punc: true,
        enable_nonstream: false,
        hotwords: Vec::new(),
        language: None,
        custom_headers,
        end_window_size: None,
        force_to_speech_time: None,
        vad_segment_duration: None,
        output_zh_variant: None,
        enable_accelerate_text: false,
        accelerate_score: None,
        context_messages: Vec::new(),
    }
}

async fn run_session(
    callbacks: CallbackState,
    credential_path: PathBuf,
    session_id: u64,
    mut receiver: mpsc::UnboundedReceiver<Command>,
) {
    callbacks.emit(session_id, EVENT_CONNECTING, "");

    let mut provider = DoubaoImeProvider::new();
    if let Err(error) = provider.connect(&config(&credential_path)).await {
        callbacks.emit(session_id, EVENT_ERROR, &error.to_string());
        return;
    }
    callbacks.emit(session_id, EVENT_READY, "");

    let mut aggregator = TranscriptAggregator::new();
    let mut finish_requested = false;

    while !finish_requested {
        tokio::select! {
            command = receiver.recv() => {
                match command {
                    Some(Command::Audio(bytes)) => {
                        if let Err(error) = provider.send_audio(&bytes).await {
                            callbacks.emit(session_id, EVENT_ERROR, &error.to_string());
                            let _ = provider.close().await;
                            return;
                        }
                    }
                    Some(Command::Finish) | None => {
                        if let Err(error) = provider.finish_input().await {
                            callbacks.emit(session_id, EVENT_ERROR, &error.to_string());
                            let _ = provider.close().await;
                            return;
                        }
                        finish_requested = true;
                    }
                    Some(Command::Cancel) => {
                        let _ = provider.close().await;
                        callbacks.emit(session_id, EVENT_CANCELLED, "");
                        return;
                    }
                }
            }
            event = provider.next_event() => {
                if handle_event(&callbacks, session_id, event, &mut aggregator) {
                    let _ = provider.close().await;
                    return;
                }
            }
        }
    }

    let final_result = timeout(Duration::from_secs(8), async {
        loop {
            match receiver.try_recv() {
                Ok(Command::Cancel) => return Err(FinalizeError::Cancelled),
                Ok(Command::Audio(_))
                | Ok(Command::Finish)
                | Err(mpsc::error::TryRecvError::Empty) => {}
                Err(mpsc::error::TryRecvError::Disconnected) => {}
            }

            match provider.next_event().await {
                Ok(AsrEvent::Interim(text)) => {
                    aggregator.update_interim(&text);
                }
                Ok(AsrEvent::Definite(text)) => {
                    aggregator.update_definite(&text);
                }
                Ok(AsrEvent::Final(text)) => {
                    aggregator.update_final(&text);
                    return Ok(aggregator.best_text());
                }
                Ok(AsrEvent::Error(message)) => return Err(FinalizeError::Failed(message)),
                Ok(AsrEvent::Closed(_)) => return Ok(aggregator.best_text()),
                Ok(AsrEvent::Connected) => {}
                Err(error) => return Err(FinalizeError::Failed(error.to_string())),
            }
        }
    })
    .await;

    let _ = provider.close().await;

    match final_result {
        Ok(Ok(text)) if !text.trim().is_empty() => {
            callbacks.emit(session_id, EVENT_FINAL, text.trim());
        }
        Ok(Ok(_)) => callbacks.emit(session_id, EVENT_FINAL, ""),
        Ok(Err(FinalizeError::Cancelled)) => {
            callbacks.emit(session_id, EVENT_CANCELLED, "");
        }
        Ok(Err(FinalizeError::Failed(message))) => {
            callbacks.emit(session_id, EVENT_ERROR, &message);
        }
        Err(_) => {
            let best = aggregator.best_text();
            if best.trim().is_empty() {
                callbacks.emit(session_id, EVENT_ERROR, "ASR final result timed out");
            } else {
                callbacks.emit(session_id, EVENT_FINAL, best.trim());
            }
        }
    }
}

enum FinalizeError {
    Cancelled,
    Failed(String),
}

fn handle_event(
    callbacks: &CallbackState,
    session_id: u64,
    event: koe_asr::error::Result<AsrEvent>,
    aggregator: &mut TranscriptAggregator,
) -> bool {
    match event {
        Ok(AsrEvent::Interim(text)) => {
            aggregator.update_interim(&text);
            callbacks.emit(session_id, EVENT_INTERIM, &aggregator.live_preview());
            false
        }
        Ok(AsrEvent::Definite(text)) => {
            aggregator.update_definite(&text);
            callbacks.emit(session_id, EVENT_INTERIM, &aggregator.live_preview());
            false
        }
        Ok(AsrEvent::Final(text)) => {
            aggregator.update_final(&text);
            false
        }
        Ok(AsrEvent::Error(message)) => {
            callbacks.emit(session_id, EVENT_ERROR, &message);
            true
        }
        Ok(AsrEvent::Closed(reason)) => {
            callbacks.emit(
                session_id,
                EVENT_ERROR,
                reason
                    .as_deref()
                    .unwrap_or("ASR connection closed unexpectedly"),
            );
            true
        }
        Ok(AsrEvent::Connected) => false,
        Err(error) => {
            callbacks.emit(session_id, EVENT_ERROR, &error.to_string());
            true
        }
    }
}

#[no_mangle]
/// Creates an ASR bridge handle.
///
/// # Safety
///
/// `credential_path` must point to a valid, NUL-terminated UTF-8 string for the
/// duration of this call. The callback context must remain valid until the
/// returned handle is destroyed and no callback can still be in flight.
pub unsafe extern "C" fn purrr_asr_create(
    callbacks: PurrrAsrCallbacks,
    credential_path: *const c_char,
) -> *mut PurrrAsrHandle {
    if credential_path.is_null() {
        return ptr::null_mut();
    }

    let path = match CStr::from_ptr(credential_path).to_str() {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => return ptr::null_mut(),
    };
    let runtime = match Runtime::new() {
        Ok(value) => value,
        Err(_) => return ptr::null_mut(),
    };

    Box::into_raw(Box::new(PurrrAsrHandle {
        runtime,
        callbacks: CallbackState {
            context: callbacks.context as usize,
            on_event: callbacks.on_event,
        },
        credential_path: path,
        active: Mutex::new(None),
    }))
}

#[no_mangle]
/// Destroys a handle previously returned by [`purrr_asr_create`].
///
/// # Safety
///
/// `handle` must be null or a live pointer returned by `purrr_asr_create`, and
/// it must be passed to this function at most once.
pub unsafe extern "C" fn purrr_asr_destroy(handle: *mut PurrrAsrHandle) {
    if handle.is_null() {
        return;
    }
    let boxed = Box::from_raw(handle);
    if let Ok(mut active) = boxed.active.lock() {
        if let Some(session) = active.take() {
            let _ = session.sender.send(Command::Cancel);
        }
    }
    drop(boxed);
}

#[no_mangle]
/// Starts a new recognition session, cancelling any prior active session.
///
/// # Safety
///
/// `handle` must point to a live handle returned by `purrr_asr_create`.
pub unsafe extern "C" fn purrr_asr_start(handle: *mut PurrrAsrHandle, session_id: u64) -> i32 {
    let Some(handle) = handle.as_ref() else {
        return -1;
    };

    let (sender, receiver) = mpsc::unbounded_channel();
    let mut active = match handle.active.lock() {
        Ok(value) => value,
        Err(_) => return -2,
    };
    if let Some(previous) = active.replace(ActiveSession {
        sender: sender.clone(),
    }) {
        let _ = previous.sender.send(Command::Cancel);
    }

    let callbacks = handle.callbacks;
    let credential_path = handle.credential_path.clone();
    handle.runtime.spawn(run_session(
        callbacks,
        credential_path,
        session_id,
        receiver,
    ));
    0
}

#[no_mangle]
/// Copies a chunk of 16 kHz mono, signed 16-bit PCM into the active session.
///
/// # Safety
///
/// `handle` must point to a live handle returned by `purrr_asr_create`.
/// `bytes` must reference at least `length` readable bytes for this call.
pub unsafe extern "C" fn purrr_asr_push_audio(
    handle: *mut PurrrAsrHandle,
    bytes: *const u8,
    length: u32,
) -> i32 {
    let Some(handle) = handle.as_ref() else {
        return -1;
    };
    if bytes.is_null() || length == 0 {
        return -2;
    }
    let data = std::slice::from_raw_parts(bytes, length as usize).to_vec();
    send_command(handle, Command::Audio(data))
}

#[no_mangle]
/// Signals end-of-input for the active recognition session.
///
/// # Safety
///
/// `handle` must point to a live handle returned by `purrr_asr_create`.
pub unsafe extern "C" fn purrr_asr_finish(handle: *mut PurrrAsrHandle) -> i32 {
    let Some(handle) = handle.as_ref() else {
        return -1;
    };
    send_command(handle, Command::Finish)
}

#[no_mangle]
/// Cancels the active recognition session.
///
/// # Safety
///
/// `handle` must point to a live handle returned by `purrr_asr_create`.
pub unsafe extern "C" fn purrr_asr_cancel(handle: *mut PurrrAsrHandle) -> i32 {
    let Some(handle) = handle.as_ref() else {
        return -1;
    };
    send_command(handle, Command::Cancel)
}

fn send_command(handle: &PurrrAsrHandle, command: Command) -> i32 {
    let active = match handle.active.lock() {
        Ok(value) => value,
        Err(_) => return -2,
    };
    let Some(session) = active.as_ref() else {
        return -3;
    };
    match session.sender.send(command) {
        Ok(()) => 0,
        Err(_) => -4,
    }
}
