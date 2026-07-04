# Changelog

## v0.1.1 (2026-07-04)

### Bug fixes

- Leave a module untouched instead of crashing or misreordering when a
  function's head has no plain name to sort by: an `unquote` or
  `unquote_splicing` fragment, a remote head like `def Foo.bar()`, or a
  bare `def`
- Raise on unparseable input, the same as `mix format` without the
  plugin, so `mix format --check-formatted` still catches syntax errors
  instead of passing a broken file through
- Keep a comment that hugs a function's bottom (a blank line after it,
  none before) with that function when it moves, matching how the base
  formatter groups a comment with the code above it; it rode with the
  following function before

## v0.1.0 (2026-06-07)

Initial release.

- Lay out a module's functions via `mix format`: callbacks (`@impl`) first in
  source order, public functions alphabetical by name and arity, each private
  just below its bottom-most caller (transitive, even through mutual
  recursion)
- Order by AST but move source text by line span, so comments and attached
  `@doc`/`@spec`/`@impl`/`attr`/`slot` ride along with their function
- Pin macros and guards the module uses above the functions, in source
  order; a public one the module provably never uses sorts with the rest
- Lay out nested `defmodule`/`defimpl` bodies, including `defdelegate` and
  `@impl`-tagged implementations
- Skip a module silently and safely when it can't be laid out without risk;
  `mix def_layout.skipped` lists which modules were skipped
- Compose with Quokka or Styler as a `mix format` plugin
