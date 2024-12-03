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

typedef struct {
    logic [4:0][63:0] pieces = 0;
    logic [63:0] pieces_w = 0;
    logic [5:0] king_w = 0;
    logic [5:0] king_b = 0;
    logic checkmate_w=0;
    logic checkmate_b=0;
    logic[7:0] en_passant=0;
    logic[7:0] castle=0;//Not sure how this is encoded, so not sure how many bits are required
    logic[15:0] ply=0;
    logic[7:0] ply50=0;
} board_t;
typedef struct packed  {
    logic[2:0] src_col;
    logic[2:0] src_row;
    logic[2:0] dst_col;
    logic[2:0] dst_row;
    move_special_t special;
} move_t;