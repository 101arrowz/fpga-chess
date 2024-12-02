#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <ctype.h>
#include <unistd.h>

#include "board.h"
#include "uci.h"
#include "engine.h"
#include "shared.h"

int uci_start(FILE *in, FILE *out) {
    char *linebuf = NULL;
    size_t line_size;
    ssize_t line_len;

    bool initialized = false;
    bool debug_mode = false;
    gamestate_t gs;
    const char* init_fen = STARTPOS_FEN;
    assert(!parse_fen(&gs.board, &init_fen));
    best_moves_t moves;
    const char* uci_delim = " \f\n\r\t\v";

    while ((line_len = getline(&linebuf, &line_size, in)) >= 0) {
        char* sts;
        char* tok = strtok_r(linebuf, uci_delim, &sts);
        if (!tok) continue;

        if (!strcmp(tok, "uci")) {
            fprintf(out, "id name River_SW\n"
                         "id author Arjun Barrett and Dylan Isaac\n"
                         "uciok\n");
            fflush(out);
            initialized = true;
            continue;
        }

        if (!initialized) {
            return -1;
        }

        if (!strcmp(tok, "debug")) {
            if ((tok = strtok_r(NULL, uci_delim, &sts)) == NULL) continue;
            if (!strcmp(tok, "on")) debug_mode = true;
            else if (!strcmp(tok, "off")) debug_mode = false;
        } else if (!strcmp(tok, "isready")) {
            fprintf(out, "readyok\n");
            fflush(out);
        } else if (!strcmp(tok, "ucinewgame")) {
            // stateless engine so this isn't necessary to handle
        } else if (!strcmp(tok, "position")) {
            if ((tok = strtok_r(NULL, uci_delim, &sts)) == NULL) continue;
            if (!strcmp(tok, "fen")) {
                char* fen_loc = tok + 4;
                while (strchr(uci_delim, *fen_loc)) ++fen_loc;
                if (parse_fen(&gs.board, (const char**) &fen_loc)) {
                    fprintf(out, "info invalid fen\n");
                    continue;
                }
                // TODO: verify
                gs.board.checkmate = 0;
                tok = strtok_r(fen_loc, uci_delim, &sts);
            } else if (!strcmp(tok, "startpos")) {
                const char* fen = STARTPOS_FEN;
                assert(!parse_fen(&gs.board, &fen));
                gs.board.checkmate = 0;
                tok = strtok_r(NULL, uci_delim, &sts);
            } else {
                continue;
            }

            if (tok == NULL) continue;
            if (!strcmp(tok, "moves")) {
                while ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL) {
                    move_t move = parse_lan_move((const char**) &tok);
                    if (move.special == SPECIAL_UNKNOWN) break;
                    if (move.special == SPECIAL_NONE) move.special = SPECIAL_UNKNOWN;
                    if (execute_move(&gs, move) < 0) {
                        fprintf(out, "info invalid moves\n");
                        continue;
                    }
                }
            }
        } else if (!strcmp(tok, "go")) {
            search_params_t params = {.timeout_ms = 1000, .max_depth = -1};
            if ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL) {
                if (!strcmp(tok, "perft")) {
                    int depth = 64;
                    if ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL) depth = atoi(tok);
                    for (int i = 0; i < depth; ++i) {
                        uint64_t count = perft(&gs, i);
                        fprintf(out, "info perft(%i) = %" PRIu64 "\n", i, count);
                        fflush(out);
                    }
                    ;
                    continue;
                } else if (!strcmp(tok, "depth")) {
                    if ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL) params.max_depth = atoi(tok);
                } else if (!strcmp(tok, "timeout")) {
                    if ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL) params.timeout_ms = atoi(tok);
                } else {
                    // standardized UCI commands
                    do {
                        // TODO: implement
                        break;
                    } while ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL);
                }
            }
            gs.engine_debug = debug_mode;
            if (search_moves(&gs, params, &moves)) continue;

            char move_name[6];

            if (debug_mode) {
                for (int i = 0; i < moves.num_moves; ++i) {
                    serialize_lan_move(moves.moves[i].move, move_name);

                    fprintf(out, "info move %3i: %s (eval = %i)\n", i, move_name, moves.moves[i].eval);
                }
            }

            serialize_lan_move(moves.moves[0].move, move_name);
            fprintf(out, "bestmove %s\n", move_name);
            fflush(stdout);
        } else if (!strcmp(tok, "move")) {
            if ((tok = strtok_r(NULL, uci_delim, &sts)) == NULL) continue;
            move_t move = parse_lan_move((const char**) &tok);
            execute_move(&gs, move);
        } else if (!strcmp(tok, "quit")) {
            initialized = false;
            break;
        }
    }

    return 0;
}