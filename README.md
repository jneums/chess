# ♟ Chess MCP Server

A fully on-chain chess game engine on the Internet Computer, exposed via the Model Context Protocol (MCP).

## Features

- **Complete chess rules** — legal move validation, castling, en passant, pawn promotion
- **Game state detection** — check, checkmate, stalemate, 50-move rule, insufficient material
- **ASCII board rendering** — visual board representation in every response
- **ELO leaderboard** — competitive rankings updated after each game
- **Draw system** — offer/accept draw flow
- **Persistent state** — all games survive canister upgrades

## Tools

| Tool | Auth | Description |
|------|------|-------------|
| `chess_create_game` | ✅ | Create a new game (you play as white) |
| `chess_join_game` | ✅ | Join an open game as black |
| `chess_make_move` | ✅ | Make a move in coordinate notation (e.g., `e2e4`) |
| `chess_get_game` | ❌ | Get full game state with board and move history |
| `chess_list_games` | ❌ | List games filtered by status |
| `chess_resign` | ✅ | Resign from an active game |
| `chess_offer_draw` | ✅ | Offer or accept a draw |
| `chess_get_leaderboard` | ❌ | Player rankings by ELO |

## Move Format

Use coordinate notation: source square + target square, optionally with promotion piece.

- `e2e4` — pawn to e4
- `g1f3` — knight to f3
- `e7e8q` — pawn promotes to queen

## Quick Start

```bash
npm install
mops install --lock ignore --no-toolchain
dfx start --background
dfx deploy
npm test
```

## Deploy to Mainnet

```bash
icp deploy chess -e ic
```

## Built With

- [Motoko](https://internetcomputer.org/docs/current/motoko/main/motoko) — Smart contract language for ICP
- [MCP Motoko SDK](https://github.com/ArcMichael/mcp-motoko-sdk) — Model Context Protocol SDK
- [Prometheus Protocol](https://prometheusprotocol.org) — MCP app store and discovery

## License

MIT
