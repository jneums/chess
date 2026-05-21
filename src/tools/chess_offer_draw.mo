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
    name = "chess_offer_draw";
    title = ?"Offer Draw";
    description = ?"Offer a draw to your opponent, or accept an existing draw offer.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The game ID")),
        ])),
      ])),
      ("required", Json.arr([Json.str("gameId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
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
        case _ return ToolContext.makeError("Game is not active.", cb);
      };

      let isWhite = Principal.equal(caller, game.white);
      let isBlack = switch (game.black) {
        case (?b) Principal.equal(caller, b);
        case null false;
      };

      if (not isWhite and not isBlack) {
        return ToolContext.makeError("You are not a player in this game.", cb);
      };

      let callerColor : T.Color = if (isWhite) #white else #black;

      switch (game.drawOffer) {
        case (?offerColor) {
          // There's an existing draw offer
          if (Engine.colorEq(offerColor, callerColor)) {
            // Caller already offered
            return ToolContext.makeSuccess(Json.obj([
              ("gameId", Json.str(gameId)),
              ("status", Json.str("active")),
              ("message", Json.str("You already offered a draw. Waiting for your opponent to respond.")),
            ]), cb);
          } else {
            // Opponent offered, caller accepts
            let updatedGame = {
              game with
              status = #draw;
              updatedAt = Int.abs(Time.now());
              drawOffer = null;
            };

            ctx.putGame(gameId, updatedGame);

            // Update leaderboard
            let blackPrincipal = switch (game.black) {
              case (?b) b;
              case null return ToolContext.makeError("No black player.", cb);
            };
            let defaultWhite : T.PlayerStats = { principal = game.white; wins = 0; losses = 0; draws = 0; elo = 1200; gamesPlayed = 0 };
            let defaultBlack : T.PlayerStats = { principal = blackPrincipal; wins = 0; losses = 0; draws = 0; elo = 1200; gamesPlayed = 0 };
            let whiteStats = Option.get(ctx.getPlayerStats(game.white), defaultWhite);
            let blackStats = Option.get(ctx.getPlayerStats(blackPrincipal), defaultBlack);
            let (w1Change, w2Change) = Engine.calculateEloChangeDraw(whiteStats.elo, blackStats.elo);
            ctx.updatePlayerStats(game.white, { whiteStats with draws = whiteStats.draws + 1; gamesPlayed = whiteStats.gamesPlayed + 1; elo = whiteStats.elo + w1Change });
            ctx.updatePlayerStats(blackPrincipal, { blackStats with draws = blackStats.draws + 1; gamesPlayed = blackStats.gamesPlayed + 1; elo = blackStats.elo + w2Change });

            return ToolContext.makeSuccess(Json.obj([
              ("gameId", Json.str(gameId)),
              ("status", Json.str("draw")),
              ("message", Json.str("Draw accepted! The game ends in a draw.")),
            ]), cb);
          };
        };
        case null {
          // No draw offer pending — create one
          let updatedGame = {
            game with
            drawOffer = ?callerColor;
            updatedAt = Int.abs(Time.now());
          };

          ctx.putGame(gameId, updatedGame);

          return ToolContext.makeSuccess(Json.obj([
            ("gameId", Json.str(gameId)),
            ("status", Json.str("active")),
            ("message", Json.str("Draw offered. Waiting for your opponent to accept or continue playing.")),
          ]), cb);
        };
      };
    };
  };
};
