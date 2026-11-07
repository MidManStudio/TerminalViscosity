// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_ffi.md, section "tv.h"
// ============================================================================

#ifndef TV_H
#define TV_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TV_ABI_VERSION 4u

#define TV_OK 0
#define TV_ERR_NULL -1
#define TV_ERR_DECODE -2
#define TV_ERR_CAPACITY -3
#define TV_ERR_ARG -4
#define TV_ERR_PANIC -99

#define TV_CHAMBER_SIZE 4u
#define TV_BALLOON_VIEW_SIZE 28u
#define TV_PLAYER_VIEW_SIZE 20u
#define TV_BUTTON_JUMP 1u
#define TV_DETONATE_VIEW_SIZE 24u

typedef struct TvWorld TvWorld;

typedef struct TvChamber {
    uint16_t compound;
    uint16_t volume_ml;
} TvChamber;

/* flags is the loadout slot the balloon was thrown from. */
typedef struct TvBalloonView {
    uint16_t id;
    uint8_t owner;
    uint8_t flags;
    uint16_t compound;
    uint16_t reserved;
    int32_t pos_mm[3];
    int16_t vel_cms[3];
    int16_t reserved2;
} TvBalloonView;

/* yaw_mrad is the heading in thousandths of a radian from 0 up to a full turn; 0 faces -z.
   hp is the hit points left, from tv_max_health() down to 0, which is knocked out. */
typedef struct TvPlayerView {
    uint8_t id;
    uint8_t hp;
    uint16_t reserved;
    int32_t pos_mm[3];
    int32_t yaw_mrad;
} TvPlayerView;

typedef struct TvDetonateView {
    uint16_t balloon;
    uint16_t compound;
    uint8_t volatility_q;
    uint8_t reserved[3];
    int32_t pos_mm[3];
    uint32_t radius_mm;
} TvDetonateView;

uint32_t tv_abi_version(void);
uint32_t tv_sizeof_chamber(void);
uint32_t tv_sizeof_balloon_view(void);
uint32_t tv_sizeof_detonate_view(void);
uint32_t tv_sizeof_player_view(void);
uint32_t tv_arena_radius_mm(void);
uint32_t tv_max_health(void);

TvWorld *tv_world_new(uint64_t seed);
void tv_world_free(TvWorld *w);

int32_t tv_encode_throw(const TvChamber *chambers, uint32_t n, uint8_t slot, int16_t dx,
                        int16_t dy, int16_t dz, uint8_t power, uint8_t *out, uint32_t cap);
int32_t tv_encode_input(int8_t forward, int8_t strafe, int32_t yaw_mrad, uint8_t buttons,
                        uint8_t *out, uint32_t cap);
int32_t tv_world_join(TvWorld *w, uint8_t player);
int32_t tv_world_submit(TvWorld *w, uint8_t player, const uint8_t *bytes, uint32_t len);
int32_t tv_world_step(TvWorld *w);
int32_t tv_world_snapshot(const TvWorld *w, uint8_t *out, uint32_t cap);
int32_t tv_world_take_events(TvWorld *w, uint8_t *out, uint32_t cap);
uint64_t tv_world_state_hash(const TvWorld *w);

int32_t tv_snapshot_decode(const uint8_t *buf, uint32_t len, TvBalloonView *out,
                           uint32_t out_cap, uint32_t *out_tick);
int32_t tv_snapshot_decode_players(const uint8_t *buf, uint32_t len, TvPlayerView *out,
                                   uint32_t out_cap);
int32_t tv_events_decode(const uint8_t *buf, uint32_t len, TvDetonateView *out,
                         uint32_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* TV_H */
