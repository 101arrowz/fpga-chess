#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include "board.h"
#include "engine.h"

#ifndef __has_builtin
#define __has_builtin(x) (0)
#endif

#if __has_builtin(__builtin_ctzll) && __has_builtin(__builtin_bswap64) && __has_builtin(__builtin_popcountll)
#define CTZ64 __builtin_ctzll
#define CTZ32 __builtin_ctzl
#define CLZ64 __builtin_clzll
#define CLZ32 __builtin_clzl
#define BS64 __builtin_bswap64
#define BS32 __builtin_bswap32
#define POPCNT32 __builtin_popcountl
#define POPCNT64 __builtin_popcountll
#else
#error Unsupported compiler
#endif

void update_white(gamestate_t *gamestate, uint64_t move_mask) {
    gamestate->board.pieces_w = (gamestate->board.ply & 1) ? (gamestate->board.pieces_w & ~move_mask) : (gamestate->board.pieces_w | move_mask);
}

bool do_capture(gamestate_t *gamestate, uint8_t dst) {
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

static int init = 0;
static uint64_t king_moves[64] = {0};
static uint64_t knight_moves[64] = {0};
static uint8_t occupancy_bounds[64][8] = {0};
static uint64_t diags[15] = {0};
static uint64_t antidiags[15] = {0};

void static_init() {
    if (!init) {
        for (int i = 0; i < 64; ++i) {
            uint64_t move = (1ull << i) | (((uint64_t) (i < 56) << i) << 8) | (((uint64_t) (i >= 8) << i) >> 8);
            uint64_t side_moves = (move >> ((i & 7) == 0)) | (move << ((i & 7) == 7));

            king_moves[i] = (move | side_moves) & ~(1ull << i);
        }

        for (int i = 0; i < 64; ++i) {
            uint64_t move = 0;
            for (int xl = 0; xl < 4; ++xl) {
                int x = (i & 7) - 2 + xl + (xl >> 1);
                int sdy = (xl & 1) ^ (xl >> 1);
                for (int yl = 0; yl < 2; ++yl) {
                    int y = (i / 8) - (1 << sdy) + (yl << (sdy + 1));
                    if (x >= 0 && x < 8 && y >= 0 && y < 8) {
                        move |= 1ull << (y * 8 + x);
                    }
                }
            }
            knight_moves[i] = move;
        }

        for (int occ = 0; occ < 64; ++occ) {
            for (int f = 0; f < 8; ++f) {
                int mask_lo = (1 << f) - 1;
                int mask_hi = -(2 << f);

                int lo = 31 - __builtin_clz(((occ << 1) & mask_lo) | 1);
                int hi = __builtin_ctz(((occ << 1) & mask_hi) | 128);

                occupancy_bounds[occ][f] = (hi << 3) | lo;
            }
        }

        for (int diag = 0; diag < 15; ++diag) {
            for (int rank = 0; rank < 8; ++rank) {
                int file = diag - rank;
                diags[diag] |= 0 <= file && file < 8 ? (1ull << (rank * 8 + file)) : 0;
                antidiags[diag] |= 0 <= file && file < 8 ? (1ull << (rank * 8 + 7 - file)) : 0;
            }
        }

        init = 1;
    }
}

uint64_t rook_attacks(uint64_t occ, int src) {
    uint64_t rank_atk = ((uint64_t) occupancy_bounds[((occ >> (src & 0x38)) >> 1) & 0x3F][src & 0x07]) << (src & 0x38);

    uint64_t other_occ = occ & ~(1ull << src);
    uint64_t file_mask = 0x0101010101010101ull << (src & 0x07);
    uint64_t up_atk = (other_occ & file_mask) - (1ull << src);
    // uint64_t down_atk = BS64(occ & file_mask) - ((0x1000000000000000ull >> (src & 0x38)) << 1);
    uint64_t down_atk = BS64(other_occ & file_mask) - BS64(1ull << src);

    return ((up_atk ^ down_atk) & file_mask) | rank_atk;
}

uint64_t bishop_attacks(uint64_t occ, int src) {
    uint64_t other_occ = occ & ~(1ull << src);
    int diag = (src >> 3) + (src & 0x07);

    uint64_t diag_mask = diags[diag];
    uint64_t antidiag_mask = antidiags[diag];

    uint64_t nw_atk = (other_occ & diag_mask) - (1ull << src);
    uint64_t se_atk = BS64(other_occ & diag_mask) - BS64(1ull << src);

    uint64_t ne_atk = (other_occ & antidiag_mask) - (1ull << src);
    uint64_t sw_atk = BS64(other_occ & antidiag_mask) - BS64(1ull << src);

    return ((nw_atk ^ se_atk) & diag_mask) | ((ne_atk ^ sw_atk) & antidiag_mask);
}

uint64_t occupancy(const board_t *board) {
    uint64_t occupied = (1ull << (board->kings & 0x3F)) | (1ull << ((board->kings >> 6) & 0x3F));
    for (int i = 0; i < NB_PIECES; ++i) occupied |= board->pieces[i];

    return occupied;
}

int pseudolegal_moves(const gamestate_t *gamestate, move_t* moves) {
    static_init();
    int is_b = gamestate->board.ply & 1;
    uint64_t color = is_b ? ~gamestate->board.pieces_w : gamestate->board.pieces_w;

    uint64_t occupied = occupancy(&gamestate->board);
    uint64_t allies = occupied & color;
    uint64_t enemies = occupied & ~color;

    int m = 0;

    {
        // king moves
        int king_pos = (gamestate->board.kings >> (is_b * 6)) & 0x3F;
        uint64_t king_legal = king_moves[king_pos] & ~allies;
        while (king_legal != 0) {
            int sq = CTZ64(king_legal);

            moves[m].src = king_pos;
            moves[m].dst = sq;
            moves[m].special = SPECIAL_NONE;
            ++m;

            king_legal ^= 1ull << sq;
        }

        int castle_rights = (gamestate->board.castle >> (is_b * 2)) & 0x3;

        if ((castle_rights & 1) && ((occupied >> (is_b * 7)) & 0x60) == 0) {
            moves[m].src = king_pos;
            moves[m].dst = (king_pos & 0x38) | (0x6);
            moves[m].special = SPECIAL_CASTLE;
            ++m;
        }

        if ((castle_rights & 2) && ((occupied >> (is_b * 7)) & 0x0D) == 0) {
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

            uint64_t all_dst = knight_moves[src] & ~allies;
            while (all_dst != 0) {
                int sq = CTZ64(all_dst);

                moves[m].src = src;
                moves[m].dst = sq;
                moves[m].special = SPECIAL_NONE;
                ++m;

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
        // rook + queen moves
        uint64_t rooks = (gamestate->board.pieces[ROOK] | gamestate->board.pieces[QUEEN]) & color;
        while (rooks != 0) {
            int src = CTZ64(rooks);
            uint64_t atk = rook_attacks(occupied, src) & ~allies;

            while (atk != 0) {
                int dst = CTZ64(atk);

                moves[m].src = src;
                moves[m].dst = dst;
                moves[m].special = SPECIAL_NONE;
                ++m;

                atk ^= 1ull << dst;
            }

            rooks ^= 1ull << src;
        }
    }

    {
        // bishop + queen moves
        uint64_t bishops = (gamestate->board.pieces[BISHOP] | gamestate->board.pieces[QUEEN]) & color;
        while (bishops != 0) {
            int src = CTZ64(bishops);
            uint64_t atk = bishop_attacks(occupied, src) & ~allies;

            while (atk != 0) {
                int dst = CTZ64(atk);

                moves[m].src = src;
                moves[m].dst = dst;
                moves[m].special = SPECIAL_NONE;
                ++m;

                atk ^= 1ull << dst;
            }

            bishops ^= 1ull << src;
        }
    }

    return m;
}

int is_check(board_t *board, int king, int is_b) {
    uint64_t enemies = is_b ? board->pieces_w : ~board->pieces_w;
    uint64_t occupied = occupancy(board);

    uint64_t king_atk = king_moves[king] & (1ull << ((board->kings >> (!is_b * 6)) & 0x3F));
    uint64_t knight_atk = knight_moves[king] & board->pieces[KNIGHT];
    uint64_t rook_atk = rook_attacks(occupied, king) & (board->pieces[ROOK] | board->pieces[QUEEN]);
    uint64_t bishop_atk = bishop_attacks(occupied, king) & (board->pieces[BISHOP] | board->pieces[QUEEN]);
    uint64_t pawn_atk_mask = (((1ull << king) & 0x01010101010101FF) != 0 && (1ull << (king - 9))) |
        (((1ull << king) & 0x10101010101010FF) != 0 && (1ull << (king - 7)));
    uint64_t pawn_atk = pawn_atk_mask & board->pieces[PAWN];

    return (king_atk | ((knight_atk | rook_atk | bishop_atk | pawn_atk) & enemies)) != 0;
}

int is_legal(gamestate_t *gamestate, move_t last_move) {
    static_init();
    int is_b = gamestate->board.ply & 1;
    int king_pos = (gamestate->board.kings >> (is_b * 6)) & 0x3F;

    return !is_check(&gamestate->board, king_pos, is_b) && (
        last_move.special != SPECIAL_CASTLE ||
        !is_check(&gamestate->board, ((king_pos & 0x38) | (last_move.dst < last_move.src ? 0x03 : 0x05)), is_b)
    );
}

int execute_move(gamestate_t *gamestate, move_t move) {
    gamestate->board.en_passant = 0;

    for (int i = 0; i < 2; ++i) {
        if (move.src == ((gamestate->board.kings >> (i * 6)) & 0x3F)) {
            gamestate->board.kings = (gamestate->board.kings & ~(0x3F << (i * 6))) | (move.dst << (i * 6));
            update_white(gamestate, 1ull << move.dst);
            gamestate->board.ply50 = do_capture(gamestate, move.dst) ? 0 : +gamestate->board.ply50 + 1;
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

            ++gamestate->board.ply;
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

    ++gamestate->board.ply;
    gamestate->board.ply50 = did_capture ? 0 : gamestate->board.ply50 + 1;

    if (move.special & SPECIAL_PROMOTE) {
        // requires piece_type == PAWN; todo verify
        gamestate->board.pieces[piece_type] &= ~(1ull << move.src);
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

#define MAX_STACK (64)

int pawn_eval[64] = {
      0,   0,   0,   0,   0,   0,   0,   0,
      5,  10,  10, -20, -20,  10,  10,   5,
      5,  -5, -10,   0,   0, -10,  -5,   5,
      0,   0,   0,  20,  20,   0,   0,   0,
      5,   5,  10,  25,  25,  10,   5,   5,
     10,  10,  20,  30,  30,  20,  10,  10,
     50,  50,  50,  50,  50,  50,  50,  50,
      0,   0,   0,   0,   0,   0,   0,   0,
};

int king_eval[64] = {
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -20, -30, -30, -40, -40, -30, -30, -20,
    -10, -20, -20, -20, -20, -20, -20, -10,
     20,  20,   0,   0,   0,   0,  20,  20,
     20,  30,  10,   0,   0,  10,  30,  20,
};

int king_eval_endgame[64] = {
    -50, -40, -30, -20, -20, -30, -40, -50,
    -30, -20, -10,   0,   0, -10, -20, -30,
    -30, -10,  20,  30,  30,  20, -10, -30,
    -30, -10,  30,  40,  40,  30, -10, -30,
    -30, -10,  30,  40,  40,  30, -10, -30,
    -30, -10,  20,  30,  30,  20, -10, -30,
    -30, -30,   0,   0,   0,   0, -30, -30,
    -50, -30, -30, -30, -30, -30, -30, -50,
};

int knight_eval[64] = {
    -50, -40, -30, -30, -30, -30, -40, -50,
    -40, -20,   0,   0,   0,   0, -20, -40,
    -30,   0,  10,  15,  15,  10,   0, -30,
    -30,   5,  15,  20,  20,  15,   5, -30,
    -30,   0,  15,  20,  20,  15,   0, -30,
    -30,   5,  10,  15,  15,  10,   5, -30,
    -40, -20,   0,   5,   5,   0, -20, -40,
    -50, -40, -30, -30, -30, -30, -40, -50,
};

int bishop_eval[64] = {
    -20, -10, -10, -10, -10, -10, -10, -20,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10,   0,   5,  10,  10,   5,   0, -10,
    -10,   5,   5,  10,  10,   5,   5, -10,
    -10,   0,  10,  10,  10,  10,   0, -10,
    -10,  10,  10,  10,  10,  10,  10, -10,
    -10,   5,   0,   0,   0,   0,   5, -10,
    -20, -10, -10, -10, -10, -10, -10, -20,
};

int rook_eval[64] = {
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0,
};

int queen_eval[64] = {
    -20, -10, -10,  -5,  -5, -10, -10, -20,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10,   0,   5,   5,   5,   5,   0, -10,
     -5,   0,   5,   5,   5,   5,   0,  -5,
      0,   0,   5,   5,   5,   5,   0,  -5,
    -10,   5,   5,   5,   5,   5,   0, -10,
    -10,   0,   5,   0,   0,   0,   0, -10,
    -20, -10, -10,  -5,  -5, -10, -10, -20,
};


int piece_weights[NB_ALL_PIECES] = {
    [KNIGHT] = 300,
    [BISHOP] = 340,
    [ROOK] = 550,
    [QUEEN] = 1000,
    [PAWN] = 100,
    [KING] = 15000
};

int* piece_locs[NB_ALL_PIECES][2] = {
    [KNIGHT] = {knight_eval, knight_eval},
    [BISHOP] = {bishop_eval, bishop_eval},
    [ROOK] = {rook_eval, rook_eval},
    [QUEEN] = {queen_eval, queen_eval},
    [PAWN] = {pawn_eval, pawn_eval},
    [KING] = {king_eval, king_eval_endgame},
};

int static_eval(gamestate_t *gamestate) {
    int eval = 0;

    // material + positional advantage
    int is_endgame = POPCNT64(gamestate->board.pieces[QUEEN]) * 9 + POPCNT64(gamestate->board.pieces[ROOK]) * 5 +
        POPCNT64(gamestate->board.pieces[KNIGHT]) * 3 + POPCNT64(gamestate->board.pieces[BISHOP]) * 3 +
        POPCNT64(gamestate->board.pieces[PAWN]) <= 26;

    int mat = 0;
    for (piece_t p = KNIGHT; p < NB_PIECES; ++p) {
        uint64_t locs = gamestate->board.pieces[p];

        while (locs != 0) {
            int src = CTZ64(locs);
            int is_w = (gamestate->board.pieces_w >> src) & 1;

            if (is_w) {
                mat += piece_weights[p] + piece_locs[p][is_endgame][src];
            } else {
                mat -= piece_weights[p] + piece_locs[p][is_endgame][0x38 - (src & 0x38) + (src & 0x07)];
            }

            locs ^= 1ull << src;
        }
    }

    if (!(gamestate->board.checkmate & 1)) mat += piece_weights[KING] + piece_locs[KING][is_endgame][gamestate->board.kings & 0x3F];
    if (!(gamestate->board.checkmate >> 1)) mat -= piece_weights[KING] + piece_locs[KING][is_endgame][gamestate->board.kings >> 6];
    eval += mat;

    // bishop pair advantage
    int dark_bishop = gamestate->board.pieces[BISHOP] & 0xCC55CC55CC55CC55ull;
    int light_bishop = gamestate->board.pieces[BISHOP] & 0x55CC55CC55CC55CCull;
    int bishop_pair_delta = ((dark_bishop & gamestate->board.pieces_w) != 0 && (light_bishop & gamestate->board.pieces_w) != 0) - 
        ((dark_bishop & ~gamestate->board.pieces_w) != 0 && (light_bishop & ~gamestate->board.pieces_w) != 0);
    int bishop_pair_bonus = 80 * bishop_pair_delta;
    eval += bishop_pair_bonus;

    // castling advantage
    int castle_bonus = 20 * (
        (gamestate->board.castle & 1) + ((gamestate->board.castle >> 1) & 1) -
        ((gamestate->board.castle >> 2) & 1) - (gamestate->board.castle >> 3)
    );
    eval += castle_bonus;

    return (gamestate->board.ply & 1) ? -eval : eval;
}

uint64_t perft(const gamestate_t *gamestate, int depth) {
    if (depth <= 0) return 1;

    move_t pl_moves[MAX_MOVES];
    gamestate_t gs_next;

    int num_moves = pseudolegal_moves(gamestate, pl_moves);
    int children = 0;
    for (int i = 0; i < num_moves; ++i) {
        memcpy(&gs_next, gamestate, sizeof(gamestate_t));

        assert(execute_move(&gs_next, pl_moves[i]) == 0);
        if (!is_legal(&gs_next, pl_moves[i])) continue;

        children += perft(&gs_next, depth - 1);
    }

    return children;
}

struct search_state {
    struct timeval start_time;
    uint64_t timeout_us;
};

int timed_out(const struct search_state *st) {
    struct timeval cur;
    gettimeofday(&cur, NULL);
    return (cur.tv_sec - st->start_time.tv_sec) * 1000000 + (cur.tv_usec - st->start_time.tv_usec) >= st->timeout_us;
}

int negamax(const gamestate_t *gamestate, struct search_state *st, int alpha, int beta, int depth) {
    move_t pl_moves[MAX_MOVES];
    gamestate_t gs_next;

    int num_moves = pseudolegal_moves(gamestate, pl_moves);
    // TODO: sort moves (by static_eval? or a faster heuristic)

    for (int i = 0; !timed_out(st) && i < num_moves; ++i) {
        memcpy(&gs_next, gamestate, sizeof(gamestate_t));

        assert(execute_move(&gs_next, pl_moves[i]) == 0);
        if (!is_legal(&gs_next, pl_moves[i])) continue;

        int eval;
        if (gs_next.board.ply50 >= 50) eval = 0;
        else if (gs_next.board.checkmate) eval = 32767;
        else if (depth <= 0) eval = static_eval(&gs_next);
        else eval = -negamax(&gs_next, st, -beta, -alpha, depth - 1);

        if (eval > alpha) alpha = eval;
        if (alpha >= beta) break;
    }

    return alpha;
}

int cmp_engine_move(const void *a, const void *b) {
    engine_move_t *am = (engine_move_t*) a;
    engine_move_t *bm = (engine_move_t*) b;

    return am->eval - bm->eval;
}

int search_moves(const gamestate_t *gamestate, search_params_t params, best_moves_t *best_moves) {
    if (gamestate->board.checkmate) return -1;

    struct search_state st;
    gettimeofday(&st.start_time, NULL);
    st.timeout_us = params.timeout_ms < 0 ? UINT64_MAX : params.timeout_ms * 1000;

    for (int initial_depth = 0; initial_depth < MAX_STACK; ++initial_depth) {
        int alpha = -32767;
        int beta = 32767;

        move_t pl_moves[MAX_MOVES];
        int move_evals[MAX_MOVES];
        gamestate_t gs_next;

        int num_moves = pseudolegal_moves(gamestate, pl_moves);
        // TODO: sort moves (by static_eval? or a faster heuristic)

        for (int i = 0; !timed_out(&st) && i < num_moves; ++i) {
            memcpy(&gs_next, gamestate, sizeof(gamestate_t));

            assert(execute_move(&gs_next, pl_moves[i]) == 0);
            if (!is_legal(&gs_next, pl_moves[i])) {
                move_evals[i] = -32768;
                continue;
            }

            int eval;
            if (gs_next.board.ply50 >= 50) eval = 0;
            else if (gs_next.board.checkmate) eval = 32767;
            else if (initial_depth <= 0) eval = static_eval(&gs_next);
            else eval = -negamax(&gs_next, &st, -beta, -alpha, initial_depth);
            move_evals[i] = eval;

            if (eval > alpha) alpha = eval;
            if (alpha >= beta) break;
        }

        if (timed_out(&st) && initial_depth > 0) break;

        int m = 0;
        for (int i = 0; i < num_moves; ++i) {
            if (move_evals[i] == -32768) continue;
            best_moves->moves[m].move = pl_moves[i];
            best_moves->moves[m].eval = move_evals[i];
            ++m;
        }
        best_moves->num_moves = m;

        qsort(best_moves->moves, m, sizeof(engine_move_t), &cmp_engine_move);
    }

    return 0;
}