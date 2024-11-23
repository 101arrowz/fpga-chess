#ifndef _ENGINE_H
#define _ENGINE_H

#include <stdbool.h>
#include "board.h"

// max moves ever constructed is 218 - use 256 to be safe
#define MAX_MOVES (256)

typedef int16_t eval_t;

typedef struct gamestate {
    board_t board;
    // TODO: other context (for 3-move rule etc.)
    bool engine_debug;
} gamestate_t;

typedef struct engine_move {
    move_t move;
    eval_t eval;
} engine_move_t;

typedef struct best_moves {
    engine_move_t moves[MAX_MOVES];
    uint8_t num_moves;
} best_moves_t;

typedef struct search_params {
    int timeout_ms;
} search_params_t;

// for now, assume engine is stateless with regards to the game
// later, may make it stateful (e.g. to keep past positions known)
int search_moves(const gamestate_t *gamestate, search_params_t params, best_moves_t *best_moves);
// execute a move on the game state
int execute_move(gamestate_t *gamestate, move_t move);
uint64_t perft(const gamestate_t *gamestate, int depth);

#endif
