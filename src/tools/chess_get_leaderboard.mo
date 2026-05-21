import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "chess_get_leaderboard";
    title = ?"Leaderboard";
    description = ?"Get the chess leaderboard ranked by ELO rating.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("limit", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Max entries to return (default: 20, max: 50)")),
        ])),
      ])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("players", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("object"))])),
        ])),
        ("total", Json.obj([("type", Json.str("integer"))])),
      ])),
    ]);
  };

  public func handle(ctx : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
      let limit = switch (Result.toOption(Json.getAsNat(args, "limit"))) {
        case (?n) if (n > 50) 50 else if (n == 0) 20 else n;
        case null 20;
      };

      let allStats = ctx.getAllPlayerStats();

      // Sort by ELO descending
      let sorted = Array.sort(allStats, func(a : { elo : Int; principal : Principal.Principal; wins : Nat; losses : Nat; draws : Nat; gamesPlayed : Nat }, b : { elo : Int; principal : Principal.Principal; wins : Nat; losses : Nat; draws : Nat; gamesPlayed : Nat }) : { #less; #equal; #greater } {
        if (a.elo > b.elo) #less
        else if (a.elo < b.elo) #greater
        else #equal;
      });

      let playersBuf = Buffer.Buffer<Json.Json>(limit);
      var count = 0;
      for (stats in sorted.vals()) {
        if (count >= limit) return;
        playersBuf.add(Json.obj([
          ("rank", Json.int(count + 1)),
          ("principal", Json.str(Principal.toText(stats.principal))),
          ("elo", Json.int(Int.abs(stats.elo))),
          ("wins", Json.int(stats.wins)),
          ("losses", Json.int(stats.losses)),
          ("draws", Json.int(stats.draws)),
          ("gamesPlayed", Json.int(stats.gamesPlayed)),
        ]));
        count += 1;
      };

      let result = Json.obj([
        ("players", Json.arr(Buffer.toArray(playersBuf))),
        ("total", Json.int(allStats.size())),
      ]);

      ToolContext.makeSuccess(result, cb);
    };
  };
};
