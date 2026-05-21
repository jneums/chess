import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Buffer "mo:base/Buffer";

import ToolContext "ToolContext";
import T "../ChessTypes";
import Engine "../ChessEngine";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_list_games";
    title = ?"List Games";
    description = ?"List chess games filtered by status: 'waiting', 'active', 'completed', or 'all' (default).";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("status", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("Filter: 'waiting', 'active', 'completed', or 'all' (default)")),
          ("enum", Json.arr([Json.str("waiting"), Json.str("active"), Json.str("completed"), Json.str("all")])),
        ])),
      ])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("games", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("object"))])),
        ])),
        ("total", Json.obj([("type", Json.str("integer"))])),
      ])),
    ]);
  };

  func matchesFilter(status : T.GameStatus, filter : Text) : Bool {
    switch (filter) {
      case ("waiting") {
        switch (status) { case (#waiting) true; case _ false };
      };
      case ("active") {
        switch (status) { case (#active) true; case _ false };
      };
      case ("completed") {
        Engine.isGameOver(status);
      };
      case _ true; // "all"
    };
  };

  public func handle(ctx : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
      let filter = switch (Result.toOption(Json.getAsText(args, "status"))) {
        case (?s) s;
        case null "all";
      };

      let allGames = ctx.getAllGames();
      let gamesBuf = Buffer.Buffer<Json.Json>(allGames.size());

      for (game in allGames.vals()) {
        if (matchesFilter(game.status, filter)) {
          let blackText = switch (game.black) {
            case (?b) Principal.toText(b);
            case null "waiting";
          };
          let winnerText = switch (game.winner) {
            case (?c) Engine.colorToText(c);
            case null "none";
          };
          gamesBuf.add(Json.obj([
            ("gameId", Json.str(game.id)),
            ("white", Json.str(Principal.toText(game.white))),
            ("black", Json.str(blackText)),
            ("status", Json.str(Engine.statusToText(game.status))),
            ("turn", Json.str(Engine.colorToText(game.turn))),
            ("moveCount", Json.int(game.moves.size())),
            ("winner", Json.str(winnerText)),
          ]));
        };
      };

      let gamesArr = Buffer.toArray(gamesBuf);

      let result = Json.obj([
        ("games", Json.arr(gamesArr)),
        ("total", Json.int(gamesArr.size())),
        ("filter", Json.str(filter)),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };
};
