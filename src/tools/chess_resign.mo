import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Int "mo:base/Int";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Option "mo:base/Option";

import ToolContext "ToolContext";
import T "../ChessTypes";
import Engine "../ChessEngine";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_resign";
    title = ?"Resign";
    description = ?"Resign from an active chess game. Your opponent wins.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The game ID to resign from")),
        ])),
      ])),
      ("required", Json.arr([Json.str("gameId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([("type", Json.str("string"))])),
        ("winner", Json.obj([("type", Json.str("string"))])),
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

      let game = switch (ctx.getGame(gameId)) {
        case (?g) g;
        case null return ToolContext.makeError("Game '" # gameId # "' not found.", cb);
      };

      switch (game.status) {
        case (#active) {};
        case _ return ToolContext.makeError("Game is not active. Status: " # Engine.statusToText(game.status), cb);
      };

      let isWhite = Principal.equal(caller, game.white);
      let isBlack = switch (game.black) {
        case (?b) Principal.equal(caller, b);
        case null false;
      };

      if (not isWhite and not isBlack) {
        return ToolContext.makeError("You are not a player in this game.", cb);
      };

      let winnerColor : T.Color = if (isWhite) #black else #white;

      let updatedGame = {
        game with
        status = #resigned;
        winner = ?winnerColor;
        updatedAt = Int.abs(Time.now());
      };

      ctx.putGame(gameId, updatedGame);

      // Update leaderboard
      let blackPrincipal = switch (game.black) {
        case (?b) b;
        case null return ToolContext.makeError("Game has no black player.", cb);
      };

      let defaultWhite : T.PlayerStats = {
        principal = game.white; wins = 0; losses = 0; draws = 0; elo = 1200; gamesPlayed = 0;
      };
      let defaultBlack : T.PlayerStats = {
        principal = blackPrincipal; wins = 0; losses = 0; draws = 0; elo = 1200; gamesPlayed = 0;
      };
      let whiteStats = Option.get(ctx.getPlayerStats(game.white), defaultWhite);
      let blackStats = Option.get(ctx.getPlayerStats(blackPrincipal), defaultBlack);

      switch (winnerColor) {
        case (#white) {
          let (wChange, bChange) = Engine.calculateEloChange(whiteStats.elo, blackStats.elo);
          ctx.updatePlayerStats(game.white, { whiteStats with wins = whiteStats.wins + 1; gamesPlayed = whiteStats.gamesPlayed + 1; elo = whiteStats.elo + wChange });
          ctx.updatePlayerStats(blackPrincipal, { blackStats with losses = blackStats.losses + 1; gamesPlayed = blackStats.gamesPlayed + 1; elo = blackStats.elo + bChange });
        };
        case (#black) {
          let (bChange, wChange) = Engine.calculateEloChange(blackStats.elo, whiteStats.elo);
          ctx.updatePlayerStats(blackPrincipal, { blackStats with wins = blackStats.wins + 1; gamesPlayed = blackStats.gamesPlayed + 1; elo = blackStats.elo + bChange });
          ctx.updatePlayerStats(game.white, { whiteStats with losses = whiteStats.losses + 1; gamesPlayed = whiteStats.gamesPlayed + 1; elo = whiteStats.elo + wChange });
        };
      };

      let result = Json.obj([
        ("gameId", Json.str(gameId)),
        ("winner", Json.str(Engine.colorToText(winnerColor))),
        ("message", Json.str(Engine.colorToText(if (isWhite) #white else #black) # " resigned. " # Engine.colorToText(winnerColor) # " wins!")),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };
};
