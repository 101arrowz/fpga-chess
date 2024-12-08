`define SPECIAL_PROMOTE SPECIAL_PROMOTE_KNIGHT

typedef enum logic[2:0] {
    SPECIAL_NONE = 3'b000,
    SPECIAL_EN_PASSANT = 3'b001,
    SPECIAL_CASTLE = 3'b010,

    // can be used to signal an invalid move or unknown special fields (e.g. for UCI moves)
    SPECIAL_UNKNOWN = 3'b011,
    
    // if (special & PROMOTION) promote_piece = (piece_t) (special & 3)
    //SPECIAL_PROMOTE = 4, This line makes IVerilog throw error
    SPECIAL_PROMOTE_KNIGHT = 3'b100,
    SPECIAL_PROMOTE_BISHOP = 3'b101,
    SPECIAL_PROMOTE_ROOK = 3'b110,
    SPECIAL_PROMOTE_QUEEN = 3'b111
} move_special_t;

`define NB_PIECES 5

typedef enum logic[2:0] {
    KNIGHT = 3'b000,
    BISHOP = 3'b001,
    ROOK = 3'b010,
    QUEEN = 3'b011,
    PAWN = 3'b100,
    KING = 3'b101
} piece_t;

typedef struct packed  {
    logic[2:0] rnk;
    logic[2:0] fil;
} coord_t;

typedef struct packed {
    logic [4:0][63:0] pieces;
    logic [63:0] pieces_w;
    coord_t[1:0] kings;
    logic[1:0] checkmate;
    logic[3:0] en_passant;
    logic[1:0][1:0] castle;
    logic[14:0] ply;
    logic[6:0] ply50;
} board_t;

typedef struct packed  {
    coord_t src;
    coord_t dst;
    move_special_t special;
} move_t;