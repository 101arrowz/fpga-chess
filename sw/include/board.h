#ifndef _BOARD_H
#define _BOARD_H

#include <inttypes.h>

typedef enum piece {
    KNIGHT = 0,
    BISHOP = 1,
    ROOK = 2,
    QUEEN = 3,

    // allow knight-queen to fit in 2 bits (e.g. for promotions)
    PAWN = 4
} piece_t;

typedef struct board {
    // bitboards for each piece
    uint64_t pieces[5] /* : 64 */;
    // which pieces are white
    uint64_t pieces_w /* : 64 */;
    // king positions; black = kings >> 6, white = kings & 63
    uint16_t kings: 12;
    // allowed en-passant file on the next move; valid = ep_next >> 3, file = ep_next & 7
    uint8_t en_passant: 4;
    // castling rights; black = castle >> 2, white = castle & 3; queenside = rights >> 1, kingside = rights & 1
    uint8_t castle: 4;
    // number of half-moves taken place; lsb = 0 means white to play, lsb = 1 means black
    uint16_t ply: 15;
    // number of half-moves since last pawn move or capture (for draws)
    uint8_t ply50: 7;
} board_t;

typedef enum move_special {
    SPECIAL_NONE = 0,
    SPECIAL_EN_PASSANT = 1,
    SPECIAL_CASTLE = 2,

    // can be used to signal an invalid move or unknown special fields (e.g. for UCI moves)
    SPECIAL_UNKNOWN = 3,
    
    // if (special & PROMOTION) promote_piece = (piece_t) (special & 3)
    SPECIAL_PROMOTE = 4,
    SPECIAL_PROMOTE_KNIGHT = 4,
    SPECIAL_PROMOTE_BISHOP = 5,
    SPECIAL_PROMOTE_ROOK = 6,
    SPECIAL_PROMOTE_QUEEN = 7
} move_special_t;

typedef struct move {
    uint8_t src: 6;
    uint8_t dst: 6;
    move_special_t special: 3;
} move_t;

#endif
