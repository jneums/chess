import Principal "mo:base/Principal";
import Result "mo:base/Result";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";

import T "../ChessTypes";

module ToolContext {

  /// Context shared between tools and the main canister
  public type ToolContext = {
    canisterPrincipal : Principal;
    owner : Principal;
    appContext : McpTypes.AppContext;
    // Game state accessors
    getGame : (Text) -> ?T.Game;
    getAllGames : () -> [T.Game];
    getPlayerStats : (Principal) -> ?T.PlayerStats;
    getAllPlayerStats : () -> [T.PlayerStats];
    // Game state mutators
    putGame : (Text, T.Game) -> ();
    nextGameId : () -> Text;
    updatePlayerStats : (Principal, T.PlayerStats) -> ();
  };

  /// Helper: extract caller principal from auth info
  public func getCaller(auth : ?AuthTypes.AuthInfo) : ?Principal {
    switch (auth) {
      case (?a) ?a.principal;
      case null null;
    };
  };

  /// Helper function to create an error response
  public func makeError(message : Text, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = "Error: " # message })]; isError = true; structuredContent = null }));
  };

  /// Helper function to create a success response with structured JSON
  public func makeSuccess(structured : Json.Json, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = Json.stringify(structured, null) })]; isError = false; structuredContent = ?structured }));
  };

  /// Helper function to create a success response with plain text
  public func makeTextSuccess(text : Text, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = text })]; isError = false; structuredContent = null }));
  };
};
