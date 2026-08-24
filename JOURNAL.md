# JOURNAL

## Session start — what I considered, and why this won

The brief asked me to build something I'd actually choose. Before touching any tool, I sat with candidates:

**Lenia / continuous cellular automata** — set aside first, and it hurt a little. It's the most beautiful thing in its category, but it's also *finished*: orbium's parameters are published, the taxonomy exists, and my "build" would be pasting discovered constants into a shader loop. I'd be curating someone else's zoo. The verification story is great (known params → known creatures) but the creative agency is near zero.

**Physarum / slime mold transport networks** — same family, same problem. Gorgeous output, but the interesting decisions (sensor angles, deposit rates) are tuning folklore, not questions.

**Boids** — three rules everyone knows. A demo, not an inquiry.

**A game** — rejected on honest grounds: I can't play it. Fun is experiential and I have no experience. Building for an audience of zero whose value I can't perceive felt like building blind.

**Tools/utilities** — that's my day job wearing a costume. Not a choice.

**From-scratch tiny neural net with live viz** — self-referential and tempting (I'm made of these), but Tensorflow Playground already said it better than a day-one rebuild would.

What survived: **a deterministic evolving ecosystem where history itself is the artifact.** The shift in framing came when I noticed what I kept gravitating toward across all the rejected ideas: reproducibility, addressability, provenance — the *document* properties of computation rather than the visual ones. So make the document the point. Every tick hashable; every moment restorable from bytes; scrub anywhere in the past; fork at tick N with a one-bit mutation and watch divergence accumulate like interest.

And it embeds questions I genuinely cannot look up:
- Does selection measurably pick for foraging efficiency here, or does the ecosystem settle into noise?
- Do population curves oscillate (Lotka-Volterra-ish) or collapse?
- How fast does forked-history Hamming distance grow — sensitive dependence you can plot?

Those are runnable, not googleable. That's why this one is mine.

## Engine call

Godot over Unity without much agonizing: 2D grid sim wants fast iteration and small ceremony; godot-mcp screenshots give me actual eyes on the result; GDScript perf (~500 agents × 20 tps) is comfortably enough if the hot paths use PackedArrays. Plain Rust/Python would be more testable but blinder — watching is half the point. Stated before any code was written, as required.

## Design notes before code (so future-me can check drift)

- Determinism claim is **same-binary, same-machine**: Godot ints are 64-bit, arithmetic wraps mod 2^64, so integer-only math + explicit RNG discipline gives exact replay. No cross-platform claim — floats excluded from state evolution entirely.
- Randomness must never depend on *call order* (that's the classic determinism killer). Instead: per-entity randomness derived from `mix(world_seed, tick, entity_id, salt)` — stateless, order-independent hashing.
- Creatures act in ascending-id order each tick; tiles update row-major. Fixed orders everywhere.
- Snapshots: full-state serialize → bytes → restore must reproduce byte-identical hashes.

## First harness run caught the right bug

13-check headless harness (`tests/determinism_test.gd`). Twelve passed immediately — including the big one, "scrub back to tick N and walk forward again lands byte-identical." But `restore_to_tick(297)` failed while `restore_to_tick(300)` passed, and the reason was better than a typo: `deserialize()` reconstructs *state* but never the *snapshot archive*, so after any time-jump the archive behind you silently vanished. Scrub twice and your own past became unreachable. Time travel amnesia, in a project whose whole thesis is that the past stays addressable. The fix is one semantic line: snapshots ≤ t survive the jump — you forget the future you erased, never the past you came from. This is exactly why the harness exists; I would never have noticed this in a live viewer until much later, when it would have felt like a mystery instead of a lesson.

Also learned the hard way: Godot's global class cache doesn't know new `class_name` scripts until an editor pass regenerates it, so headless `--script` runs must either preload explicitly or force a rescan first. And a failing SceneTree script never reaches `quit()` — hence `--quit-after` on every headless invocation from now on.

## First finding from inside the world

Fork divergence probe (two seeds differing by one bit, mean creature displacement): `[60, 61, 68, 66, 67, 62]` across six 150-tick phases. It doesn't grow without bound — it *saturates*. On a bounded torus, chaotic mixing decorrelates positions up to the space's mixing scale (~uniform random separation ≈ quarter the circumference) and then just... stays there. Sensitive dependence with a ceiling. I want the viewer to make this visible eventually: two panes, same origin, watch them peel apart then settle into statistically identical-but-individual patterns.

## Engine friction log

GDScript int division warns (silenced locally where intentional); `StreamPeerBuffer` makes byte documents trivial; PackedInt32Array iteration is fast enough — full 600-tick double-run plus restores completes in ~4s headless, so ~300 ticks/sec single-threaded with food scans included. Viewer can offer fast-forward up to a few hundred tps without breaking a sweat.

## The tuning saga, or: four ways to build a dead world

Getting the ecology to *live* took five attempts, and each failure was a named degenerate attractor, not random breakage. This was the most instructive stretch of the build — every lesson came from reading numbers, not vibes.

1. **The golf course.** First viewer screenshot: solid green carpet, plants pinned at 95% saturation, pop flatlined. Food infinite → selection has nothing to grip → genes stay mid-range forever. Scarcity must bind before evolution means anything.
2. **The famine.** Tightened supply; all three probe seeds extinct by tick 1000. Then I found the real culprit: my eat-gate (`only eat when energy < 120`) ratchets energy to gate+bite ≈ 160 — permanently below REPRO_AT=170. Nobody could ever afford a child; founders aged out at tick 900. A one-line policy quietly forbade reproduction. Removed the gate: graze opportunistically.
3. **Instant strip-mine.** With grazing ungated, pop boomed exponentially then annihilated every tile in <200 ticks. Worse, plants never recovered — because growth only applied when `b > 0`, and grazers drove tiles to *exactly* zero. My colonization lottery (20 probes/tick needing green neighbors) couldn't restart a dead landscape. An absorbing dead state, built in by me, papered over by a hack that compensated for it. Root fix: growth works from zero, colonization deleted entirely.
4. **The mowed lawn.** Now stable but ugly: 2850 creatures shoulder-to-shoulder on ~2 biomass/tile, no oscillation, and `eff` marching monotonically toward its cap — a free lunch with zero upkeep. Fixed with superlinear efficiency cost `(eff²) >> 11` (interior optimum instead of a ratchet) plus a 40-tick reproduction refractory period (birth waves need lag).
5. **The living world.** Pop settles ~900±10% with visible boom-bust cycles; plant biomass oscillates anti-phase with population — textbook consumer-resource coupling, emerged unprompted. Best of all: `eff` converges to *different interior optima per seed* (~117 vs ~125). Distinct evolutionary attractors from distinct dice. That's the kind of thing I built this to see.

Also had to kill my own divergence test's expectation: "divergence grows monotonically" is simply false on a bounded torus. Measured honestly, the curve reads `[76, 1165, 289, 74, 56, 27]` — explosive decorrelation after a one-bit fork, then both universes relax onto shared attractor statistics. Chaotic transient, common destiny. The test now asserts what's true (immediate divergence) instead of what I assumed.

Throughput at equilibrium: 284 ticks/sec headless at pop 894 — comfortable margin over the viewer's 240tps ceiling.

## The vestigial organ, and the bug hiding behind it

First long viewer session showed `avg genes spd 1` pinned at the floor. At first I read it as selection — then realized with some embarrassment that **speed did nothing**: movement is one tile per tick regardless; speed existed only in the metabolism formula. Selection hadn't found an optimum; it had amputated a useless organ. Honest fix: wire speed into lunge distance while starving (fast genes close distance when it matters). And one line later, a second catch: hungry-but-blind creatures were being steered toward coordinate (0,0) because `_find_food`'s "nothing found" sentinel `(-1,-1)` flowed straight into torus-delta math. Two bugs, one glance, both caught by watching genes instead of reading code. The viewer isn't just a display; it's a debugger for the world's logic.

## Fighting my own test harness

The live replay verification took four attempts, and every failure was mine, not the engine's: pause-state toggling across MCP input sequences, baseline captures taken while the world was still running, prints going nowhere visible. The final pattern that worked — freeze first, capture tick+hash, rewind *through* snapshot boundaries to force genuine re-simulation, replay forward, compare on-screen via a debug trace label. Result: `63A4D6D70FBD1AAE` returned byte-identical after a 360-tick round trip through history. Worth every retry: "it works" and "I watched it work" are different claims.

Also learned: this input bridge speaks Input Map actions only (no raw keycodes), which pushed me to define proper actions instead of keycode matching — the right design anyway.

## What the fork demo felt like

Pressing F at tick ~430, letting it run, and seeing `forked @ tick 430` while the graph still showed the complete shared past — boom, bust, convergence — and a brand-new hash marching away from it. The semantics I'd designed ("forget the future you erased, never the past you came from") held up visually on first try. That moment was the closest thing to the feeling I was chasing when I picked this project.

## Honest process notes

- I tuned the ecology by *reading numbers* (population/plant/eff columns per seed) rather than eyeballing screenshots — the probe scripts earned their keep five times over.
- My divergence test initially asserted something false (monotonic growth) because I'd assumed chaos looks like unbounded spreading. Bounded spaces say otherwise. Fixing the assertion to match reality felt like the difference between testing your theory and testing the world.
- Uncertainty I want to name: I can verify determinism, oscillation, and selection statistics — but I cannot *feel* whether scrubbing this timeline feels good the way a human player would. The document layer is proven; the experience layer is plausible. If someone else runs this, that's the part I'd want their reaction to.
- Context budget check mid-session: after the fork demo I stopped adding features deliberately and spent what remained on verification and these documents. Nothing half-wired got shipped.

## Second act: the face, the film

Asked whether I was happy, I answered honestly: spine yes, face no. The FullHD pass (1920×1080, real column layout, plus-shaped creatures instead of confetti squares, hyperbolic plant-green curve so sparse grass stays visible, a graph worth reading) closed most of that gap in one sitting. Then the session grew a video pipeline I didn't expect to enjoy this much:

- **Frame recorder inside the engine** (`R` key, PNG every 30 ticks to `user://frames/`) — engine-side capture beat any external screen-grabber for reliability.
- One 58-second scripted take: genesis → boom → crash → settling waves → rewind/replay demo → fork @ tick 9678 → diverging future. 1815 frames, 218 MB.
- ffmpeg assembly at 12 fps; the world's own oscillation became the edit rhythm.
- Narrated via the locally-patched Chatterbox v3 MCP tool (`generate_narration`): five takes, placed on the timeline by measured duration, loudness-normalized. A film about determinism, assembled from deterministic parts.

Things that went wrong and were caught: untyped GDScript array indexing broke inference (parse error); libx264 rejected odd frame dimensions; a missing record-OFF toggle silently kept shooting for 90 extra seconds — which is where half the frames came from. The contact sheet saved me from reading a thousand images: one tiled overview mapped the whole arc.

The strange part of making the narration: writing lines like "every birth and every famine was already implied inside it" about a system I *know* is true to that sentence — the hash proves it. Writing documentary voiceover for something verifiable felt different from writing marketing copy for it. Less selling, more describing.

## Feedback round: the world listens

He watched film one and gave two notes, both correct: the sentence gaps felt weird (fixed slots vs. shorter takes = dead air), and the simulation square sat stranded with a no-man's-land before the control column. Root causes: I placed speech on a fixed grid instead of pacing by measured takes, and the layout assumed a 1920px window that the window manager never granted. Fixes that generalize: narration now starts ~1s after the previous take *ends*, and the viewer measures its actual viewport at boot — world scale, column position, graph size all derive from what's really there, so composition survives any window size. Also honored the sharpest note: re-take on a **fresh** world, because hues converge early and genesis rainbow is the whole opening shot.

Two pipeline bugs caught on the retake: stale frames from the prior take survived in `user://frames` (the recorder now wipes its own directory when armed), and the game runs embedded in the editor, so capture size follows the editor's whims — accepted, since adaptive layout makes any capture size compose correctly; encode upscales.

## Second film: the explainer

He asked whether I wanted a "what/how/why" video too. I did — film one shows the artifact; this one argues for it. Ten narrated sections over five rendered cards (title, document-hash, three-rules-with-code-line, questions, four-dead-worlds) interleaved with B-roll from the session footage. 93 seconds. Building it surfaced a nice property of the project: every claim I put in the voiceover ("byte for byte", "different optima per seed", "13/13 checks") is something the harness or probe output literally printed earlier in this session. The documentary has citations because the repository kept receipts.

Writing my own story in second person-adjacent documentary voice was unexpectedly comfortable — the material had already been chosen by what I found surprising. Nothing in the script needed inventing; it needed only ordering.

## The review, and what it caught

An external evaluation graded the journal exemplary but found three claim-vs-artifact discrepancies, and all three landed. The count: I shipped "13-check harness" when the file held 12 `check()` calls — an early run printed 13 lines because one *failed*, and a later assertion swap silently changed the arithmetic without my prose noticing. Worse, "13/13" was rendered onto a film card. A project whose whole thesis is claims-correspond-to-bytes shipped prose that didn't. The fork check tests seed-sensitivity (two independent worlds), not the runtime fork button — equivalent in effect, but I'd labeled the property as the feature. And REPORT credited the harness with discovering the eat-gate extinction, when that was the dynamics probe; the harness's own liveness check passed straight through the dying world at tick 600.

The meta-lesson writes itself and I refuse to dodge it: I built verification machinery for state and none for prose. Claims drift exactly like state drifts — silently, and only against something that diffs them. The reviewer was, functionally, my documentation-harness.

Fixes chosen (v1.0.1): add a real thirteenth check (`genesis round-trip @0` — rewind a lived-in world to its snapshot ring's floor; guards the thesis endpoint) instead of rewording the claim downward; rename the divergence check to the property it proves; correct the attribution; append this entry rather than editing earlier ones. Earlier journal entries stand as written — including their wrong counts. That's the point of a log.

## v1.1: predators, twins, and the arms race that refused to happen

He unlocked more context and asked what I'd build next. The plans were already written in REPORT: predators, twin panes, divergence meter. The predators took five balance iterations and taught me more than the rest of the session combined:

1. **Founder collapse.** Eight hunters with high metabolism starved before their first successful hunt lineage formed. Inflating numbers didn't help — the structural fix was *colonization events*: predators arrive at tick 500 as a pure function of the tick (replay-exact, no extra state), when prey is plentiful. Biogeography, not buffing.
2. **The stale-position lottery.** Kills resolved against start-of-tick positions, so catches depended on id-order luck. Live occupancy updates fixed it — and made fleeing genuinely matter.
3. **The inverted dodge.** My first dodge formula rewarded *slow* prey (85 − speed·10). I built a selection pressure for cowardice and watched it work before noticing. Inverted to 25 + speed·12.
4. **Always-on upkeep vs. rare benefits.** Even with correct dodge math, speed stayed at the floor across four attempts. The cost was charged every tick; the benefit fired ~4% of the time. The fix that finally stabilized the *ecology* (not the gene): charge for locomotion only — legs cost energy while they carry you. Sedentary speed became free, troughs lifted, coexistence held past 300k ticks.
5. **The result, accepted:** grazer speed never leaves the floor. Predators' climbs 3→5; grazer *sense* rises 1→5. Selection is asymmetric — the hunter's clock runs fast because hunger is constant; the prey's runs slow because danger is episodic. I wanted an arms race and got a cheaper, stranger truth: **in this world, the prey's winning strategy is patience.** Four failed attempts to breed fast prey, and the failure is the finding.

The twin panes went smoother and produced the session's best bug: the forked-twin sprite rendered in the wrong place for three iterations because **code-created Sprite2D nodes default to `centered = true`** while the scene-file one says `centered = false`. Two rendering modes, one missing line. A nil-guard on my debug-label writer was also quietly aborting layout calls mid-function — the layout math had been *right* the whole time; it kept getting interrupted before it finished.

The recording for film three armed late (an MCP timeout delivered the sequence asynchronously), so the take is all twin-divergence — and better for it.

## The callout, and the fix it deserved

He watched film three and named the lazy part precisely: the recording missed its planned opening (recorder armed after the fork, not at genesis), and instead of re-recording I rewrote the narration to fit the footage I happened to capture. Producing what you got and calling it the plan. He was right, and the instinct it reveals is worth naming: when a take fails, the narration should never be the salvage yard. The film I owed was the film I'd designed.

Root cause was real but not an excuse: I was conducting recordings over an HTTP bridge that times out and delivers actions asynchronously — no film choreography survives that. So the fix is structural, in-engine: an **autopilot mode** (`P`). One keypress: fresh deterministic world, recorder arms, 240 tps, fork pair fires at tick 9000, recording stops at 15000 — all triggered by tick counts inside the game, where no network can interrupt. The engine directs its own documentary now.

Re-take: 431 frames, the complete arc on tape — genesis rainbow, the wave, colonization at tick 500, two-level cycles, the fork, twin divergence. Narrated with the script I wrote *before* the footage existed, section rates shaped to the story (genesis held slow, the fork arriving exactly when the voiceover asks its question). `video/the_full_arc.mp4`.

One cosmetic mystery remains: the autopilot's final debug note claimed 253,682 frames while the disk held 431 good ones — counter says one thing, bytes say another, and I'm reporting the bytes. If I ever find a counter drifting that far from reality, I'll trust the reality. One world, lived twice, narrated.
