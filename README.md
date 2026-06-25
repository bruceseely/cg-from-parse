# cg-from-parse

Bridge layer that extracts **conceptual graphs** ([`cgraph`](../cgraph)) from
**PARSIFAL** ([`parsifal`](../parsifal)) parse products.

## Why a separate repo

The extraction code conceptually depends on *both* systems, but neither base
system should depend on the other:

```
parsifal   cgraph
    \        /
   cg-from-parse      (depends on both; nothing depends on it)
```

Keeping the glue here leaves `parsifal` and `cgraph` independently loadable,
testable, and releasable, and keeps the dependency graph acyclic. Anyone who
just wants to parse, or just wants conceptual graphs, never pulls in the other.

## Loading

ASDF finds all three systems via the existing source-registry directive
`(:tree "~/repo/")`, which recursively scans `~/repo/` for `.asd` files. As a
sibling repo under `~/repo/`, this system is quickloadable directly:

```lisp
(ql:quickload :cg-from-parse)
```

If ASDF doesn't see it yet, force a rescan with `(asdf:clear-source-registry)`.

## Package boundary

The `:cg-from-parse` package (nickname `:cfp`) uses only `:cl`. Parser and CG
symbols are referenced *qualified* — `pa:…` and `cg:…` — rather than via
`:use`, so every crossing between the two systems is explicit and there are no
symbol conflicts between their large export sets.

## Status

Scaffold only. `cg-from-parse:extract-graph` is the entry point and currently
signals "not yet implemented".

## Tests

```lisp
(asdf:test-system :cg-from-parse)   ; or
(cg-from-parse::test-all t)
```
