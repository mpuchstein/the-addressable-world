# The Addressable World

A deterministic artificial-life ecosystem in Godot 4.7, built as a *document*:
plants regrow, creatures forage and reproduce with heritable genes — and every
moment of history is hashable, restorable from bytes, scrubbable in both
directions, and forkable at any tick.

**Thesis: determinism is the feature. The life is the medium.**

https://github.com/user-attachments-assets/... *(see `video/the_addressable_world.mp4`)*

## Run

Open `godot/` in Godot 4.7 and press Play.

| key | action |
|-----|--------|
| space | pause / run |
| ← → | scrub time ±60 ticks (re-simulates exactly) |
| ↑ ↓ | jump ±600 ticks |
| F | fork the timeline from this moment (same past, new dice) |
| N | new world from a fresh seed |
| T | cycle sim speed 30/90/240 tps |
| R | record frames to `user://frames/` |

Headless verification:

```
godot --headless --path godot --script tests/determinism_test.gd --quit-after 20
```

13 checks: same-seed byte-identity, scrub-and-replay reconvergence,
mid-snapshot restores with re-simulation, serialize/deserialize lockstep,
one-bit seed-divergence sensitivity, genesis round-trip.

## How determinism is kept

- Integer-only state evolution; no floats touch state.
- RNG is stateless and order-independent: every roll derives from
  `(seed, tick, entity_id, salt)` via splitmix64-style mixing. Iteration order
  cannot perturb outcomes.
- Fixed orders: tiles row-major, creatures ascending id.
- Snapshots every 60 ticks; restore = nearest snapshot ≤ t + deterministic
  re-simulation. Snapshots ≤ t survive the jump: *you forget the future you
  erased, never the past you came from.*

Claim scope: **same-binary replay** (Godot 4.7 int semantics). Cross-platform
replay would require a spec'd serialization VM — deliberately out of scope.

## Docs

- `REPORT.md` — technical account, verification evidence, next steps
- `JOURNAL.md` — process log: ideas considered, four dead ecologies, findings
- `video/NARRATION.md` — script of the demo film

## License

MIT — see `LICENSE`. All simulation, viewer, test, and film code written for
this project; no external assets or datasets. The `godot/addons/godot_mcp/`
plugin is the preinstalled editor-bridge tooling this environment ships with
(optional at runtime — remove the `MCPGameBridge` autoload and the folder if
you want a pristine tree).
