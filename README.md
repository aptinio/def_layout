# DefLayout

[![CI](https://github.com/aptinio/def_layout/actions/workflows/ci.yml/badge.svg)](https://github.com/aptinio/def_layout/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/def_layout.svg)](https://hex.pm/packages/def_layout)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/def_layout/)

Lays out a module's functions via `mix format`: callbacks first,
public functions alphabetical, each private function just below its
bottom-most caller.

## Why

Where a public function sits in a file changes nothing at runtime.
Ordering it by hand is a recurring decision with only an aesthetic
payoff, one you then maintain forever and re-litigate in review.
DefLayout removes the decision. A formatter, for one specific thing.
The same pass puts every private helper directly below its bottom-most
caller - the part hardly anyone argues with, and the part
hand-ordering never keeps true for long.

If you think public function order carries meaning worth maintaining
by hand, this isn't the tool for you. That's by design.

## The layout

The rule is to use the most meaningful order a formatter can deliver
and fall back to alphabetical.

1. **Callbacks** (`@impl`) come first and keep their source order.
   `init`, `handle_call`, `terminate` is a lifecycle; that's the one
   place order carries information. A callback you haven't tagged
   with `@impl` sorts with the publics.
2. **Public functions** follow, alphabetical by name and arity. Their
   position is behavior-neutral, so it sorts. A `defdelegate` not
   tagged `@impl` is just a public and sorts by its local name.
3. **Private functions** sink just below their bottom-most caller,
   transitively. A helper lives directly under what uses it, even if
   that puts it between two callbacks.

Macros and guards have a rule of their own: they're define-before-use,
so their position is load-bearing exactly when the module itself uses
one. Used ones are pinned, in source order, above the functions; a
public one the module provably never uses is just another public and
sorts with the rest.
`__using__` is the classic case - defined for other modules, inert at
home - which is why a Phoenix `_web.ex` lays out.

Nested modules don't move. When they bracket the functions - above
the first or below the last - they're frozen anchors, and the
functions lay out between them. When one sits among the functions
instead, the outer module is skipped: moving a def across it can
silently change which module a name resolves to.

Inside a nested `defmodule` or `defimpl`, the body is just a module
body and gets the full layout of its own. That makes `defimpl` blocks
unremarkable: implementations tagged `@impl` keep their source order,
untagged ones sort with the publics, privates sink. (`defprotocol`
bodies are signatures, not implementations; those stay untouched.)

Here's the sharpest case, the reorder a skeptic points at first:

```elixir
# before (hand-ordered)
def start_link    # the entry point, conventionally first

@impl GenServer
def init

@impl GenServer
def handle_call({:get, key}, _from, state) do
  {:reply, fetch(state, key), state}
end

def take
def get
defp fetch
```

```elixir
# after
@impl GenServer   # callbacks first, in source order
def init          # (alphabetical would flip these two)

@impl GenServer   # the attribute rides along
def handle_call({:get, key}, _from, state) do
  {:reply, fetch(state, key), state}
end

defp fetch        # private, sinks under its caller

def get           # ┐ publics,
def start_link    # │ alphabetical
def take          # ┘
```

Yes, `start_link` lands mid-pack, wherever the alphabet drops it.
That's the honest cost of the rule, shown up front. Once you know
publics are alphabetical you stop scanning for `start_link`; you jump
to it. (For why `start_link` sorts but `init` doesn't, see the FAQ.)

Public alphabetization is the half people argue about. The other half
is harder to argue with: each private function directly under its
bottom-most caller means you read a function and its helpers are
right there, in call order, instead of scattered across the file or
piled at the bottom. This half pays for itself on any module with
helpers.

The output is a deterministic, idempotent fixed point, not a canonical
form: callbacks keep their source order, and a private whose caller
DefLayout can't see (it only sees local calls, matched by name and
arity) drops to the bottom in source order. What's guaranteed is that
formatting twice gives you the same file.

## Why this doesn't exist already

Styler and Quokka reorder the directive block (`@moduledoc`, `use`,
`import`, `alias`, `require`) and leave the functions below in source
order. They work by rewriting the AST, and Elixir's
AST doesn't hold comments: they ride in a separate list, anchored by
line number. Re-homing them survives a directive shuffle at the top
of a module; move whole functions around and comments land on the
wrong code.

DefLayout orders by AST but moves source text by line span, so
comments and attached `@doc`/`@spec`/`@impl`/`attr`/`slot` ride along
with their function. That's the whole trick, and the reason def
reordering can exist at all. Quokka orders your directives;
DefLayout orders the rest. They compose (this repo runs both).

Credo's `StrictModuleLayout` warns rather than rewrites, and the
layout it can check for is a different one: contiguous tiers, all
publics then all privates, where DefLayout deliberately interleaves.
The two coexist as long as you don't add function parts to its
`:order` (the default leaves them out).

## Tested on real code

Fourteen codebases: Phoenix and LiveView apps, macro-heavy DSLs
(Ash, Absinthe), libraries from Plug to Nx, and my own production
code - 5,168 source files. Every file came out reorder-only against
a freshly formatted baseline (the diff is positions, never content),
def-for-def intact, and stable under a second pass. Ten of those
codebases also ran end to end through the real `mix format`: 1,459
files came out reordered, and every one still compiled. Same results
on Elixir 1.19 and 1.20; CI runs the suite on four Elixir/OTP pairs,
1.16/OTP 26 through 1.20/OTP 29.

The sweep is `scripts/standalone.exs` - point it at any codebase
(`mix run scripts/standalone.exs PATH`) and check the claims yourself.

## Setup

Requires Elixir 1.16+.

Add `def_layout` to your dependencies:

```elixir
# mix.exs
defp deps do
  [
    {:def_layout, "~> 0.1.0", only: [:dev, :test], runtime: false}
  ]
end
```

Then add it to your `.formatter.exs` plugins:

```elixir
# .formatter.exs
[
  plugins: [DefLayout],
  # ...
]
```

`mix format` now lays out your modules. If you also run Quokka or
Styler, list DefLayout first so the other plugin formats last and its
conventions win the final output.

On an existing codebase, run the first pass on a branch and read the
diff: if the code was already formatted, the pass only moves lines,
it never edits them, so the diff is easy to judge. On code the
formatter has never touched, the same pass also settles the usual
formatter churn - that part isn't the reordering. If a module you
expected to change didn't, `mix def_layout.skipped` lists what was
left alone and why.

### Using Styler? Pin `line_length`

DefLayout formats through the standard formatter, which wraps at 98
columns by default; Styler defaults to 122. If your `.formatter.exs`
pins neither, the two disagree and your first run drowns in
line-wrapping churn that has nothing to do with reordering. Pin a
width and both respect it:

```elixir
# .formatter.exs
[
  plugins: [DefLayout, Styler],
  line_length: 122
]
```

### What gets skipped

DefLayout reorders a module only when it can do so safely. A module
with anything it can't confidently classify next to a moving
function - an unrecognized construct above the first def,
expressions interleaved among the functions, a nested module among
them - is skipped. In practice that includes most DSL-heavy
modules (an Ecto `schema`, a `plug` pipeline).
Skips are per module body, not per file: sibling modules in the same
file still get the full layout, and a skipped outer doesn't stop its
nested modules' bodies from getting theirs. A skipped module still
gets formatted, just not laid out, so the worst case is exactly what
`mix format` already does. The skip is silent: if a module you
expected to change didn't, it contains something DefLayout won't
move things across. Run `mix def_layout.skipped` to list which
modules are being skipped and why.

One macro placement triggers the skip: the module uses one of its
own macros or guards, but the definition sits below the first def
(think a `defmacrop` next to the queries it powers). That adjacency
is usually deliberate, and DefLayout won't guess. Extracting macros
to a dedicated module - the pattern the `defguard` docs themselves
model - restores the full layout on both sides: the consumer's
compile-time dependencies become header directives, and the
extracted macros are inert at home, so they sort. The cost is that
private macros must go public to cross the module boundary.

The fine print, for macro-heavy modules: when DefLayout can't tell
whether a macro is used (a name that only appears inside a `quote`,
a variable sharing the name), it pins the macro - the macro stays
above the functions, as if used, and the module still lays out. The cost of
that caution is a macro that needlessly stays pinned, never a broken
build. A module that calls one of its own `defmacro`s heightens the
caution: the expansion runs during the module's compile
and produces code the formatter never sees - code that could invoke
any macro in the module - so every macro stays pinned and none
sorts. And when the expanding macro's own expansion-time code - its
body outside `quote`, an `unquote` argument - calls one of the
module's functions, the module is skipped: that function has to stay
above the expansion site, a constraint placement can't honor.

One limit DefLayout can't see past is `use`. It can register an
`@on_definition` hook invisibly (decorator-style libraries do).
That hook fires per def in definition order and can read per-def
attributes, so a reorder changes what it observes. A module
declaring `@on_definition` directly is skipped; one acquiring it
through `use` looks ordinary.

## FAQ

### `start_link` should be first. It's the entry point.

`start_link` isn't a callback. It's not in GenServer's `@callback`s;
the generated `child_spec` references it by name
(`start: {__MODULE__, :start_link, [init_arg]}`), so its position in
the file is behavior-neutral. "First" is reading habit, not a contract.

That's the principle behind the whole layout: if the framework
formalized it (a real `@impl` callback), it keeps its order; if it's
convention (invoked by name, placement irrelevant), it sorts.

### It puts `application` before `project` in `mix.exs`.

Same thing. `Mix.Project` isn't a behaviour; Mix calls `project/0` and
`application/0` reflectively by name. Convention, so they sort. This
repo's own `mix.exs` is laid out that way.

### Why alphabetical and not most-important-first?

Because "important" is subjective and not machine-derivable; a
deterministic tool can't honor it without growing a config surface
that defeats the point. Alphabetical is the one public order that's
stable, zero-config, and findable.

### Can I get a setting to preserve my public order?

No. A preserve-order toggle only serves people who reject the premise,
and using a tool while fighting its one opinion isn't worth the
config surface. The opinion is the product.

### Have you actually run this on your own code?

I was skeptical of alphabetical publics myself. I expected to hate
seeing `start_link` sort away from the top of a GenServer, and I
came in willing to add a config knob to preserve public order. Then
I ran it across my own production codebase: the private-helper
layout was an immediate win, and the public reordering bothered me
far less than I expected. The one thing that nagged, `start_link`
not on top, turned out to be a convention I'd been hand-maintaining
for no reason; the framework doesn't care where it sits. Looking at
my own code talked me out of the knob.

And this repo formats itself with DefLayout.
