import Result "mo:base/Result";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";

import HttpTypes "mo:http-types";
import Map "mo:map/Map";

import AuthCleanup "mo:mcp-motoko-sdk/auth/Cleanup";
import AuthState "mo:mcp-motoko-sdk/auth/State";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";

import Mcp "mo:mcp-motoko-sdk/mcp/Mcp";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import HttpHandler "mo:mcp-motoko-sdk/mcp/HttpHandler";
import Cleanup "mo:mcp-motoko-sdk/mcp/Cleanup";
import State "mo:mcp-motoko-sdk/mcp/State";
import Payments "mo:mcp-motoko-sdk/mcp/Payments";
import HttpAssets "mo:mcp-motoko-sdk/mcp/HttpAssets";
import Beacon "mo:mcp-motoko-sdk/mcp/Beacon";
import ApiKey "mo:mcp-motoko-sdk/auth/ApiKey";

import SrvTypes "mo:mcp-motoko-sdk/server/Types";
import IC "mo:ic";

// Import chess types and engine
import T "ChessTypes";

// Import tool modules
import ToolContext "tools/ToolContext";
import ChessCreateGame "tools/chess_create_game";
import ChessJoinGame "tools/chess_join_game";
import ChessMakeMove "tools/chess_make_move";
import ChessGetGame "tools/chess_get_game";
import ChessListGames "tools/chess_list_games";
import ChessResign "tools/chess_resign";
import ChessOfferDraw "tools/chess_offer_draw";
import ChessGetLeaderboard "tools/chess_get_leaderboard";

shared ({ caller = deployer }) persistent actor class McpServer(
  args : ?{
    owner : ?Principal;
  }
) = self {

  // The canister owner
  var owner : Principal = Option.get(do ? { args!.owner! }, deployer);

  // ========== GAME STATE ==========

  // Game storage
  var games : Map.Map<Text, T.Game> = Map.new<Text, T.Game>();
  var gameCounter : Nat = 0;

  // Player leaderboard
  var leaderboard : Map.Map<Principal, T.PlayerStats> = Map.new<Principal, T.PlayerStats>();

  // ========== MCP SDK STATE ==========

  var stable_http_assets : HttpAssets.StableEntries = [];
  transient let http_assets = HttpAssets.init(stable_http_assets);

  var resourceContents = [
    ("file:///README.md", "# Chess MCP Server\nFully on-chain chess engine on the Internet Computer."),
  ];

  var appContext : McpTypes.AppContext = State.init(resourceContents);

  // ========== AUTHENTICATION ==========

  let issuerUrl = "https://bfggx-7yaaa-aaaai-q32gq-cai.icp0.io";
  let requiredScopes = ["openid"];

  public query func transformJwksResponse({
    context : Blob;
    response : IC.HttpRequestResult;
  }) : async IC.HttpRequestResult {
    {
      response with headers = [];
    };
  };

  let authContext : ?AuthTypes.AuthContext = ?AuthState.init(
    Principal.fromActor(self),
    owner,
    issuerUrl,
    requiredScopes,
    transformJwksResponse,
  );

  // ========== BEACON ==========

  let beaconCanisterId = Principal.fromText("m63pw-fqaaa-aaaai-q33pa-cai");
  let beaconContext : ?Beacon.BeaconContext = ?Beacon.init(
    beaconCanisterId,
    ?(15 * 60),
  );

  // ========== TIMERS ==========

  Cleanup.startCleanupTimer<system>(appContext);

  switch (authContext) {
    case (?ctx) { AuthCleanup.startCleanupTimer<system>(ctx) };
    case (null) { Debug.print("Authentication is disabled.") };
  };

  switch (beaconContext) {
    case (?ctx) { Beacon.startTimer<system>(ctx) };
    case (null) { Debug.print("Beacon is disabled.") };
  };

  // ========== RESOURCES ==========

  transient let resources : [McpTypes.Resource] = [
    {
      uri = "file:///README.md";
      name = "README.md";
      title = ?"Chess MCP Server Documentation";
      description = ?"On-chain chess engine documentation.";
      mimeType = ?"text/markdown";
    },
  ];

  // ========== TOOL CONTEXT ==========

  transient let toolContext : ToolContext.ToolContext = {
    canisterPrincipal = Principal.fromActor(self);
    owner = owner;
    appContext = appContext;

    getGame = func(id : Text) : ?T.Game {
      Map.get(games, Map.thash, id);
    };

    getAllGames = func() : [T.Game] {
      let buf = Buffer.Buffer<T.Game>(Map.size(games));
      for ((_, game) in Map.entries(games)) {
        buf.add(game);
      };
      Buffer.toArray(buf);
    };

    getPlayerStats = func(p : Principal) : ?T.PlayerStats {
      Map.get(leaderboard, Map.phash, p);
    };

    getAllPlayerStats = func() : [T.PlayerStats] {
      let buf = Buffer.Buffer<T.PlayerStats>(Map.size(leaderboard));
      for ((_, stats) in Map.entries(leaderboard)) {
        buf.add(stats);
      };
      Buffer.toArray(buf);
    };

    putGame = func(id : Text, game : T.Game) {
      Map.set(games, Map.thash, id, game);
    };

    nextGameId = func() : Text {
      gameCounter += 1;
      "game-" # Nat.toText(gameCounter);
    };

    updatePlayerStats = func(p : Principal, stats : T.PlayerStats) {
      Map.set(leaderboard, Map.phash, p, stats);
    };
  };

  // ========== TOOLS ==========

  transient let tools : [McpTypes.Tool] = [
    ChessCreateGame.config(),
    ChessJoinGame.config(),
    ChessMakeMove.config(),
    ChessGetGame.config(),
    ChessListGames.config(),
    ChessResign.config(),
    ChessOfferDraw.config(),
    ChessGetLeaderboard.config(),
  ];

  // ========== MCP CONFIG ==========

  let allowanceUrl = "https://prometheusprotocol.org/connections";

  transient let mcpConfig : McpTypes.McpConfig = {
    self = Principal.fromActor(self);
    allowanceUrl = ?allowanceUrl;
    serverInfo = {
      name = "chess";
      title = "Chess MCP Server";
      version = "0.1.0";
    };
    resources = resources;
    resourceReader = func(uri) {
      Map.get(appContext.resourceContents, Map.thash, uri);
    };
    tools = tools;
    toolImplementations = [
      ("chess_create_game", ChessCreateGame.handle(toolContext)),
      ("chess_join_game", ChessJoinGame.handle(toolContext)),
      ("chess_make_move", ChessMakeMove.handle(toolContext)),
      ("chess_get_game", ChessGetGame.handle(toolContext)),
      ("chess_list_games", ChessListGames.handle(toolContext)),
      ("chess_resign", ChessResign.handle(toolContext)),
      ("chess_offer_draw", ChessOfferDraw.handle(toolContext)),
      ("chess_get_leaderboard", ChessGetLeaderboard.handle(toolContext)),
    ];
    beacon = beaconContext;
  };

  transient let mcpServer = Mcp.createServer(mcpConfig);

  // ========== PUBLIC ENTRY POINTS ==========

  public query func get_owner() : async Principal { return owner };

  public shared ({ caller }) func set_owner(new_owner : Principal) : async Result.Result<(), Payments.TreasuryError> {
    if (caller != owner) { return #err(#NotOwner) };
    owner := new_owner;
    return #ok(());
  };

  public shared func get_treasury_balance(ledger_id : Principal) : async Nat {
    return await Payments.get_treasury_balance(Principal.fromActor(self), ledger_id);
  };

  public shared ({ caller }) func withdraw(
    ledger_id : Principal,
    amount : Nat,
    destination : Payments.Destination,
  ) : async Result.Result<Nat, Payments.TreasuryError> {
    return await Payments.withdraw(caller, owner, ledger_id, amount, destination);
  };

  // ========== HTTP HANDLERS ==========

  private func _create_http_context() : HttpHandler.Context {
    return {
      self = Principal.fromActor(self);
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      auth = authContext;
      http_asset_cache = ?http_assets.cache;
      mcp_path = ?"/mcp";
    };
  };

  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    switch (HttpHandler.http_request(ctx, req)) {
      case (?mcpResponse) { return mcpResponse };
      case (null) {
        if (req.url == "/") {
          return {
            status_code = 200;
            headers = [("Content-Type", "text/html")];
            body = Text.encodeUtf8("<h1>♟ Chess MCP Server</h1><p>Connect via MCP at /mcp</p>");
            upgrade = null;
            streaming_strategy = null;
          };
        } else {
          return {
            status_code = 404;
            headers = [];
            body = Blob.fromArray([]);
            upgrade = null;
            streaming_strategy = null;
          };
        };
      };
    };
  };

  public shared func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    let mcpResponse = await HttpHandler.http_request_update(ctx, req);
    switch (mcpResponse) {
      case (?res) { return res };
      case (null) {
        return {
          status_code = 404;
          headers = [];
          body = Blob.fromArray([]);
          upgrade = null;
          streaming_strategy = null;
        };
      };
    };
  };

  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return HttpHandler.http_request_streaming_callback(ctx, token);
  };

  // ========== LIFECYCLE ==========

  system func preupgrade() {
    stable_http_assets := HttpAssets.preupgrade(http_assets);
  };

  system func postupgrade() {
    HttpAssets.postupgrade(http_assets);
  };

  // ========== API KEY SYSTEM ==========

  public shared (msg) func create_my_api_key(name : Text, scopes : [Text]) : async Text {
    switch (authContext) {
      case (null) { Debug.trap("Authentication is not enabled.") };
      case (?ctx) { return await ApiKey.create_my_api_key(ctx, msg.caller, name, scopes) };
    };
  };

  public shared (msg) func revoke_my_api_key(key_id : Text) : async () {
    switch (authContext) {
      case (null) { Debug.trap("Authentication is not enabled.") };
      case (?ctx) { return ApiKey.revoke_my_api_key(ctx, msg.caller, key_id) };
    };
  };

  public query (msg) func list_my_api_keys() : async [AuthTypes.ApiKeyMetadata] {
    switch (authContext) {
      case (null) { Debug.trap("Authentication is not enabled.") };
      case (?ctx) { return ApiKey.list_my_api_keys(ctx, msg.caller) };
    };
  };

  // ========== ICRC-120 ==========

  public type UpgradeFinishedResult = {
    #InProgress : Nat;
    #Failed : (Nat, Text);
    #Success : Nat;
  };

  private func natNow() : Nat { return Int.abs(Time.now()) };

  public func icrc120_upgrade_finished() : async UpgradeFinishedResult {
    #Success(natNow());
  };
};
