# Manhunt

iOS game for playing real-world Manhunt with friends. The host sets hiders and seekers, a play area, safe zones, and out-of-bounds zones. Phones report precise location, verify tags, and follow rules enforced by a server.

Design: [docs/superpowers/specs/2026-11-08-manhunt-app-design.md](docs/superpowers/specs/2026-11-08-manhunt-app-design.md)

## Layout

- `ios/` — SwiftUI visual of the screens in the design (sample park, sample players). Open `ios/Manhunt.xcodeproj` and run the Manhunt scheme. The rules engine is not in the app yet. `ios/ManhuntTests` is the contract for that later work and does not build until those types exist.
- `server/` — FastAPI game server (not started)
- `infra/` — Azure Bicep (not started)

## License

[MIT](LICENSE)
