#include <stdlib.h>
#include "board.h"
#include "engine.h"

#ifndef __has_builtin
#define __has_builtin(x) (0)
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

uint64_t occupancy(board_t *board) {
    uint64_t occupied = (1ull << (board->kings & 0x3F)) | (1ull << ((board->kings >> 6) & 0x3F));
    for (int i = 0; i < NB_PIECES; ++i) occupied |= board->pieces[i];

    return occupied;
}

int pseudolegal_moves(gamestate_t *gamestate, move_t* moves) {
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


int search_moves(const gamestate_t *gamestate, best_moves_t *best_moves) {
    // stub
    return -1;
}