#ifndef _SHARED_H
#define _SHARED_H

#include <stdio.h>
#include "board.h"


#define PARSE_FEN_EOF (-1)
#define PARSE_FEN_INVALID (-1)
#define PARSE_FEN_OK (0)
#define STARTPOS_FEN ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

int parse_fen(board_t *board, const char **fen);
move_t parse_lan_move(const char** ptr);
void serialize_lan_move(const move_t move, char* out);

#endif