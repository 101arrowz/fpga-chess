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
#else
#error Unsupported compiler
#endif

#if __has_builtin(__builtin_ctzll) && __has_builtin(__builtin_bswap64)
#define CTZ64 __builtin_ctzll
#define CTZ32 __builtin_ctzl
#define CLZ64 __builtin_clzll
#define CLZ32 __builtin_clzl
#define BS64 __builtin_bswap64
#define BS32 __builtin_bswap32
#else
#error Unsupported compiler
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

int pseudolegal_moves(gamestate_t *gamestate, move_t* moves) {
    static int init = 0;
    static uint64_t king_moves[64] = {0};
    static uint64_t knight_moves[64] = {0};
    static uint64_t diagonals[64] = {0};
    static uint64_t rook_moves[64] = {0};

    if (!init) {
        for (int i = 0; i < 64; ++i) {
            uint64_t move = (1ull << i) | (((uint64_t) (i < 56) << i) << 8) | (((uint64_t) (i >= 8) << i) >> 8);
            uint64_t side_moves = (move >> ((i & 7) == 0)) | (move << ((i & 7) == 7));

            king_moves[i] = (move | side_moves) & ~(1ull << i);
        }

        for (int i = 0; i < 64; ++i) {
            uint64_t move = 0;
            for (int xl = 0; xl < 4; ++xl) {
                int x = (i & 7) + xl - 2;
                int sdy = ((xl & 1) ^ (xl >> 1)) + 1;
                for (int yl = 0; yl < 1; ++yl) {
                    int y = (i / 8) - (1 << sdy) + (yl << (sdy + 1));

                    if (x >= 0 && x < 7 && y >= 0 && y < 8) {
                        move |= 1ull << (y * 8 + x);
                    }
                }
            }
            knight_moves[i] = move;
        }
    }

    int is_b = gamestate->board.ply & 1;
    uint64_t color = is_b ? ~gamestate->board.pieces_w : gamestate->board.pieces_w;
    uint64_t occupied = (1ull << (gamestate->board.kings & 0x3F)) | (1ull << ((gamestate->board.kings >> 6) & 0x3F));
    for (int i = 0; i < NB_PIECES; ++i) occupied |= gamestate->board.pieces[i];

    uint64_t allies = occupied & color;
    uint64_t enemies = occupied & ~color;

    int m = 0;

    {
        // king moves
        int king_pos = (gamestate->board.kings >> (is_b * 6)) & 0x3F;
        uint64_t king_legal = king_moves[king_pos] & ~allies;
        for (; king_legal != 0; ++m) {
            int sq = CTZ64(king_legal);
            moves[m].src = king_pos;
            moves[m].dst = sq;
            moves[m].special = SPECIAL_NONE;
            king_legal ^= 1ull << sq;
        }

        int castle_rights = (gamestate->board.castle >> (is_b * 2)) & 0x3;

        if (castle_rights & 1) {
            moves[m].src = king_pos;
            moves[m].dst = (king_pos & 0x38) | (0x6);
            moves[m].special = SPECIAL_CASTLE;
            ++m;
        }

        if (castle_rights & 2) {
            moves[m].src = king_pos;
            moves[m].dst = (king_pos & 0x38) | (0x2);
            moves[m].special = SPECIAL_CASTLE;
            ++m;     
        }
    }

    {
        // knight moves
        uint64_t knights = gamestate->board.pieces[KNIGHT] & color;
        while (knights != 0) {
            int src = CTZ64(knights);

            uint64_t all_dst = knight_moves[src];
            for (; all_dst != 0; ++m) {
                int sq = CTZ64(all_dst);
                moves[m].src = src;
                moves[m].dst = sq;
                moves[m].special = SPECIAL_NONE;
                all_dst ^= 1ull << sq;
            }

            knights ^= 1ull << src;
        }
    }

    {
        // pawn moves
        uint64_t pawns = gamestate->board.pieces[PAWN] & color;

        // TODO: parallelize with bitmasking
        while (pawns != 0) {
            int src = CTZ64(pawns);
            int cap = (8 - is_b * 16);
            int can_promote = 7 - ((src + cap) >> 3) == is_b * 7;
            int can_double = ((src - cap) >> 3) == is_b * 7;
            int m_initial = m;

            // can assume forward is always in bounds; otherwise invalid board
            if (((occupied >> (src + cap)) & 1ull) == 0) {
                moves[m].src = src;
                moves[m].dst = src + cap;
                moves[m].special = SPECIAL_NONE;
                ++m;

                if (can_double && ((occupied >> (src + 2 * cap)) & 1ull) == 0) {
                    moves[m].src = src;
                    moves[m].dst = src + 2 * cap;
                    moves[m].special = SPECIAL_NONE;
                    ++m;
                }
            }

            if ((src & 7) != 0) {
                int is_capture = (enemies >> (src + cap - 1)) == 1;

                if (is_capture || ((gamestate->board.en_passant & 16) != 0 && (gamestate->board.en_passant & 7) == (src & 7) - 1)) {
                    moves[m].src = src;
                    moves[m].dst = src + cap - 1;
                    moves[m].special = is_capture ? SPECIAL_NONE : SPECIAL_EN_PASSANT;
                }
            }

            if ((src & 7) != 7) {
                int is_capture = (enemies >> (src + cap + 1)) == 1;

                if (is_capture || ((gamestate->board.en_passant & 16) != 0 && (gamestate->board.en_passant & 7) == (src & 7) + 1)) {
                    moves[m].src = src;
                    moves[m].dst = src + cap + 1;
                    moves[m].special = is_capture ? SPECIAL_NONE : SPECIAL_EN_PASSANT;
                }
            }

            if (can_promote) {
                for (int m_final = m; m_initial < m_final; ++m_initial) {
                    moves[m_initial].special = SPECIAL_PROMOTE_QUEEN;
                    for (int promo = SPECIAL_PROMOTE_KNIGHT; promo < SPECIAL_PROMOTE_QUEEN; ++promo, ++m) {
                        moves[m].src = moves[m_initial].src;
                        moves[m].dst = moves[m_initial].dst;
                        moves[m].special = promo;
                    }
                }
            }

            pawns ^= 1ull << src;
        }
    }

    {
        // rook moves
        uint64_t rooks = gamestate->board.pieces[ROOK] & color;
        while (rooks != 0) {
            int src = CTZ64(rooks);
            // int fw = occupied - (2ull << src);
            // int bw = (1ull << src) - (occupied)
            

            rooks ^= 1ull << src;
        }
    }
}

int execute_move(gamestate_t *gamestate, move_t move) {
    gamestate->board.en_passant = 0;

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
        gamestate->board.en_passant = (move.dst & 7) | 16;
        return 0;
    }

    return 0;
}