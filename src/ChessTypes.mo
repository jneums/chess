module {
  // --- Piece types ---
  public type Color = { #white; #black };
  public type PieceType = { #king; #queen; #rook; #bishop; #knight; #pawn };

  public type Piece = {
    pieceType : PieceType;
    color : Color;
  };

  // --- Move ---
  public type Move = {
    from : Nat;
    to : Nat;
    piece : PieceType;
    captured : ?PieceType;
    promotion : ?PieceType;
    isCheck : Bool;
    isCastle : Bool;
    isEnPassant : Bool;
    notation : Text;
    moveNumber : Nat;
  };

  // --- Game status ---
  public type GameStatus = {
    #waiting;
    #active;
    #checkmate;
    #stalemate;
    #draw;
    #resigned;
  };

  // --- Game ---
  public type Game = {
    id : Text;
    white : Principal;
    black : ?Principal;
    board : [?Piece]; // 64 squares, a1=0 .. h8=63
    moves : [Move];
    status : GameStatus;
    turn : Color;
    winner : ?Color;
    whiteCanCastleKing : Bool;
    whiteCanCastleQueen : Bool;
    blackCanCastleKing : Bool;
    blackCanCastleQueen : Bool;
    enPassantSquare : ?Nat;
    halfMoveClock : Nat;
    fullMoveNumber : Nat;
    createdAt : Nat;
    updatedAt : Nat;
    drawOffer : ?Color;
  };

  // --- Player stats ---
  public type PlayerStats = {
    principal : Principal;
    wins : Nat;
    losses : Nat;
    draws : Nat;
    elo : Int;
    gamesPlayed : Nat;
  };
};
