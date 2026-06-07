# Changelog

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
