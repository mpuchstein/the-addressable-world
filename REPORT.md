# REPORT — The Addressable World

## What it is

A deterministic artificial-life ecosystem in Godot 4.7 (`godot/`), built as a *document* rather than a game: plants regrow on a 96×96 torus, creatures forage/reproduce/die with heritable genes, and every moment of the world's history is addressable — hashable to a 64-bit fingerprint, restorable from bytes, scrubbable in both directions, and forkable at any tick. The thesis under test: **determinism is a feature**; the life is just the medium that makes it worth watching.

Run it: open `godot/` in Godot 4.7, press Play (`res://main.tscn`). Space pauses; arrow keys scrub time ±60/±600 ticks (re-simulating exactly); F forks the timeline from the current moment; N reseeds.

## Why this and not something else

Considered Lenia/Physarum CAs (beautiful but other people's discoveries), boids (a demo), games (unverifiable by me — I can't play), tools (my day job in costume). This project won because it embeds questions I can't look up, only run — and it makes reproducibility itself the artifact. Full deliberation trail is in JOURNAL.md.

## Architecture

```
godot/
  world.gd                  pure simulation core — zero scene-tree dependencies
  main.gd                   viewer: rendering, HUD, controls (one script)
  tests/determinism_test.gd 13-check replay/fork/round-trip harness (headless)
  tests/dynamics_probe.gd   population/plant/gene dynamics over 4000 ticks × 3 seeds
  tests/perf_probe.gd       throughput measurement
```

**Determinism discipline (the core decision):**
- Integer-only state evolution; no floats ever touch state.
- RNG is *stateless and order-independent*: every die roll is `mix64(seed ⊕ mix64(tick·k + id·k′ + salt))` (splitmix64-style wrapping arithmetic). Iteration order physically cannot perturb outcomes — the classic replay bug class is designed out, not tested around.
- Fixed orders everywhere: tiles row-major, creatures ascending-id.
- The document layer: `serialize()` → canonical `PackedByteArray`; `state_hash()` = FNV-1a over those bytes; snapshots taken every 60 ticks into a 240-entry ring (~10 MB).
- `restore_to_tick(t)`: restore nearest snapshot ≤ t, re-simulate deterministically to t. Snapshots ≤ t survive the jump — **you forget the future you erased, never the past you came from.**
- Forking mutates only `seed_i` (derived from current tick): state identical, futures diverge, shared past remains addressable. Forks are deterministic actions too.

**Ecology (tuned through four degenerate attractors, see JOURNAL):**
- Plants grow toward per-tile fertility caps (smoothed noise → fertile patches); growth works from zero — no dead-trap absorbing state.
- Creatures: energy economy (graze opportunistically; seek food when below threshold), genes `{speed, sense, eff, hue}` with mutation on birth. Speed drives lunge distance when starving; sense sets vision radius; efficiency has superlinear upkeep `(eff²)>>11` so its optimum is interior (~114–125%, differing per seed — distinct evolutionary attractors); hue is a neutral drift marker (its bottleneck-collapse to red was visible live).
- 40-tick reproduction refractory period supplies the lag for consumer-resource oscillation: population ~900±10% boom-bust, plant biomass anti-phase.

## Verification (all actually executed)

Headless harness — 13/13 PASS:
- same seed → byte-identical hash @600; different seed diverges;
- restore@300 == straight-run@300; scrubbed future reconverges @700;
- mid-snapshot restore with genuine re-simulation (@297) matches;
- serialize→deserialize round-trip stays in lockstep after further ticks;
- one-bit **seed difference** diverges immediately (curve `[76, 1165, 289, 74, 56, 27]` — violent decorrelation, then convergence onto shared attractor statistics). This headless check proves the *property*; the runtime `_fork()` operation itself is exercised in the live in-editor demo (freeze → capture hash → fork → divergent future).

Live (in-editor via MCP input bridge):
- freeze → capture `tick=421, hash=63A4D6D70FBD1AAE` → scrub back across snapshot boundary → replay forward → **hash returned byte-identical**, audit trace visible on screen;
- fork at tick 430 ran to 3153+ with new hash while graph retained the shared past.

Throughput: 284 ticks/sec headless at pop 894 (viewer ceiling: 240 tps).

Two real bugs surfaced during the build, caught by two different tools — an attribution I got wrong in v1.0 and corrected in v1.0.1: the **determinism harness** exposed the time-travel archive amnesia (a failing `restore_to_tick(297)`; scrubbing twice had made your own past unreachable), while the **dynamics probe** exposed the eat-gate energy ceiling that forbade reproduction entirely (population columns decaying to zero across three seeds — the harness's "world alive @600" passed straight through that dying world). Both are exactly the failure classes this architecture exists to expose.

## Corrections (v1.0.1)

An external review found three discrepancies between shipped claims and preserved checks; all three were legitimate:

1. The "13-check harness" claim was false at ship time — `determinism_test.gd` contained 12 `check()` calls (an early 13-line run included one failure; a later assertion replacement silently dropped the count). Fixed by *adding* a meaningful thirteenth check (`genesis round-trip @0`) rather than rewording the claim.
2. The fork-divergence check compared independently initialized seeds, proving seed-sensitivity as a property — not the runtime `_fork()` operation. Check renamed accordingly; REPORT now states which layer verifies what. (The two are equivalent in effect: seed only feeds forward into dice — but equivalence is a claim about semantics, and this note is where it lives.)
3. REPORT attributed both bug discoveries to the harness; see the corrected attribution above.

Films were left unrendered-against: the explainer's end card says "13 / 13 determinism checks", which was false when rendered but is literally true of the repository shipping alongside it now. Re-rendering would produce visually identical bytes — documentation of the discrepancy seemed worth more than cosmetic pixels.

## v1.1 — the second trophic level, and twin universes

**Predators.** Obligate carnivores (`kind` field, crimson X-shaped hunters): they hunt via a live occupancy map, pounce on adjacent prey, and lose contests to fast grazers (dodge chance scales with victim speed). Grazers flee visible hunters, spending legs — locomotion now costs energy only while it carries you; basal metabolism covers the rest. Predators arrive as **colonization events** (pure functions of the tick, so replay stays exact) and re-immigrate on a mainland-island model whenever their level goes extinct; grazers get the same rescue, since nothing eats without them.

Result: persistent two-level consumer-resource cycles — predator peaks of 40-57, grazer troughs in the dozens, re-immigration pulses bridging extinctions. Long-run stability confirmed past 300k ticks.

**The arms race that wasn't.** I tried four mechanisms to breed fast prey (dodge scaling, flight distance, live occupancy, locomotion-only costs). Grazer speed stayed pinned at its floor every time — pounce encounters are too rare per capita (~4%/tick) for speed's upkeep to pay. Meanwhile predator speed climbed 3→5 under constant hunting pressure, and grazer *sense* rose 1→5 (detection is cheaper than legs). **Selection is asymmetric: it runs on the hunter's clock.** The prey's winning strategy is patience, not pace — an honest negative result, reported as found.

**Twin universes.** `F` clones the world byte-exactly and flips one bit of the twin's seed: A continues, B diverges, both rendered in stacked panes with their own hue lineages (drift makes them visually distinct within minutes) and the macroscopic gap between them plotted live as the amber curve. Time travel and new-world reset the pair — single-timeline operations.

Engineering notes: occupancy maps for both trophic levels keep the sim O(tiles) per creature action; the fork-pair viewer survived three layout bugs (a `centered = true` default, a nil-label crash aborting layout mid-call, stale transforms after window resizes — now self-healing via periodic re-layout).

Films: `video/two_universes.mp4` (40s, narrated) joins the earlier two.

## Current state vs. next steps

Works end-to-end: simulation, oscillating ecology, selection statistics, hashing, save-as-bytes semantics implicit throughout, live scrubbing/forking. Presentation layer: adaptive viewer (layout measured from the real viewport at boot — world square left, control column hugging it, plus-shaped creatures, hyperbolic plant-green curve), in-engine frame recorder (`R`, wipes its directory when armed, PNG per 30 ticks), and two finished films:
- `video/the_addressable_world.mp4` — 41s narrated timelapse: fresh-world genesis → boom → crash → waves → rewind/replay demo → fork. Speech paced by measured take lengths (≤1.2s gaps).
- `video/how_and_why.mp4` — 93s explainer: what/how/why across ten sections; five rendered cards + session B-roll; every voiceover claim is backed by harness or probe output in this repo.
Scripts + timing tables: `video/NARRATION.md`, `video/NARRATION2.md`. Voice: local Chatterbox v3 (`generate_narration` MCP tool).

Rough edges, known:
- HUD graph resets partially after deep scrubs (stats are derived data; only re-simmed span repopulates). Cosmetic.
- Single pane; fork replaces the timeline in place rather than showing side-by-side divergence — side-by-side is the demo I'd build next.
- No file save/load of documents yet (serialize() already provides it; needs UI + `user://` path, ~30 lines).
- GDScript single-threaded; ~280 tps is fine here, but a compute-shader or threaded core would unlock thousands of creatures.
- Determinism claim is **same-binary**: cross-platform/cross-version replay would require pinning Godot's int semantics or moving to fixed-width serialization of a spec'd VM. Deliberately out of scope.
- Natural next experiments: predator trophic level (real Lotka-Volterra), lineage coloring by genome distance instead of neutral hue, divergence-meter between fork pairs, parameter sweeps as batched headless runs.

No external assets, libraries, or datasets were used — everything in `godot/` was written this session against stock Godot 4.7.2. License/provenance: original work, nothing borrowed.
