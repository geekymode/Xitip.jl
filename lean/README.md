# Checking Xitip's proofs in Lean 4

[`lean`](https://geekymode.github.io/Xitip.jl/dev/lean/) writes the
arithmetic core of a proof as a Lean 4 theorem: one real variable per joint
entropy, the inequalities the proof uses as hypotheses, the statement as the
goal, and `linarith` to close it. Lean checks it; this package does not.

## Running the check

`verify.jl` generates the proofs and compiles them. It needs a Lean project
with Mathlib available — any will do, since the generated files import
Mathlib and nothing else:

```console
$ git clone https://github.com/teorth/pfr.git    # or any Mathlib project
$ cd pfr && lake exe cache get && cd ..
$ julia --project=.. lean/verify.jl pfr
```

It writes each proof into the project, runs `lake env lean` on it, and fails
if any does not compile. It also drops one hypothesis from a proof and
checks that Lean then *rejects* it, so that a theorem passing for the wrong
reason — because it was vacuous — does not go unnoticed.

Mathlib's prebuilt cache is a few gigabytes; the first `lake exe cache get`
is slow and everything after it is not.

## What the generated theorem says, and what it does not

It says: the statement follows from those particular inequalities by linear
arithmetic, and Lean has checked that it does.

It does not say the variables are entropies. They are plain reals, and the
hypotheses are assumptions. Giving them their meaning takes a bridge, which
connects `h_X_Y` to `H[⟨X, Y⟩]` and discharges each hypothesis from a
library's nonnegativity lemma — `ProbabilityTheory.condMutualInfo_nonneg`
and friends, from [PFR](https://github.com/teorth/pfr) or
[LeanInfoTheory](https://github.com/serhatemrecoban/LeanInfoTheory), since
core Mathlib carries only binary entropy. That bridge is not written yet;
see the documentation page for what it involves.
