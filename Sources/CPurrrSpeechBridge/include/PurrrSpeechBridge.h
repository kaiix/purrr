#ifndef PURRR_SPEECH_BRIDGE_H
#define PURRR_SPEECH_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PurrrAsrHandle PurrrAsrHandle;

typedef enum PurrrAsrEventKind {
    PURRR_ASR_EVENT_CONNECTING = 0,
    PURRR_ASR_EVENT_READY = 1,
    PURRR_ASR_EVENT_INTERIM = 2,
    PURRR_ASR_EVENT_FINAL = 3,
    PURRR_ASR_EVENT_ERROR = 4,
    PURRR_ASR_EVENT_CANCELLED = 5
} PurrrAsrEventKind;

typedef void (*PurrrAsrEventCallback)(
    void *context,
    uint64_t session_id,
    int32_t event_kind,
    const char *message
);

typedef struct PurrrAsrCallbacks {
    void *context;
    PurrrAsrEventCallback on_event;
} PurrrAsrCallbacks;

PurrrAsrHandle *purrr_asr_create(
    PurrrAsrCallbacks callbacks,
    const char *credential_path
);

void purrr_asr_destroy(PurrrAsrHandle *handle);

int32_t purrr_asr_start(PurrrAsrHandle *handle, uint64_t session_id);

int32_t purrr_asr_push_audio(
    PurrrAsrHandle *handle,
    const uint8_t *bytes,
    uint32_t length
);

int32_t purrr_asr_finish(PurrrAsrHandle *handle);

int32_t purrr_asr_cancel(PurrrAsrHandle *handle);

#ifdef __cplusplus
}
#endif

#endif
