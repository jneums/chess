import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Int "mo:base/Int";
import Time "mo:base/Time";

import ToolContext "ToolContext";
import T "../ChessTypes";
import Engine "../ChessEngine";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_create_game";
    title = ?"Create Chess Game";
    description = ?"Create a new chess game. You will play as white. Another player can join as black.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("gameId", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("board", Json.obj([("type", Json.str("string"))])),
        ("message", Json.obj([("type", Json.str("string"))])),
      ])),
    ]);
  };

  public func handle(ctx : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(_args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
      let caller = switch (ToolContext.getCaller(auth)) {
        case (?p) p;
        case null return ToolContext.makeError("Authentication required. You must be logged in to create a game.", cb);
      };

      let gameId = ctx.nextGameId();
      let board = Engine.initialBoard();
      let now = Int.abs(Time.now());

      let game : T.Game = {
        id = gameId;
        white = caller;
        black = null;
        board = board;
        moves = [];
        status = #waiting;
        turn = #white;
        winner = null;
        whiteCanCastleKing = true;
        whiteCanCastleQueen = true;
        blackCanCastleKing = true;
        blackCanCastleQueen = true;
        enPassantSquare = null;
        halfMoveClock = 0;
        fullMoveNumber = 1;
        createdAt = now;
        updatedAt = now;
        drawOffer = null;
      };

      ctx.putGame(gameId, game);

      let result = Json.obj([
        ("gameId", Json.str(gameId)),
        ("status", Json.str("waiting")),
        ("board", Json.str(Engine.renderBoard(board))),
        ("message", Json.str("Game created! You are playing as white. Share game ID '" # gameId # "' for someone to join as black.")),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };
};
