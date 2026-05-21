import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Int "mo:base/Int";
import Time "mo:base/Time";
import Principal "mo:base/Principal";

import ToolContext "ToolContext";
import Engine "../ChessEngine";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_join_game";
    title = ?"Join Chess Game";
    description = ?"Join an existing chess game as black.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The ID of the game to join")),
        ])),
      ])),
      ("required", Json.arr([Json.str("gameId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([("type", Json.str("string"))])),
        ("white", Json.obj([("type", Json.str("string"))])),
        ("black", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("board", Json.obj([("type", Json.str("string"))])),
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
        case (#waiting) {};
        case _ return ToolContext.makeError("Game is not open for joining. Status: " # Engine.statusToText(game.status), cb);
      };

      if (Principal.equal(caller, game.white)) {
        return ToolContext.makeError("You cannot join your own game.", cb);
      };

      let updatedGame = {
        game with
        black = ?caller;
        status = #active;
        updatedAt = Int.abs(Time.now());
      };

      ctx.putGame(gameId, updatedGame);

      let result = Json.obj([
        ("gameId", Json.str(gameId)),
        ("white", Json.str(Principal.toText(game.white))),
        ("black", Json.str(Principal.toText(caller))),
        ("status", Json.str("active")),
        ("board", Json.str(Engine.renderBoard(game.board))),
        ("message", Json.str("You joined as black! White moves first.")),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };
};
