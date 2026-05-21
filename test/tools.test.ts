/**
 * Chess MCP Server — Tool Tests
 */

import { describe, beforeAll, afterAll, it, expect, inject } from 'vitest';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@icp-sdk/core/candid';
import { AnonymousIdentity } from '@icp-sdk/core/agent';
import { idlFactory as mcpServerIdlFactory } from '../.dfx/local/canisters/chess/service.did.js';
import type { _SERVICE as McpServerService } from '../.dfx/local/canisters/chess/service.did.d.ts';
import type { Actor } from '@dfinity/pic';
import path from 'node:path';

const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../.dfx/local/canisters/chess/chess.wasm',
);

// Helper to call a tool via JSON-RPC with optional API key
async function callTool(
  actor: Actor<McpServerService>,
  toolName: string,
  args: any,
  apiKey?: string,
  id: string = 'test',
) {
  const rpcPayload = {
    jsonrpc: '2.0',
    method: 'tools/call',
    params: { name: toolName, arguments: args },
    id,
  };
  const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
  const headers: [string, string][] = [['Content-Type', 'application/json']];
  if (apiKey) {
    headers.push(['X-API-Key', apiKey]);
  }
  const httpResponse = await actor.http_request_update({
    method: 'POST',
    url: '/mcp',
    headers,
    body,
    certificate_version: [],
  });
  if (httpResponse.status_code !== 200) {
    const bodyText = new TextDecoder().decode(httpResponse.body as Uint8Array);
    return { _status: httpResponse.status_code, _body: bodyText, result: { isError: true, content: [{ text: `HTTP ${httpResponse.status_code}: ${bodyText}` }] } };
  }
  const responseBody = JSON.parse(
    new TextDecoder().decode(httpResponse.body as Uint8Array),
  );
  return responseBody;
}

// Helper to parse structured content from tool response
function parseResult(response: any) {
  const text = response.result.content[0].text;
  return JSON.parse(text);
}

describe('Chess Tool Tests', () => {
  let pic: PocketIc;
  let serverActor: Actor<McpServerService>;
  let canisterId: any;
  let whitePlayer = createIdentity('white-player');
  let blackPlayer = createIdentity('black-player');
  let whiteApiKey: string;
  let blackApiKey: string;

  beforeAll(async () => {
    const picUrl = inject('PIC_URL');
    pic = await PocketIc.create(picUrl);
    canisterId = await pic.createCanister();

    const initArg = IDL.encode(
      [IDL.Opt(IDL.Record({ owner: IDL.Opt(IDL.Principal) }))],
      [[{ owner: [whitePlayer.getPrincipal()] }]],
    );

    await pic.installCode({
      canisterId,
      wasm: MCP_SERVER_WASM_PATH,
      arg: initArg.buffer as ArrayBufferLike,
    });

    serverActor = pic.createActor<McpServerService>(
      mcpServerIdlFactory,
      canisterId,
    );

    // Create API keys for both players
    serverActor.setIdentity(whitePlayer);
    whiteApiKey = await serverActor.create_my_api_key('white-key', ['openid']);

    serverActor.setIdentity(blackPlayer);
    blackApiKey = await serverActor.create_my_api_key('black-key', ['openid']);
  });

  afterAll(async () => {
    await pic?.tearDown();
  });

  describe('chess_create_game', () => {
    it('should create a game when authenticated', async () => {
      const resp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      expect(resp.result.isError).toBe(false);
      const data = parseResult(resp);
      expect(data.gameId).toBe('game-1');
      expect(data.status).toBe('waiting');
      expect(data.board).toContain('R N B Q K B N R');
    });

    it('should reject unauthenticated create', async () => {
      const resp = await callTool(serverActor, 'chess_create_game', {});
      // Should get 401 or an error
      expect(resp._status === 401 || resp.result.isError).toBe(true);
    });
  });

  describe('chess_join_game', () => {
    it('should let another player join as black', async () => {
      // Create a game as white
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;

      // Join as black
      const joinResp = await callTool(serverActor, 'chess_join_game', { gameId }, blackApiKey);
      expect(joinResp.result.isError).toBe(false);
      const data = parseResult(joinResp);
      expect(data.status).toBe('active');
      expect(data.message).toContain('black');
    });

    it('should reject self-join', async () => {
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;

      const joinResp = await callTool(serverActor, 'chess_join_game', { gameId }, whiteApiKey);
      expect(joinResp.result.isError).toBe(true);
      expect(joinResp.result.content[0].text).toContain('own game');
    });
  });

  describe('chess_make_move', () => {
    it('should accept legal moves', async () => {
      // Create and join
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;
      await callTool(serverActor, 'chess_join_game', { gameId }, blackApiKey);

      // White moves e2e4
      const moveResp = await callTool(serverActor, 'chess_make_move', { gameId, move: 'e2e4' }, whiteApiKey);
      expect(moveResp.result.isError).toBe(false);
      const data = parseResult(moveResp);
      expect(data.move).toBe('e2e4');
      expect(data.turn).toBe('black');
      expect(data.status).toBe('active');
    });

    it('should reject moves when not your turn', async () => {
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;
      await callTool(serverActor, 'chess_join_game', { gameId }, blackApiKey);

      // Black tries to move first
      const moveResp = await callTool(serverActor, 'chess_make_move', { gameId, move: 'e7e5' }, blackApiKey);
      expect(moveResp.result.isError).toBe(true);
      expect(moveResp.result.content[0].text).toContain('not your turn');
    });

    it('should reject illegal moves', async () => {
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;
      await callTool(serverActor, 'chess_join_game', { gameId }, blackApiKey);

      // Try to move pawn 3 squares
      const moveResp = await callTool(serverActor, 'chess_make_move', { gameId, move: 'e2e5' }, whiteApiKey);
      expect(moveResp.result.isError).toBe(true);
    });
  });

  describe('chess_get_game', () => {
    it('should return game state (public, with api key)', async () => {
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;

      // Use any api key to access (public tool, but auth is required at HTTP level)
      const getResp = await callTool(serverActor, 'chess_get_game', { gameId }, whiteApiKey);
      expect(getResp.result.isError).toBe(false);
      const data = parseResult(getResp);
      expect(data.status).toBe('waiting');
      expect(data.board).toContain('K');
    });
  });

  describe('chess_list_games', () => {
    it('should list games with status filter', async () => {
      const resp = await callTool(serverActor, 'chess_list_games', { status: 'all' }, whiteApiKey);
      expect(resp.result.isError).toBe(false);
      const data = parseResult(resp);
      expect(data.total).toBeGreaterThan(0);
      expect(Array.isArray(data.games)).toBe(true);
    });
  });

  describe('chess_resign', () => {
    it('should let a player resign', async () => {
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;
      await callTool(serverActor, 'chess_join_game', { gameId }, blackApiKey);

      // White resigns
      const resignResp = await callTool(serverActor, 'chess_resign', { gameId }, whiteApiKey);
      expect(resignResp.result.isError).toBe(false);
      const data = parseResult(resignResp);
      expect(data.winner).toBe('black');
    });
  });

  describe('chess_offer_draw', () => {
    it('should allow draw offer and acceptance', async () => {
      const createResp = await callTool(serverActor, 'chess_create_game', {}, whiteApiKey);
      const gameId = parseResult(createResp).gameId;
      await callTool(serverActor, 'chess_join_game', { gameId }, blackApiKey);

      // White offers draw
      const offerResp = await callTool(serverActor, 'chess_offer_draw', { gameId }, whiteApiKey);
      expect(offerResp.result.isError).toBe(false);
      expect(parseResult(offerResp).message).toContain('Draw offered');

      // Black accepts
      const acceptResp = await callTool(serverActor, 'chess_offer_draw', { gameId }, blackApiKey);
      expect(acceptResp.result.isError).toBe(false);
      expect(parseResult(acceptResp).status).toBe('draw');
    });
  });

  describe('chess_get_leaderboard', () => {
    it('should return leaderboard after games', async () => {
      const resp = await callTool(serverActor, 'chess_get_leaderboard', {}, whiteApiKey);
      expect(resp.result.isError).toBe(false);
      const data = parseResult(resp);
      expect(Array.isArray(data.players)).toBe(true);
    });
  });
});
