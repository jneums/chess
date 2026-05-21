import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

import T "ChessTypes";

module {

  // ========== BOARD HELPERS ==========

  // Convert file (0-7) and rank (0-7) to square index
  public func toSquare(file : Nat, rank : Nat) : Nat {
    rank * 8 + file;
  };

  // Get file from square index
  public func fileOf(sq : Nat) : Nat { sq % 8 };

  // Get rank from square index
  public func rankOf(sq : Nat) : Nat { sq / 8 };

  // Check if square is on board
  public func onBoard(file : Int, rank : Int) : Bool {
    file >= 0 and file < 8 and rank >= 0 and rank < 8;
  };

  // ========== INITIAL POSITION ==========

  public func initialBoard() : [?T.Piece] {
    let board = Array.init<?T.Piece>(64, null);
    // White pieces (rank 0)
    board[0] := ?{ pieceType = #rook; color = #white };
    board[1] := ?{ pieceType = #knight; color = #white };
    board[2] := ?{ pieceType = #bishop; color = #white };
    board[3] := ?{ pieceType = #queen; color = #white };
    board[4] := ?{ pieceType = #king; color = #white };
    board[5] := ?{ pieceType = #bishop; color = #white };
    board[6] := ?{ pieceType = #knight; color = #white };
    board[7] := ?{ pieceType = #rook; color = #white };
    // White pawns (rank 1)
    for (i in Iter.range(8, 15)) {
      board[i] := ?{ pieceType = #pawn; color = #white };
    };
    // Black pawns (rank 6)
    for (i in Iter.range(48, 55)) {
      board[i] := ?{ pieceType = #pawn; color = #black };
    };
    // Black pieces (rank 7)
    board[56] := ?{ pieceType = #rook; color = #black };
    board[57] := ?{ pieceType = #knight; color = #black };
    board[58] := ?{ pieceType = #bishop; color = #black };
    board[59] := ?{ pieceType = #queen; color = #black };
    board[60] := ?{ pieceType = #king; color = #black };
    board[61] := ?{ pieceType = #bishop; color = #black };
    board[62] := ?{ pieceType = #knight; color = #black };
    board[63] := ?{ pieceType = #rook; color = #black };

    Array.freeze(board);
  };

  // ========== COLOR HELPERS ==========

  public func oppositeColor(c : T.Color) : T.Color {
    switch (c) { case (#white) #black; case (#black) #white };
  };

  public func colorEq(a : T.Color, b : T.Color) : Bool {
    switch (a, b) {
      case (#white, #white) true;
      case (#black, #black) true;
      case _ false;
    };
  };

  public func pieceTypeEq(a : T.PieceType, b : T.PieceType) : Bool {
    switch (a, b) {
      case (#king, #king) true;
      case (#queen, #queen) true;
      case (#rook, #rook) true;
      case (#bishop, #bishop) true;
      case (#knight, #knight) true;
      case (#pawn, #pawn) true;
      case _ false;
    };
  };

  // ========== BOARD RENDERING ==========

  func pieceChar(p : T.Piece) : Text {
    switch (p.color, p.pieceType) {
      case (#white, #king) "K";
      case (#white, #queen) "Q";
      case (#white, #rook) "R";
      case (#white, #bishop) "B";
      case (#white, #knight) "N";
      case (#white, #pawn) "P";
      case (#black, #king) "k";
      case (#black, #queen) "q";
      case (#black, #rook) "r";
      case (#black, #bishop) "b";
      case (#black, #knight) "n";
      case (#black, #pawn) "p";
    };
  };

  public func renderBoard(board : [?T.Piece]) : Text {
    var result = "  a b c d e f g h\n";
    // Render from rank 8 (index 7) down to rank 1 (index 0)
    var rank : Int = 7;
    while (rank >= 0) {
      let r = Int.abs(rank);
      result #= Nat.toText(r + 1) # " ";
      for (file in Iter.range(0, 7)) {
        let sq = toSquare(file, r);
        switch (board[sq]) {
          case (?p) { result #= pieceChar(p) # " " };
          case (null) { result #= ". " };
        };
      };
      result #= Nat.toText(r + 1) # "\n";
      rank -= 1;
    };
    result #= "  a b c d e f g h";
    result;
  };

  // ========== MOVE NOTATION ==========

  public func squareToAlgebraic(sq : Nat) : Text {
    let file = fileOf(sq);
    let rank = rankOf(sq);
    let fileChar = Text.fromChar(Char.fromNat32(Nat32.fromNat(97 + file))); // 'a' = 97
    fileChar # Nat.toText(rank + 1);
  };

  public func algebraicToSquare(s : Text) : ?Nat {
    let chars = Text.toArray(s);
    if (chars.size() < 2) return null;
    let fileChar = chars[0];
    let rankChar = chars[1];
    let fileCode = Nat32.toNat(Char.toNat32(fileChar));
    let rankCode = Nat32.toNat(Char.toNat32(rankChar));
    if (fileCode < 97 or fileCode > 104) return null; // a-h
    if (rankCode < 49 or rankCode > 56) return null;  // 1-8
    let file = fileCode - 97;
    let rank = rankCode - 49;
    ?toSquare(file, rank);
  };

  // Parse move like "e2e4" or "e7e8q"
  public func parseMove(moveStr : Text) : Result.Result<{ from : Nat; to : Nat; promotion : ?T.PieceType }, Text> {
    let lower = Text.toLowercase(moveStr);
    let chars = Text.toArray(lower);
    if (chars.size() < 4 or chars.size() > 5) {
      return #err("Invalid move format. Use coordinate notation like 'e2e4' or 'e7e8q'");
    };

    let fromStr = Text.fromChar(chars[0]) # Text.fromChar(chars[1]);
    let toStr = Text.fromChar(chars[2]) # Text.fromChar(chars[3]);

    let from = switch (algebraicToSquare(fromStr)) {
      case (?sq) sq;
      case null return #err("Invalid source square: " # fromStr);
    };
    let to = switch (algebraicToSquare(toStr)) {
      case (?sq) sq;
      case null return #err("Invalid target square: " # toStr);
    };

    var promotion : ?T.PieceType = null;
    if (chars.size() == 5) {
      promotion := switch (chars[4]) {
        case ('q') ?#queen;
        case ('r') ?#rook;
        case ('b') ?#bishop;
        case ('n') ?#knight;
        case _ return #err("Invalid promotion piece. Use q, r, b, or n");
      };
    };

    #ok({ from; to; promotion });
  };

  // ========== FIND KING ==========

  public func findKing(board : [?T.Piece], color : T.Color) : ?Nat {
    for (i in Iter.range(0, 63)) {
      switch (board[i]) {
        case (?p) {
          if (colorEq(p.color, color) and pieceTypeEq(p.pieceType, #king)) {
            return ?i;
          };
        };
        case null {};
      };
    };
    null;
  };

  // ========== ATTACK DETECTION ==========

  // Check if a square is attacked by any piece of the given color
  public func isSquareAttacked(board : [?T.Piece], sq : Nat, byColor : T.Color) : Bool {
    let file = fileOf(sq);
    let rank = rankOf(sq);
    let f : Int = file;
    let r : Int = rank;

    // Knight attacks
    let knightOffsets : [(Int, Int)] = [
      (-2, -1), (-2, 1), (-1, -2), (-1, 2),
      (1, -2), (1, 2), (2, -1), (2, 1)
    ];
    for ((df, dr) in knightOffsets.vals()) {
      let nf = f + df;
      let nr = r + dr;
      if (onBoard(nf, nr)) {
        let nsq = toSquare(Int.abs(nf), Int.abs(nr));
        switch (board[nsq]) {
          case (?p) {
            if (colorEq(p.color, byColor) and pieceTypeEq(p.pieceType, #knight)) return true;
          };
          case null {};
        };
      };
    };

    // Pawn attacks
    let pawnDir : Int = switch (byColor) { case (#white) 1; case (#black) -1 };
    // A pawn on rank (r - pawnDir) attacks square (f-1, r) and (f+1, r)
    let pawnRank = r - pawnDir;
    for (pf in [f - 1, f + 1].vals()) {
      if (onBoard(pf, pawnRank)) {
        let psq = toSquare(Int.abs(pf), Int.abs(pawnRank));
        switch (board[psq]) {
          case (?p) {
            if (colorEq(p.color, byColor) and pieceTypeEq(p.pieceType, #pawn)) return true;
          };
          case null {};
        };
      };
    };

    // King attacks (adjacent squares)
    for (df in [-1, 0, 1].vals()) {
      for (dr in [-1, 0, 1].vals()) {
        if (df != 0 or dr != 0) {
          let kf = f + df;
          let kr = r + dr;
          if (onBoard(kf, kr)) {
            let ksq = toSquare(Int.abs(kf), Int.abs(kr));
            switch (board[ksq]) {
              case (?p) {
                if (colorEq(p.color, byColor) and pieceTypeEq(p.pieceType, #king)) return true;
              };
              case null {};
            };
          };
        };
      };
    };

    // Sliding pieces: rook/queen (straight), bishop/queen (diagonal)
    // Straight directions (rook, queen)
    let straightDirs : [(Int, Int)] = [(0, 1), (0, -1), (1, 0), (-1, 0)];
    for ((df, dr) in straightDirs.vals()) {
      var dist : Int = 1;
      label straightLoop while (true) {
        let nf = f + df * dist;
        let nr = r + dr * dist;
        if (not onBoard(nf, nr)) break straightLoop;
        let nsq = toSquare(Int.abs(nf), Int.abs(nr));
        switch (board[nsq]) {
          case (?p) {
            if (colorEq(p.color, byColor) and (pieceTypeEq(p.pieceType, #rook) or pieceTypeEq(p.pieceType, #queen))) return true;
            break straightLoop; // blocked
          };
          case null {};
        };
        dist += 1;
      };
    };

    // Diagonal directions (bishop, queen)
    let diagDirs : [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    for ((df, dr) in diagDirs.vals()) {
      var dist : Int = 1;
      label diagLoop while (true) {
        let nf = f + df * dist;
        let nr = r + dr * dist;
        if (not onBoard(nf, nr)) break diagLoop;
        let nsq = toSquare(Int.abs(nf), Int.abs(nr));
        switch (board[nsq]) {
          case (?p) {
            if (colorEq(p.color, byColor) and (pieceTypeEq(p.pieceType, #bishop) or pieceTypeEq(p.pieceType, #queen))) return true;
            break diagLoop;
          };
          case null {};
        };
        dist += 1;
      };
    };

    false;
  };

  // Is the given color's king in check?
  public func isInCheck(board : [?T.Piece], color : T.Color) : Bool {
    switch (findKing(board, color)) {
      case (?kingSq) isSquareAttacked(board, kingSq, oppositeColor(color));
      case null false; // shouldn't happen
    };
  };

  // ========== MOVE GENERATION (for legality checking) ==========

  // Apply a move to a board (returns new board). Does NOT validate legality.
  public func applyMoveRaw(board : [?T.Piece], from : Nat, to : Nat, promotion : ?T.PieceType, enPassantSq : ?Nat) : [?T.Piece] {
    let newBoard = Array.thaw<?T.Piece>(board);
    let piece = board[from];

    switch (piece) {
      case (?p) {
        var movedPiece = p;

        // Handle promotion
        switch (promotion) {
          case (?promo) {
            movedPiece := { pieceType = promo; color = p.color };
          };
          case null {};
        };

        // Handle en passant capture
        switch (enPassantSq) {
          case (?epSq) {
            if (pieceTypeEq(p.pieceType, #pawn) and to == epSq) {
              // Remove the captured pawn
              let capturedPawnSq = switch (p.color) {
                case (#white) to - 8; // pawn was one rank below
                case (#black) to + 8;
              };
              newBoard[capturedPawnSq] := null;
            };
          };
          case null {};
        };

        // Handle castling
        if (pieceTypeEq(p.pieceType, #king)) {
          let fileDiff : Int = Int.abs(to) - Int.abs(from);
          if (fileDiff == 2) {
            // Kingside castle
            let rookFrom = to + 1;
            let rookTo : Nat = to - 1;
            newBoard[rookTo] := board[rookFrom];
            newBoard[rookFrom] := null;
          } else if (fileDiff == -2) {
            // Queenside castle
            let rookFrom : Nat = to - 2;
            let rookTo = to + 1;
            newBoard[rookTo] := board[rookFrom];
            newBoard[rookFrom] := null;
          };
        };

        newBoard[to] := ?movedPiece;
        newBoard[from] := null;
      };
      case null {};
    };

    Array.freeze(newBoard);
  };

  // Check if a pseudo-legal move is truly legal (doesn't leave own king in check)
  func isMoveLegal(board : [?T.Piece], from : Nat, to : Nat, color : T.Color, promotion : ?T.PieceType, enPassantSq : ?Nat) : Bool {
    let newBoard = applyMoveRaw(board, from, to, promotion, enPassantSq);
    not isInCheck(newBoard, color);
  };

  // Generate all legal moves for a color (used for checkmate/stalemate detection)
  public func hasLegalMoves(game : T.Game, color : T.Color) : Bool {
    let board = game.board;
    for (from in Iter.range(0, 63)) {
      switch (board[from]) {
        case (?p) {
          if (colorEq(p.color, color)) {
            // Generate pseudo-legal moves for this piece
            let moves = pseudoLegalMoves(board, from, p, game.enPassantSquare, game);
            for (to in moves.vals()) {
              let promo = if (pieceTypeEq(p.pieceType, #pawn)) {
                let toRank = rankOf(to);
                if ((colorEq(p.color, #white) and toRank == 7) or (colorEq(p.color, #black) and toRank == 0)) {
                  ?#queen; // just check queen promotion for legality
                } else {
                  null;
                };
              } else {
                null;
              };
              if (isMoveLegal(board, from, to, color, promo, game.enPassantSquare)) {
                return true;
              };
            };
          };
        };
        case null {};
      };
    };
    false;
  };

  // Generate pseudo-legal target squares for a piece
  func pseudoLegalMoves(board : [?T.Piece], from : Nat, piece : T.Piece, enPassantSq : ?Nat, game : T.Game) : [Nat] {
    let buf = Buffer.Buffer<Nat>(16);
    let f : Int = fileOf(from);
    let r : Int = rankOf(from);

    switch (piece.pieceType) {
      case (#pawn) {
        let dir : Int = switch (piece.color) { case (#white) 1; case (#black) -1 };
        let startRank : Int = switch (piece.color) { case (#white) 1; case (#black) 6 };

        // Forward one
        let fwd = r + dir;
        if (onBoard(f, fwd)) {
          let fwdSq = toSquare(Int.abs(f), Int.abs(fwd));
          if (Option.isNull(board[fwdSq])) {
            buf.add(fwdSq);
            // Forward two from start
            if (r == startRank) {
              let fwd2 = r + dir * 2;
              let fwd2Sq = toSquare(Int.abs(f), Int.abs(fwd2));
              if (Option.isNull(board[fwd2Sq])) {
                buf.add(fwd2Sq);
              };
            };
          };
        };

        // Captures (diagonal)
        for (df in [-1, 1].vals()) {
          let cf = f + df;
          let cr = r + dir;
          if (onBoard(cf, cr)) {
            let csq = toSquare(Int.abs(cf), Int.abs(cr));
            switch (board[csq]) {
              case (?target) {
                if (not colorEq(target.color, piece.color)) buf.add(csq);
              };
              case null {
                // En passant
                switch (enPassantSq) {
                  case (?epSq) { if (csq == epSq) buf.add(csq) };
                  case null {};
                };
              };
            };
          };
        };
      };

      case (#knight) {
        let offsets : [(Int, Int)] = [
          (-2, -1), (-2, 1), (-1, -2), (-1, 2),
          (1, -2), (1, 2), (2, -1), (2, 1)
        ];
        for ((df, dr) in offsets.vals()) {
          let nf = f + df;
          let nr = r + dr;
          if (onBoard(nf, nr)) {
            let nsq = toSquare(Int.abs(nf), Int.abs(nr));
            switch (board[nsq]) {
              case (?target) { if (not colorEq(target.color, piece.color)) buf.add(nsq) };
              case null { buf.add(nsq) };
            };
          };
        };
      };

      case (#king) {
        for (df in [-1, 0, 1].vals()) {
          for (dr in [-1, 0, 1].vals()) {
            if (df != 0 or dr != 0) {
              let kf = f + df;
              let kr = r + dr;
              if (onBoard(kf, kr)) {
                let ksq = toSquare(Int.abs(kf), Int.abs(kr));
                switch (board[ksq]) {
                  case (?target) { if (not colorEq(target.color, piece.color)) buf.add(ksq) };
                  case null { buf.add(ksq) };
                };
              };
            };
          };
        };
        // Castling
        let castleRank : Nat = switch (piece.color) { case (#white) 0; case (#black) 7 };
        if (rankOf(from) == castleRank and fileOf(from) == 4) {
          let canCK = switch (piece.color) { case (#white) game.whiteCanCastleKing; case (#black) game.blackCanCastleKing };
          let canCQ = switch (piece.color) { case (#white) game.whiteCanCastleQueen; case (#black) game.blackCanCastleQueen };
          let enemy = oppositeColor(piece.color);

          if (canCK) {
            // Kingside: f1/f8 and g1/g8 must be empty, king not in check, king doesn't pass through check
            let f1 = toSquare(5, castleRank);
            let g1 = toSquare(6, castleRank);
            if (Option.isNull(board[f1]) and Option.isNull(board[g1])) {
              if (not isSquareAttacked(board, from, enemy) and
                  not isSquareAttacked(board, f1, enemy) and
                  not isSquareAttacked(board, g1, enemy)) {
                buf.add(g1);
              };
            };
          };
          if (canCQ) {
            // Queenside: b1/b8, c1/c8, d1/d8 must be empty
            let b1 = toSquare(1, castleRank);
            let c1 = toSquare(2, castleRank);
            let d1 = toSquare(3, castleRank);
            if (Option.isNull(board[b1]) and Option.isNull(board[c1]) and Option.isNull(board[d1])) {
              if (not isSquareAttacked(board, from, enemy) and
                  not isSquareAttacked(board, d1, enemy) and
                  not isSquareAttacked(board, c1, enemy)) {
                buf.add(c1);
              };
            };
          };
        };
      };

      case (#rook) {
        addSlidingMoves(board, from, piece.color, [(0,1),(0,-1),(1,0),(-1,0)], buf);
      };

      case (#bishop) {
        addSlidingMoves(board, from, piece.color, [(1,1),(1,-1),(-1,1),(-1,-1)], buf);
      };

      case (#queen) {
        addSlidingMoves(board, from, piece.color, [(0,1),(0,-1),(1,0),(-1,0),(1,1),(1,-1),(-1,1),(-1,-1)], buf);
      };
    };

    Buffer.toArray(buf);
  };

  func addSlidingMoves(board : [?T.Piece], from : Nat, color : T.Color, dirs : [(Int, Int)], buf : Buffer.Buffer<Nat>) {
    let f : Int = fileOf(from);
    let r : Int = rankOf(from);
    for ((df, dr) in dirs.vals()) {
      var dist : Int = 1;
      label slideLoop while (true) {
        let nf = f + df * dist;
        let nr = r + dr * dist;
        if (not onBoard(nf, nr)) break slideLoop;
        let nsq = toSquare(Int.abs(nf), Int.abs(nr));
        switch (board[nsq]) {
          case (?target) {
            if (not colorEq(target.color, color)) buf.add(nsq); // capture
            break slideLoop;
          };
          case null { buf.add(nsq) };
        };
        dist += 1;
      };
    };
  };

  // ========== VALIDATE & EXECUTE MOVE ==========

  public func validateAndExecuteMove(game : T.Game, from : Nat, to : Nat, promotion : ?T.PieceType) : Result.Result<T.Game, Text> {
    let board = game.board;

    // 1. Check piece exists at source
    let piece = switch (board[from]) {
      case (?p) p;
      case null return #err("No piece at " # squareToAlgebraic(from));
    };

    // 2. Check piece belongs to current player
    if (not colorEq(piece.color, game.turn)) {
      return #err("That's not your piece");
    };

    // 3. Check target is not own piece
    switch (board[to]) {
      case (?target) {
        if (colorEq(target.color, piece.color)) {
          return #err("Cannot capture your own piece");
        };
      };
      case null {};
    };

    // 4. Check pseudo-legality
    let legalTargets = pseudoLegalMoves(board, from, piece, game.enPassantSquare, game);
    var found = false;
    for (t in legalTargets.vals()) {
      if (t == to) { found := true };
    };
    if (not found) {
      return #err("Illegal move: " # squareToAlgebraic(from) # squareToAlgebraic(to));
    };

    // 5. Check promotion requirements
    let isPromotion = pieceTypeEq(piece.pieceType, #pawn) and (
      (colorEq(piece.color, #white) and rankOf(to) == 7) or
      (colorEq(piece.color, #black) and rankOf(to) == 0)
    );
    if (isPromotion and Option.isNull(promotion)) {
      return #err("Pawn promotion requires a piece. Add q, r, b, or n to your move (e.g., e7e8q)");
    };
    if (not isPromotion and not Option.isNull(promotion)) {
      return #err("Cannot promote: this is not a promotion move");
    };

    // 6. Detect special moves
    let isEnPassant = pieceTypeEq(piece.pieceType, #pawn) and (
      switch (game.enPassantSquare) {
        case (?epSq) to == epSq;
        case null false;
      }
    );
    let castleDiff : Int = Int.abs(to) - Int.abs(from);
    let isCastle = pieceTypeEq(piece.pieceType, #king) and (castleDiff == 2 or castleDiff == -2);
    let captured : ?T.PieceType = if (isEnPassant) {
      ?#pawn;
    } else {
      switch (board[to]) {
        case (?target) ?target.pieceType;
        case null null;
      };
    };

    // 7. Apply the move
    let newBoard = applyMoveRaw(board, from, to, promotion, game.enPassantSquare);

    // 8. Check if move leaves own king in check (illegal)
    if (isInCheck(newBoard, game.turn)) {
      return #err("Illegal move: would leave your king in check");
    };

    // 9. Update castling rights
    var wCK = game.whiteCanCastleKing;
    var wCQ = game.whiteCanCastleQueen;
    var bCK = game.blackCanCastleKing;
    var bCQ = game.blackCanCastleQueen;

    if (pieceTypeEq(piece.pieceType, #king)) {
      if (colorEq(piece.color, #white)) { wCK := false; wCQ := false };
      if (colorEq(piece.color, #black)) { bCK := false; bCQ := false };
    };
    if (pieceTypeEq(piece.pieceType, #rook)) {
      if (from == 0) wCQ := false;   // a1
      if (from == 7) wCK := false;   // h1
      if (from == 56) bCQ := false;  // a8
      if (from == 63) bCK := false;  // h8
    };
    // Also if rook is captured
    if (to == 0) wCQ := false;
    if (to == 7) wCK := false;
    if (to == 56) bCQ := false;
    if (to == 63) bCK := false;

    // 10. Update en passant square
    var newEnPassant : ?Nat = null;
    if (pieceTypeEq(piece.pieceType, #pawn)) {
      let rankDiff : Int = Int.abs(rankOf(to)) - Int.abs(rankOf(from));
      if (rankDiff == 2 or rankDiff == -2) {
        // Double pawn push - set en passant square
        newEnPassant := ?toSquare(fileOf(from), (rankOf(from) + rankOf(to)) / 2);
      };
    };

    // 11. Update half-move clock
    let newHalfMoveClock = if (pieceTypeEq(piece.pieceType, #pawn) or not Option.isNull(captured)) {
      0;
    } else {
      game.halfMoveClock + 1;
    };

    // 12. Update full move number
    let newFullMoveNumber = if (colorEq(game.turn, #black)) {
      game.fullMoveNumber + 1;
    } else {
      game.fullMoveNumber;
    };

    // 13. Build move notation
    let notation = squareToAlgebraic(from) # squareToAlgebraic(to) # (
      switch (promotion) {
        case (?#queen) "q";
        case (?#rook) "r";
        case (?#bishop) "b";
        case (?#knight) "n";
        case _ "";
      }
    );

    let nextTurn = oppositeColor(game.turn);

    // 14. Check if opponent is in check after this move
    let opponentInCheck = isInCheck(newBoard, nextTurn);

    // 15. Build the move record
    let moveRecord : T.Move = {
      from;
      to;
      piece = piece.pieceType;
      captured;
      promotion;
      isCheck = opponentInCheck;
      isCastle;
      isEnPassant;
      notation;
      moveNumber = game.fullMoveNumber;
    };

    // 16. Build updated game state (status will be determined next)
    let updatedGame : T.Game = {
      id = game.id;
      white = game.white;
      black = game.black;
      board = newBoard;
      moves = Array.append(game.moves, [moveRecord]);
      status = #active; // will be updated below
      turn = nextTurn;
      winner = null;
      whiteCanCastleKing = wCK;
      whiteCanCastleQueen = wCQ;
      blackCanCastleKing = bCK;
      blackCanCastleQueen = bCQ;
      enPassantSquare = newEnPassant;
      halfMoveClock = newHalfMoveClock;
      fullMoveNumber = newFullMoveNumber;
      createdAt = game.createdAt;
      updatedAt = Int.abs(Time.now());
      drawOffer = null; // clear any draw offer on move
    };

    // 17. Check for checkmate, stalemate, draw
    let opponentHasMoves = hasLegalMoves(updatedGame, nextTurn);

    let (finalStatus, finalWinner) = if (not opponentHasMoves) {
      if (opponentInCheck) {
        (#checkmate, ?game.turn); // current player wins
      } else {
        (#stalemate, null); // draw
      };
    } else if (newHalfMoveClock >= 100) {
      (#draw, null); // 50-move rule
    } else if (isInsufficientMaterial(newBoard)) {
      (#draw, null);
    } else {
      (#active, null);
    };

    #ok({
      updatedGame with
      status = finalStatus;
      winner = finalWinner;
    });
  };

  // ========== INSUFFICIENT MATERIAL ==========

  public func isInsufficientMaterial(board : [?T.Piece]) : Bool {
    var whitePieces = Buffer.Buffer<T.PieceType>(4);
    var blackPieces = Buffer.Buffer<T.PieceType>(4);

    for (i in Iter.range(0, 63)) {
      switch (board[i]) {
        case (?p) {
          if (colorEq(p.color, #white)) whitePieces.add(p.pieceType)
          else blackPieces.add(p.pieceType);
        };
        case null {};
      };
    };

    let wCount = whitePieces.size();
    let bCount = blackPieces.size();

    // K vs K
    if (wCount == 1 and bCount == 1) return true;

    // K+B vs K or K+N vs K
    if (wCount == 1 and bCount == 2) {
      for (pt in blackPieces.vals()) {
        if (pieceTypeEq(pt, #bishop) or pieceTypeEq(pt, #knight)) return true;
      };
    };
    if (wCount == 2 and bCount == 1) {
      for (pt in whitePieces.vals()) {
        if (pieceTypeEq(pt, #bishop) or pieceTypeEq(pt, #knight)) return true;
      };
    };

    false;
  };

  // ========== ELO CALCULATION ==========

  public func calculateEloChange(winnerElo : Int, loserElo : Int) : (Int, Int) {
    // K-factor = 32
    let k : Int = 32;
    // Expected scores (simplified integer math)
    // E_winner = 1 / (1 + 10^((loserElo - winnerElo) / 400))
    // We'll use a simplified approach
    let diff = loserElo - winnerElo;
    let change = if (diff > 400) { k * 15 / 16 } // ~0.94 expected
    else if (diff > 200) { k * 3 / 4 } // ~0.76 expected
    else if (diff > 0) { k * 5 / 8 } // ~0.64 expected
    else if (diff > -200) { k / 2 } // ~0.5 expected
    else if (diff > -400) { k * 3 / 8 } // ~0.36 expected
    else { k / 4 }; // ~0.24 expected

    (change, -change); // winner gains, loser loses
  };

  public func calculateEloChangeDraw(elo1 : Int, elo2 : Int) : (Int, Int) {
    let diff = elo2 - elo1;
    let change = if (diff > 200) { 8 }
    else if (diff > 0) { 4 }
    else if (diff > -200) { 0 }
    else { -4 };
    (change, -change);
  };

  // ========== STATUS HELPERS ==========

  public func statusToText(s : T.GameStatus) : Text {
    switch (s) {
      case (#waiting) "waiting";
      case (#active) "active";
      case (#checkmate) "checkmate";
      case (#stalemate) "stalemate";
      case (#draw) "draw";
      case (#resigned) "resigned";
    };
  };

  public func colorToText(c : T.Color) : Text {
    switch (c) { case (#white) "white"; case (#black) "black" };
  };

  public func pieceTypeToText(pt : T.PieceType) : Text {
    switch (pt) {
      case (#king) "king";
      case (#queen) "queen";
      case (#rook) "rook";
      case (#bishop) "bishop";
      case (#knight) "knight";
      case (#pawn) "pawn";
    };
  };

  public func isGameOver(status : T.GameStatus) : Bool {
    switch (status) {
      case (#checkmate) true;
      case (#stalemate) true;
      case (#draw) true;
      case (#resigned) true;
      case _ false;
    };
  };

  // ========== MOVE HISTORY RENDERING ==========

  public func renderMoveHistory(moves : [T.Move]) : Text {
    if (moves.size() == 0) return "No moves yet.";
    var result = "";
    var i = 0;
    while (i < moves.size()) {
      let moveNum = i / 2 + 1;
      if (i % 2 == 0) {
        result #= Nat.toText(moveNum) # ". " # moves[i].notation;
      } else {
        result #= " " # moves[i].notation # " ";
      };
      i += 1;
    };
    result;
  };
};
