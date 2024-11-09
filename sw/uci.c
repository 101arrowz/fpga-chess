#include <assert.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>

#include "board.h"
#include "uci.h"
#include "engine.h"

#define PARSE_FEN_EOF (-1)
#define PARSE_FEN_INVALID (-1)
#define PARSE_FEN_OK 0

uint32_t parse_base10(const char **str) {
    const char *p = *str;
    uint64_t result = 0;

    if (*p == '0') {
        if ('0' <= p[1] && p[1] <= '9') return -1;
        *str = p + 1;
        return 0;
    }

    while ('0' <= *p && *p <= '9') {
        result = result * 10 + (*p++ - '0');
        if (result > UINT32_MAX) return -1;
    }

    if (p == *str) return -1;
    *str = p;
    return result;
}

#define STARTPOS_FEN ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

int parse_fen(board_t *board, const char** ptr) {
    const char* fen = *ptr;

    memset(board->pieces, 0, sizeof(board->pieces));
    memset(&board->pieces_w, 0, sizeof(board->pieces_w));

    for (int rank = 7; rank >= 0; --rank) {
        int file = 0;

        for (; file < 8; ++fen) {
            if (*fen == '\0') {
                return PARSE_FEN_EOF;
            } else if ('0' <= *fen && *fen <= '7') {
                file += *fen - '0';
            } else {
                int piece = -1;
                switch (*fen) {
                    case 'n':
                    case 'N':
                        piece = KNIGHT;
                        break;
                    case 'b':
                    case 'B':
                        piece = BISHOP;
                        break;
                    case 'r':
                    case 'R':
                        piece = ROOK;
                        break;
                    case 'q':
                    case 'Q':
                        piece = QUEEN;
                        break;
                    case 'p':
                    case 'P':
                        piece = PAWN;
                        break;
                }

                if (piece < 0) return PARSE_FEN_INVALID;
                board->pieces[piece] |= 1ull << (rank * 8 + file);
                board->pieces_w |= ((uint64_t) (*fen >= 'a')) << (rank * 8 + file);
            }
        }

        if (file != 8) return PARSE_FEN_INVALID;

        if (rank > 0 && *fen++ != '/') return PARSE_FEN_INVALID;
    }

    if (*fen++ != ' ') return PARSE_FEN_INVALID;

    if (*fen != 'w' && *fen != 'b') return PARSE_FEN_INVALID;
    bool is_black = *fen == 'b';
    ++fen;

    if (*fen++ != ' ') return PARSE_FEN_INVALID;

    board->castle = 0;
    if (*fen == '-') {
        ++fen;
    } else {
        do {
            int rights;
            switch (*fen) {
                case 'k': rights = 0; break;
                case 'q': rights = 1; break;
                case 'K': rights = 2; break;
                case 'Q': rights = 3; break;
                default: return PARSE_FEN_INVALID;
            };
            if (board->castle & (1 << rights)) return PARSE_FEN_INVALID;
            board->castle |= 1 << rights;
            ++fen;
        } while (*fen != ' ');
    }

    if (*fen++ != ' ') return PARSE_FEN_INVALID;

    if (*fen == '-') {
        board->en_passant = 0;
        ++fen;
    } else {
        if (*fen < 'a' || *fen > 'h') return PARSE_FEN_INVALID;
        board->en_passant = (1 << 3) | (*fen++ - 'a');
        if (*fen != '3' && *fen != '6') return PARSE_FEN_INVALID;
        // need opposing color to move when pawn is on rank 3 (i.e. white pawn)
        if ((*fen++ == '3') != is_black) return PARSE_FEN_INVALID;
    }

    if (*fen++ != ' ') return PARSE_FEN_INVALID;

    int ply50 = parse_base10(&fen);
    if (ply50 < 0 /* || ply50 >= 50 */) return PARSE_FEN_INVALID;
    board->ply50 = ply50;

    if (*fen++ != ' ') return PARSE_FEN_INVALID;

    int fullmove = parse_base10(&fen);
    if (fullmove < 0 /* || fullmove > 5949 */) return PARSE_FEN_INVALID;
    board->ply = (fullmove - 1) * 2 + is_black;

    *ptr = fen;
    return PARSE_FEN_OK;
}

static move_t invalid_move = {.special = SPECIAL_UNKNOWN};

move_t parse_lan_move(const char** ptr) {
    const char *lan = *ptr;
    move_t move;

    if (*lan < 'a' || *lan > 'h') return invalid_move;
    move.src = (*lan++ - 'a');
    if (*lan < '1' || *lan > '8') return invalid_move;
    move.src |= (*lan++ - '1') << 3;

    if (*lan < 'a' || *lan > 'h') return invalid_move;
    move.dst = (*lan++ - 'a');
    if (*lan < '1' || *lan > '8') return invalid_move;
    move.dst |= (*lan++ - '1') << 3;

    switch (*lan) {
        case 'n': ++lan; move.special = SPECIAL_PROMOTE_KNIGHT; break;
        case 'b': ++lan; move.special = SPECIAL_PROMOTE_BISHOP; break;
        case 'r': ++lan; move.special = SPECIAL_PROMOTE_ROOK; break;
        case 'q': ++lan; move.special = SPECIAL_PROMOTE_QUEEN; break;
        default: move.special = SPECIAL_NONE; break;
    }

    *ptr = lan;
    return move;
}

void serialize_lan_move(const move_t move, char* out) {
    out[0] = 'a' + (move.src & 7);
    out[1] = '1' + (move.src >> 3);
    out[2] = 'a' + (move.dst & 7);
    out[3] = '1' + (move.dst >> 3);

    // TODO: extra handling needed for castling/etc.?
    if (move.special & SPECIAL_PROMOTE) {
        char promo[4] = {[KNIGHT] = 'n', [BISHOP] = 'b', [ROOK] = 'r', [QUEEN] = 'q'};
        out[4] = promo[move.special & 3];
        out[5] = '\0';
    } else {
        out[4] = '\0';
    }
}

int uci_start(FILE *in, FILE *out) {
    char *linebuf = NULL;
    size_t line_size;
    ssize_t line_len;

    bool initialized = false;
    bool debug_mode = false;
    gamestate_t gs;
    best_moves_t moves;
    const char* uci_delim = " \f\n\r\t\v";

    while ((line_len = getline(&linebuf, &line_size, in))) {
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
                if ((tok = strtok_r(NULL, uci_delim, &sts)) == NULL) continue;
                if (!parse_fen(&gs.board, (const char**) &tok)) continue;
            } else if (!strcmp(tok, "startpos")) {
                const char* fen = STARTPOS_FEN;
                assert(!parse_fen(&gs.board, &fen));
            } else {
                continue;
            }

            if ((tok = strtok_r(NULL, uci_delim, &sts)) == NULL) continue;
            if (!strcmp(tok, "moves")) {
                while ((tok = strtok_r(NULL, uci_delim, &sts)) != NULL) {
                    move_t move = parse_lan_move((const char**) &tok);
                    if (move.special == SPECIAL_UNKNOWN) break;
                    if (move.special == SPECIAL_NONE) move.special = SPECIAL_UNKNOWN;
                    if (execute_move(&gs, move)) break;
                }
            }
        } else if (!strcmp(tok, "go")) {
            gs.engine_debug = debug_mode;
            if (search_moves(&gs, &moves)) continue;

            char move_name[6];
            serialize_lan_move(moves.moves[0].move, move_name);

            fprintf(out, "bestmove %s\n", move_name);
            fflush(stdout);
        } else if (!strcmp(tok, "quit")) {
            initialized = false;
            break;
        }
    }

    return 0;
}