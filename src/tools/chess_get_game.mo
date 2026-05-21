import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";

import ToolContext "ToolContext";
import Engine "../ChessEngine";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_get_game";
    title = ?"Get Game State";
    description = ?"Get the full state of a chess game including board, move history, and status.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The game ID to inspect")),
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
        ("board", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("turn", Json.obj([("type", Json.str("string"))])),
        ("moveCount", Json.obj([("type", Json.str("integer"))])),
        ("moveHistory", Json.obj([("type", Json.str("string"))])),
        ("winner", Json.obj([("type", Json.str("string"))])),
      ])),
    ]);
  };

  public func handle(ctx : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
      let gameId = switch (Result.toOption(Json.getAsText(args, "gameId"))) {
        case (?id) id;
        case null return ToolContext.makeError("Missing 'gameId' parameter.", cb);
      };

      let game = switch (ctx.getGame(gameId)) {
        case (?g) g;
        case null return ToolContext.makeError("Game '" # gameId # "' not found.", cb);
      };

      let blackText = switch (game.black) {
        case (?b) Principal.toText(b);
        case null "waiting for opponent";
      };

      let winnerText = switch (game.winner) {
        case (?c) Engine.colorToText(c);
        case null "none";
      };

      let result = Json.obj([
        ("gameId", Json.str(gameId)),
        ("white", Json.str(Principal.toText(game.white))),
        ("black", Json.str(blackText)),
        ("board", Json.str(Engine.renderBoard(game.board))),
        ("status", Json.str(Engine.statusToText(game.status))),
        ("turn", Json.str(Engine.colorToText(game.turn))),
        ("moveCount", Json.int(game.moves.size())),
        ("moveHistory", Json.str(Engine.renderMoveHistory(game.moves))),
        ("winner", Json.str(winnerText)),
        ("halfMoveClock", Json.int(game.halfMoveClock)),
        ("fullMoveNumber", Json.int(game.fullMoveNumber)),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };
};
