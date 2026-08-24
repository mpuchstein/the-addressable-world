# Narration script — "How and Why" v2 (100.6s)

Updated for v1.1's world: two trophic levels, the patience finding, twin
universes. Voice: Chatterbox v3 `generate_narration`, en, ex 0.4 / temp 0.65 /
cfg 0.5. Eleven takes, each placed 0.45s into its section; sections = take
+ 0.9s. Cards: title, doc-hash, rules, questions, patience (new), dead-worlds,
end. B-roll from the autopilot take (hunters on tape).

| # | at | visual | text |
|---|-----|--------|------|
| 1 | 0.5s | title | What would I build, given nothing but my own curiosity? A universe small enough to prove things about. |
| 2 | 6.7s | genesis+colonization | It is an artificial life simulation with two trophic levels. Plants regrow on a torus. Grazers forage and inherit their parents genes. And hunters, crimson crosses, arrive at tick five hundred to eat them. |
| 3 | 17.7s | doc card | But the real subject is not the creatures. It is the document they live in. Every moment of this world has a fingerprint: a sixty four bit hash of its entire state. |
| 4 | 26.6s | rules card | Three rules make replay exact. Integers only: floats never touch state. Randomness never depends on order: every die roll derives from seed, tick, and creature. And every sixty ticks, the whole world is serialized to bytes. |
| 5 | 38.9s | cycles | Those bytes make time travel exact. Rewind six hundred ticks, replay them forward, and you arrive byte for byte where you stood. |
| 6 | 45.6s | twins | Or fork history itself. Same past, new dice. Twin universes peel apart from a single flipped bit, and the gap between them is plotted live. |
| 7 | 54.4s | questions card | Why build this? Because it holds questions I cannot look up. Does selection find efficient grazers? Do hunters and prey breathe against each other? How fast does one flipped bit become another world? |
| 8 | 64.2s | waves | The answers surprised me. Hunters and grazers fell into anti phase breathing. Efficiency settled at different optima in different seeds. And the arms race I asked for? It refused to happen. |
| 9 | 73.7s | patience card | Selection is asymmetric. Hunters grew faster, because they must hunt to eat. Prey grew cheaper eyes, not faster legs. In this world, the winning strategy is patience. |
| 10 | 83.3s | dead-worlds card | Getting here took five attempts. Four times the world was stable and dead: a golf course, a famine, a strip mine, a mowed lawn. Life needed scarcity, inheritance, and lag. |
| 11 | 93.3s | end card | A thirteen check harness proves the determinism claims on every run. The past stays addressable. That was the whole point. |

Output: `video/how_and_why_v2.mp4` — supersedes the v1.0 explainer.
