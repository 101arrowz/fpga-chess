#include <stdlib.h>
#include "board.h"
#include "engine.h"

#ifndef __has_builtin
#define __has_builtin(x) (0)
#endif

#if __has_builtin(__builtin_rotateleft64)
#define ROTL64 __builtin_rotateleft64
#define ROTR64 __builtin_rotateright64
#elif __has_builtin(__builtin_stdc_rotate_left)
#define ROTL64 __builtin_stdc_rotate_left
#define ROTR64 __builtin_stdc_rotate_right
#endif

int search_moves(const gamestate_t *gamestate, best_moves_t *best_moves) {
    // stub
    return -1;
}

inline void update_white(gamestate_t *gamestate, uint64_t move_mask) {
    gamestate->board.pieces_w = (gamestate->board.ply & 1) ? (gamestate->board.pieces_w & ~move_mask) : (gamestate->board.pieces_w | move_mask);
}

inline bool do_capture(gamestate_t *gamestate, uint8_t dst) {
    int did_capture = 0;

    for (int i = 0; i < NB_PIECES; ++i) {
        did_capture |= (gamestate->board.pieces[i] >> dst) & 1;
        gamestate->board.pieces[i] &= ~(1ull << dst);
    }

    for (int i = 0; i < 2; ++i) {
        int update = dst == ((gamestate->board.kings >> (i * 6)) & 0x3F);
        did_capture |= update;
        gamestate->board.checkmate |= update << i;
    }

    return (bool) did_capture;
}

int execute_move(gamestate_t *gamestate, move_t move) {
    for (int i = 0; i < 2; ++i) {
        if (move.src == ((gamestate->board.kings >> (i * 6)) & 0x3F)) {
            gamestate->board.kings = (gamestate->board.kings & ~(0x3F << (i * 6))) | (move.dst << (i * 6));
            update_white(gamestate, 1ull << move.dst);
            do_capture(gamestate, move.dst);
            int dy = (int) (move.dst >> 3) - (int) (move.src >> 3);
            int dx = (int) (move.dst & 7) - (int) (move.src & 7);

            if (gamestate->engine_debug) {
                // TODO: verify move legality
            }

            if (move.special == SPECIAL_CASTLE || (move.special == SPECIAL_UNKNOWN && (dx > 1 || dx < -1))) {
                uint8_t rook_src = (move.src & 56) | (move.dst < move.src ? 0 : 7);
                uint8_t rook_dst = (move.src & 56) | (move.dst < move.src ? 3 : 5);
                gamestate->board.pieces[ROOK] = (gamestate->board.pieces[ROOK] & ~(1ull << rook_src)) | (1ull << rook_dst);
                update_white(gamestate, 1ull << rook_dst);
            }

            return 0;
        }
    }

    int piece_type = -1;
    for (int i = 0; i < NB_PIECES; ++i) {
        if (gamestate->board.pieces[i] & (1ull << move.src)) piece_type = i;
    }
    // piece_type should only be updated once; todo verify

    if (piece_type < 0) return -1;

    if (gamestate->engine_debug) {
        // TODO: verify move legality
    }

    update_white(gamestate, 1ull << move.dst);
    bool did_capture = do_capture(gamestate, move.dst);
    if (move.special & SPECIAL_PROMOTE) {
        // requires piece_type == PAWN; todo verify
        gamestate->board.pieces[piece_type] &= ~(1ull < move.src);
        gamestate->board.pieces[move.special & ~SPECIAL_PROMOTE] |= (1ull << move.dst);
        return 0;
    }


    gamestate->board.pieces[piece_type] = (gamestate->board.pieces[piece_type] & ~(1ull << move.src)) | (1ull << move.dst);
    if (move.special == SPECIAL_EN_PASSANT || (move.special == SPECIAL_UNKNOWN && piece_type == PAWN && (move.dst & 7) != (move.src & 7) && !did_capture)) {
        // should always return true; todo verify
        do_capture(gamestate, (gamestate->board.ply & 1) ? ((move.dst + 8) & 63) : ((move.dst - 8) & 63));
        return 0;
    }

    return 0;
}