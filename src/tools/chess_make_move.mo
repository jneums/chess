import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Principal "mo:base/Principal";
import Option "mo:base/Option";

import ToolContext "ToolContext";
import T "../ChessTypes";
import Engine "../ChessEngine";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_make_move";
    title = ?"Make Move";
    description = ?"Make a chess move using coordinate notation (e.g., 'e2e4', 'e7e8q' for promotion). Must be your turn.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The game ID")),
        ])),
        ("move", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("Move in coordinate notation, e.g. 'e2e4', 'g1f3', 'e7e8q' (promotion)")),
        ])),
      ])),
      ("required", Json.arr([Json.str("gameId"), Json.str("move")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([("type", Json.str("string"))])),
        ("move", Json.obj([("type", Json.str("string"))])),
        ("board", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("turn", Json.obj([("type", Json.str("string"))])),
        ("isCheck", Json.obj([("type", Json.str("boolean"))])),
        ("moveHistory", Json.obj([("type", Json.str("string"))])),
        ("message", Json.obj([("type", Json.str("string"))])),
      ])),
    ]);
  };

  public func handle(ctx : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
      let caller = switch (ToolContext.getCaller(auth)) {
        case (?p) p;
        case null return ToolContext.makeError("Authentication required.", cb);
      };

      let gameId = switch (Result.toOption(Json.getAsText(args, "gameId"))) {
        case (?id) id;
        case null return ToolContext.makeError("Missing 'gameId' parameter.", cb);
      };

      let moveStr = switch (Result.toOption(Json.getAsText(args, "move"))) {
        case (?m) m;
        case null return ToolContext.makeError("Missing 'move' parameter.", cb);
      };

      let game = switch (ctx.getGame(gameId)) {
        case (?g) g;
        case null return ToolContext.makeError("Game '" # gameId # "' not found.", cb);
      };

      // Check game is active
      switch (game.status) {
        case (#active) {};
        case _ return ToolContext.makeError("Game is not active. Status: " # Engine.statusToText(game.status), cb);
      };

      // Check it's caller's turn
      let isWhite = Principal.equal(caller, game.white);
      let isBlack = switch (game.black) {
        case (?b) Principal.equal(caller, b);
        case null false;
      };

      if (not isWhite and not isBlack) {
        return ToolContext.makeError("You are not a player in this game.", cb);
      };

      let callerColor : T.Color = if (isWhite) #white else #black;
      if (not Engine.colorEq(callerColor, game.turn)) {
        return ToolContext.makeError("It's not your turn. It's " # Engine.colorToText(game.turn) # "'s turn.", cb);
      };

      // Parse the move
      let parsed = switch (Engine.parseMove(moveStr)) {
        case (#ok(m)) m;
        case (#err(e)) return ToolContext.makeError(e, cb);
      };

      // Validate and execute
      let updatedGame = switch (Engine.validateAndExecuteMove(game, parsed.from, parsed.to, parsed.promotion)) {
        case (#ok(g)) g;
        case (#err(e)) return ToolContext.makeError(e, cb);
      };

      ctx.putGame(gameId, updatedGame);

      // Update leaderboard if game is over
      if (Engine.isGameOver(updatedGame.status)) {
        _updateLeaderboard(ctx, updatedGame);
      };

      // Build response
      let lastMove = updatedGame.moves[updatedGame.moves.size() - 1];
      let isCheck = lastMove.isCheck;

      let message = if (Engine.isGameOver(updatedGame.status)) {
        switch (updatedGame.status) {
          case (#checkmate) "Checkmate! " # Engine.colorToText(Engine.oppositeColor(updatedGame.turn)) # " wins!";
          case (#stalemate) "Stalemate! The game is a draw.";
          case (#draw) "Draw by " # (if (updatedGame.halfMoveClock >= 100) "50-move rule" else "insufficient material") # ".";
          case _ "Game over.";
        };
      } else if (isCheck) {
        "Check! " # Engine.colorToText(updatedGame.turn) # " to move.";
      } else {
        Engine.colorToText(updatedGame.turn) # " to move.";
      };

      let result = Json.obj([
        ("gameId", Json.str(gameId)),
        ("move", Json.str(lastMove.notation)),
        ("board", Json.str(Engine.renderBoard(updatedGame.board))),
        ("status", Json.str(Engine.statusToText(updatedGame.status))),
        ("turn", Json.str(Engine.colorToText(updatedGame.turn))),
        ("isCheck", Json.bool(isCheck)),
        ("moveHistory", Json.str(Engine.renderMoveHistory(updatedGame.moves))),
        ("message", Json.str(message)),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };

  func _updateLeaderboard(ctx : ToolContext.ToolContext, game : T.Game) {
    let blackPrincipal = switch (game.black) {
      case (?b) b;
      case null return;
    };

    let defaultWhite : T.PlayerStats = {
      principal = game.white; wins = 0; losses = 0; draws = 0; elo = 1200; gamesPlayed = 0;
    };
    let defaultBlack : T.PlayerStats = {
      principal = blackPrincipal; wins = 0; losses = 0; draws = 0; elo = 1200; gamesPlayed = 0;
    };

    let whiteStats = Option.get(ctx.getPlayerStats(game.white), defaultWhite);
    let blackStats = Option.get(ctx.getPlayerStats(blackPrincipal), defaultBlack);

    switch (game.winner) {
      case (?#white) {
        let (wChange, bChange) = Engine.calculateEloChange(whiteStats.elo, blackStats.elo);
        ctx.updatePlayerStats(game.white, {
          whiteStats with
          wins = whiteStats.wins + 1;
          gamesPlayed = whiteStats.gamesPlayed + 1;
          elo = whiteStats.elo + wChange;
        });
        ctx.updatePlayerStats(blackPrincipal, {
          blackStats with
          losses = blackStats.losses + 1;
          gamesPlayed = blackStats.gamesPlayed + 1;
          elo = blackStats.elo + bChange;
        });
      };
      case (?#black) {
        let (bChange, wChange) = Engine.calculateEloChange(blackStats.elo, whiteStats.elo);
        ctx.updatePlayerStats(blackPrincipal, {
          blackStats with
          wins = blackStats.wins + 1;
          gamesPlayed = blackStats.gamesPlayed + 1;
          elo = blackStats.elo + bChange;
        });
        ctx.updatePlayerStats(game.white, {
          whiteStats with
          losses = whiteStats.losses + 1;
          gamesPlayed = whiteStats.gamesPlayed + 1;
          elo = whiteStats.elo + wChange;
        });
      };
      case null {
        // Draw
        let (w1Change, w2Change) = Engine.calculateEloChangeDraw(whiteStats.elo, blackStats.elo);
        ctx.updatePlayerStats(game.white, {
          whiteStats with
          draws = whiteStats.draws + 1;
          gamesPlayed = whiteStats.gamesPlayed + 1;
          elo = whiteStats.elo + w1Change;
        });
        ctx.updatePlayerStats(blackPrincipal, {
          blackStats with
          draws = blackStats.draws + 1;
          gamesPlayed = blackStats.gamesPlayed + 1;
          elo = blackStats.elo + w2Change;
        });
      };
    };
  };
};
