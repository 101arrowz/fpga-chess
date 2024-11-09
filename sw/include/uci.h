#ifndef _UCI_H
#define _UCI_H

#include <stdio.h>
#include "board.h"

int parse_fen(board_t *board, const char **fen);
move_t parse_lan_move(const char** ptr);
void serialize_lan_move(const move_t move, char* out);
int uci_start(FILE *in, FILE *out);

#endif
