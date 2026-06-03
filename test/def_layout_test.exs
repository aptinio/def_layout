defmodule DefLayoutTest do
  use ExUnit.Case, async: true

  defp format(source), do: DefLayout.format(source, [])

  describe "public function ordering" do
    test "two bare publics out of order are sorted alphabetically by name" do
      source = """
      defmodule M do
        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "sorts a different set of names (triangulation)" do
      source = """
      defmodule M do
        def zebra do
          :zebra
        end

        def yak do
          :yak
        end

        def aardvark do
          :aardvark
        end
      end
      """

      expected = """
      defmodule M do
        def aardvark do
          :aardvark
        end

        def yak do
          :yak
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "ties on name break by arity ascending" do
      source = """
      defmodule M do
        def same(a, b) do
          {a, b}
        end

        def same(a) do
          a
        end
      end
      """

      expected = """
      defmodule M do
        def same(a) do
          a
        end

        def same(a, b) do
          {a, b}
        end
      end
      """

      assert format(source) == expected
    end

    test "clauses of one function stay contiguous when the function moves" do
      source = """
      defmodule M do
        def beta(:x), do: 1
        def beta(:y), do: 2

        def alpha(_), do: 0
      end
      """

      expected = """
      defmodule M do
        def alpha(_), do: 0

        def beta(:x), do: 1
        def beta(:y), do: 2
      end
      """

      assert format(source) == expected
    end

    test "a guarded head is ordered by its name" do
      source = """
      defmodule M do
        def beta(x) when is_atom(x) do
          x
        end

        def alpha(x) do
          x
        end
      end
      """

      expected = """
      defmodule M do
        def alpha(x) do
          x
        end

        def beta(x) when is_atom(x) do
          x
        end
      end
      """

      assert format(source) == expected
    end

    test "orders functions whose bodies contain sigils" do
      source = """
      defmodule M do
        def beta do
          ~r/beta/
        end

        def alpha do
          ~r/alpha/
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          ~r/alpha/
        end

        def beta do
          ~r/beta/
        end
      end
      """

      assert format(source) == expected
    end
  end

  describe "comment safety" do
    test "leading comment and @doc/@spec ride along on reorder" do
      source = """
      defmodule M do
        # beta does beta things
        @doc "beta"
        @spec beta() :: :beta
        def beta do
          :beta
        end

        # alpha does alpha things
        @doc "alpha"
        @spec alpha() :: :alpha
        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        # alpha does alpha things
        @doc "alpha"
        @spec alpha() :: :alpha
        def alpha do
          :alpha
        end

        # beta does beta things
        @doc "beta"
        @spec beta() :: :beta
        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "@deprecated and @dialyzer ride along on reorder" do
      source = """
      defmodule M do
        @deprecated "use alpha/0"
        def zebra do
          :zebra
        end

        @dialyzer {:nowarn_function, alpha: 0}
        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @dialyzer {:nowarn_function, alpha: 0}
        def alpha do
          :alpha
        end

        @deprecated "use alpha/0"
        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "attr/slot macros ride along on reorder" do
      source = """
      defmodule M do
        attr :rest, :global
        slot :inner_block

        def beta(assigns) do
          assigns
        end

        attr :name, :string

        def alpha(assigns) do
          assigns
        end
      end
      """

      # `attr`/`slot` ride along verbatim; the trailing formatter pass adds parens
      # only because these opts carry no `:locals_without_parens`.
      expected = """
      defmodule M do
        attr(:name, :string)

        def alpha(assigns) do
          assigns
        end

        attr(:rest, :global)
        slot(:inner_block)

        def beta(assigns) do
          assigns
        end
      end
      """

      assert format(source) == expected
    end

    test "an own-line comment between one-liner defs attaches to the following def" do
      # Ownership of a comment between two adjacent defs is genuinely ambiguous;
      # the movable-block rule resolves it to the *following* def (the comment is
      # that def's leading block), so it rides with `alpha` when it sorts up.
      source = """
      defmodule M do
        def beta, do: :beta
        # a floating note
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        # a floating note
        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a trailing inline comment stays with its own def, never cross-attributed" do
      # The base formatter lifts each trailing comment to a leading line before
      # layout, so the comment rides in its def's span. (The lift is
      # `Code.format_string!`'s normalization, not DefLayout's.)
      source = """
      defmodule M do
        def beta, do: :beta # beta note
        def alpha, do: :alpha # alpha note
      end
      """

      expected = """
      defmodule M do
        # alpha note
        def alpha, do: :alpha

        # beta note
        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a comment between two clauses rides inside the merged group" do
      source = """
      defmodule M do
        def gamma(:a), do: 1
        # gamma handles b
        def gamma(:b), do: 2

        def alpha, do: 0
      end
      """

      expected = """
      defmodule M do
        def alpha, do: 0

        def gamma(:a), do: 1
        # gamma handles b
        def gamma(:b), do: 2
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a comment above @doc rides along with the function" do
      source = """
      defmodule M do
        # zebra is the z one
        @doc "zebra"
        def zebra do
          :zebra
        end

        # alpha is the a one
        @doc "alpha"
        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        # alpha is the a one
        @doc "alpha"
        def alpha do
          :alpha
        end

        # zebra is the z one
        @doc "zebra"
        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a blank line between @spec and its def is preserved as the group moves" do
      # The core formatter keeps a single author blank line between `@spec` and
      # its `def` (decision B: a blank there is a stable, formatter-legal state),
      # so the layout must carry it intact rather than treating it as a boundary.
      source = """
      defmodule M do
        @spec zebra() :: :zebra

        def zebra do
          :zebra
        end

        @spec alpha() :: :alpha

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @spec alpha() :: :alpha

        def alpha do
          :alpha
        end

        @spec zebra() :: :zebra

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end
  end

  describe "plugin contract" do
    test "features/1 declares the .ex/.exs extensions and no sigils" do
      assert DefLayout.features([]) == [extensions: [".ex", ".exs"]]
    end

    test "source that fails to parse is returned unchanged" do
      source = "defmodule M do"

      assert format(source) == source
    end

    test "reorders inside a module while leaving sibling top-level code untouched" do
      source = """
      require Logger

      defmodule M do
        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      require Logger

      defmodule M do
        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "two sibling modules in one file each reorder independently" do
      source = """
      defmodule A do
        def beta, do: :b
        def alpha, do: :a
      end

      defmodule B do
        def zeta, do: :z
        def epsilon, do: :e
      end
      """

      expected = """
      defmodule A do
        def alpha, do: :a

        def beta, do: :b
      end

      defmodule B do
        def epsilon, do: :e

        def zeta, do: :z
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a single-statement module body is left unchanged" do
      source = """
      defmodule M do
        def only do
          :only
        end
      end
      """

      assert format(source) == source
    end
  end

  describe "idempotency" do
    test "an already-sorted module is left unchanged" do
      source = """
      defmodule M do
        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == source
    end

    test "format(format(x)) == format(x) on an unsorted module" do
      source = """
      defmodule M do
        def gamma do
          :gamma
        end

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      once = format(source)
      assert format(once) == once
    end

    test "a dense module (no blank lines between defs) reorders to a fixed point" do
      # Input has zero blank lines between defs; the layout synthesizes the
      # separators, anchors the private under its caller, and the result is a
      # fixed point (re-running adds no further churn).
      source = """
      defmodule M do
        defp helper, do: :ok
        def zebra, do: :z
        def alpha, do: helper()
      end
      """

      expected = """
      defmodule M do
        def alpha, do: helper()

        defp helper, do: :ok

        def zebra, do: :z
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end
  end

  # Out-of-scope constructs (callbacks, interleaved statements) leave the module
  # in source order, still canonically formatted.
  describe "silent bail (out of strict scope)" do
    test "a callback leaves public order untouched" do
      source = """
      defmodule M do
        @impl true
        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == source
    end

    test "a statement interleaved among functions leaves order untouched" do
      source = """
      defmodule M do
        def beta do
          :beta
        end

        @some_attr :x

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == source
    end

    test "a defmacro interleaved among defs leaves order untouched" do
      # `defmacro` isn't in the reorderable def-family, so once it sits between
      # functions it's an interleaved non-def statement: the module bails rather
      # than permute defs around a macro whose define-before-use position matters.
      source = """
      defmodule M do
        def beta, do: :b

        defmacro mac(x), do: x

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end
  end

  # The plugin formats before laying out, so layout decisions run on
  # formatter-stable text: a shape the base formatter rewrites (`;`-joined
  # defs) can't bail on one pass and lay out on the next - a single pass
  # reaches the fixed point.
  describe "formats before laying out" do
    test "two defs sharing one source line are split and laid out" do
      source = """
      defmodule M do
        def beta, do: :beta; def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
    end

    test "a def sharing the header's last line is split and laid out" do
      source = """
      defmodule M do
        @moduledoc false; def beta, do: :b
        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        @moduledoc false
        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
    end
  end

  # Shapes that would corrupt or crash the line-span splice if reordered, so the
  # scanner bails: the module is formatted but left in source order.
  describe "safety bail (would otherwise corrupt or crash)" do
    test "a keyword-form defmodule bails rather than crashing" do
      source = "defmodule M, do: (def beta, do: :b; def alpha, do: :a)\n"

      expected = """
      defmodule M,
        do:
          (
            def beta, do: :b
            def alpha, do: :a
          )
      """

      assert format(source) == expected
    end

    test "non-adjacent clauses of one function bail rather than scramble" do
      # The scanner only merges *adjacent* same-key clauses, so `foo/1` split by
      # `bar` leaves two `foo/1` groups. Reordering them would break clause-match
      # order (semantic corruption), so the module bails and keeps source order -
      # even though `bar` sorts before `foo`.
      source = """
      defmodule M do
        def foo(:a), do: 1
        def bar, do: 2
        def foo(:b), do: 3
      end
      """

      assert format(source) == source
    end
  end

  describe "private placement" do
    test "a private moves just below its single caller" do
      source = """
      defmodule M do
        defp helper do
          :ok
        end

        def beta do
          helper()
        end
      end
      """

      expected = """
      defmodule M do
        def beta do
          helper()
        end

        defp helper do
          :ok
        end
      end
      """

      assert format(source) == expected
    end

    test "a private interleaves below its caller, not floated by its name" do
      source = """
      defmodule M do
        defp aaa_helper do
          :ok
        end

        def zebra do
          :zebra
        end

        def alpha do
          aaa_helper()
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          aaa_helper()
        end

        defp aaa_helper do
          :ok
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a private called only by another private rides below it (transitive)" do
      source = """
      defmodule M do
        defp leaf do
          :leaf
        end

        defp mid do
          leaf()
        end

        def top do
          mid()
        end
      end
      """

      expected = """
      defmodule M do
        def top do
          mid()
        end

        defp mid do
          leaf()
        end

        defp leaf do
          :leaf
        end
      end
      """

      assert format(source) == expected
    end

    test "co-anchored privates follow the caller's first-call-site order" do
      source = """
      defmodule M do
        defp aaa do
          :aaa
        end

        defp bbb do
          :bbb
        end

        def caller do
          bbb()
          aaa()
        end
      end
      """

      expected = """
      defmodule M do
        def caller do
          bbb()
          aaa()
        end

        defp bbb do
          :bbb
        end

        defp aaa do
          :aaa
        end
      end
      """

      assert format(source) == expected
    end

    test "a private shared by two publics sinks below the bottom-most caller" do
      source = """
      defmodule M do
        defp shared do
          :shared
        end

        def alpha do
          shared()
        end

        def zebra do
          shared()
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          shared()
        end

        def zebra do
          shared()
        end

        defp shared do
          :shared
        end
      end
      """

      assert format(source) == expected
    end

    test "an orphan private falls back to the end in source order" do
      source = """
      defmodule M do
        defp orphan do
          :orphan
        end

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          :alpha
        end

        def beta do
          :beta
        end

        defp orphan do
          :orphan
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a recursion cycle is broken below its caller-reachable member" do
      source = """
      defmodule M do
        defp pong do
          ping()
        end

        defp ping do
          pong()
        end

        def zebra do
          ping()
        end

        def alpha do
          :alpha
        end
      end
      """

      # `ping` is reachable from public `zebra`, so the cycle anchors there:
      # `ping` below `zebra`, then `pong` below `ping`.
      expected = """
      defmodule M do
        def alpha do
          :alpha
        end

        def zebra do
          ping()
        end

        defp ping do
          pong()
        end

        defp pong do
          ping()
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a non-cycle private blocked by a cycle anchors to its true caller" do
      # `c` is not in the `a <-> b` cycle, only blocked by it (its caller `a` is
      # a cycle member). It must wait for the cycle to resolve and then anchor to
      # its true bottom-most caller `a` - not get grabbed early by source position
      # (which made placement non-idempotent before the cycle-member fix).
      source = """
      defmodule Demo do
        def r do
          b()
          c()
        end

        def s do
          a()
        end

        defp c, do: :ok
        defp b, do: a()

        defp a do
          b()
          c()
        end
      end
      """

      expected = """
      defmodule Demo do
        def r do
          b()
          c()
        end

        def s do
          a()
        end

        defp a do
          b()
          c()
        end

        defp b, do: a()

        defp c, do: :ok
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a multi-entry cycle reaches the same fixed point from any source order" do
      # `a -> b -> c -> a`, entered by both `p -> a` and `q -> b`. The cycle is
      # broken by key (not source order), so the two scramblings converge.
      v1 = """
      defmodule Multi do
        def p, do: a()
        def q, do: b()
        defp a, do: b()
        defp b, do: c()
        defp c, do: a()
      end
      """

      v2 = """
      defmodule Multi do
        def p, do: a()
        def q, do: b()
        defp c, do: a()
        defp b, do: c()
        defp a, do: b()
      end
      """

      formatted = format(v1)
      assert format(v2) == formatted
      assert format(formatted) == formatted
    end

    test "a private called through a pipe anchors below the piping caller" do
      # `x |> helper()` calls `helper/1`; the piped arg must count toward arity,
      # else `helper/1` looks like an orphan and sinks to the module tail.
      source = """
      defmodule PipeDemo do
        def alpha(x) do
          x |> helper()
        end

        def zeta do
          :zeta
        end

        defp helper(x) do
          x
        end
      end
      """

      expected = """
      defmodule PipeDemo do
        def alpha(x) do
          x |> helper()
        end

        defp helper(x) do
          x
        end

        def zeta do
          :zeta
        end
      end
      """

      assert format(source) == expected
    end

    test "a private referenced only by capture anchors below the capturing caller" do
      source = """
      defmodule M do
        defp helper(x) do
          x
        end

        def alpha(list) do
          Enum.map(list, &helper/1)
        end

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        def alpha(list) do
          Enum.map(list, &helper/1)
        end

        defp helper(x) do
          x
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a private's leading comment and @spec ride along as it sinks" do
      source = """
      defmodule M do
        # helper does the work
        @spec helper() :: :ok
        defp helper do
          :ok
        end

        def run do
          helper()
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          helper()
        end

        # helper does the work
        @spec helper() :: :ok
        defp helper do
          :ok
        end
      end
      """

      assert format(source) == expected
    end
  end

  # Known scanner limitations: the call-graph is built from source AST without
  # arity-range or scope analysis, so a few constructs anchor a private somewhere
  # other than its true caller. None corrupt or crash - the layout stays a fixed
  # point - so these lock the current SAFE behavior against silent regression.
  describe "scanner limitations (safe mis-placement)" do
    test "a default-arg private called at a lower arity tails as an orphan" do
      # `helper/1` (one defaulted param) called as `helper()` records a `helper/0`
      # edge, which doesn't match the `helper/1` key - so the call graph sees no
      # caller and `helper` sinks to the module tail instead of under `alpha`.
      # Safe: orphan fallback, never corruption. (Fixable later via arity ranges.)
      source = """
      defmodule M do
        defp helper(x \\\\ :ok) do
          x
        end

        def alpha do
          helper()
        end

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          helper()
        end

        def zebra do
          :zebra
        end

        defp helper(x \\\\ :ok) do
          x
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a name referenced only inside a quote is over-collected as a call edge" do
      # `gen`'s body returns `quote(do: leaf())` - quoted code, not a runtime call -
      # but `collect_calls` is name-blind and records a `gen -> leaf` edge anyway.
      # So `leaf` anchors below `gen` (its spurious bottom-most caller) rather than
      # below `aaa`, which actually calls it. Safe mis-anchor, still idempotent.
      # (The collector is uniformly name-blind, so a `defp` shadowing a special
      # form would over-collect the same way - cursor#2.)
      source = """
      defmodule M do
        defp leaf do
          :leaf
        end

        defp gen do
          quote do
            leaf()
          end
        end

        def aaa do
          leaf()
        end

        def zzz do
          gen()
        end
      end
      """

      expected = """
      defmodule M do
        def aaa do
          leaf()
        end

        def zzz do
          gen()
        end

        defp gen do
          quote do
            leaf()
          end
        end

        defp leaf do
          :leaf
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end
  end

  describe "module header" do
    test "a @behaviour declaration in the header still reorders" do
      source = """
      defmodule M do
        @behaviour GenServer

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @behaviour GenServer

        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "module-level type and callback attributes in the header still reorder" do
      source = """
      defmodule M do
        @type t :: :alpha | :beta
        @callback init(t) :: t

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @type t :: :alpha | :beta
        @callback init(t) :: t

        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "a defstruct in the header still reorders" do
      source = """
      defmodule M do
        @enforce_keys [:name]
        defstruct [:name, :age]

        def beta(s) do
          s
        end

        def alpha(s) do
          s
        end
      end
      """

      expected = """
      defmodule M do
        @enforce_keys [:name]
        defstruct [:name, :age]

        def alpha(s) do
          s
        end

        def beta(s) do
          s
        end
      end
      """

      assert format(source) == expected
    end

    test "a header of recognized module-level constructs still reorders" do
      source = """
      defmodule M do
        @moduledoc "M"
        import Bar

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @moduledoc "M"
        import Bar

        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "an unrecognized module attribute in the header bails (no stranding)" do
      source = """
      defmodule M do
        @timeout 5_000

        def beta do
          @timeout
        end

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == source
    end

    test "module-level compile hooks in the header still reorder" do
      source = """
      defmodule M do
        @compile {:inline, alpha: 0}
        @before_compile Hooks
        @after_compile Hooks
        @after_verify Hooks
        @on_load :setup
        @vsn "1.0.0"
        @external_resource "priv/data"

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @compile {:inline, alpha: 0}
        @before_compile Hooks
        @after_compile Hooks
        @after_verify Hooks
        @on_load :setup
        @vsn "1.0.0"
        @external_resource "priv/data"

        def alpha do
          :alpha
        end

        def beta do
          :beta
        end
      end
      """

      assert format(source) == expected
    end

    test "the remaining recognized header attributes still reorder" do
      # Every name is load-bearing: if any weren't recognized, the header would
      # fail `header_safe?` and the module would bail instead of reordering.
      source = """
      defmodule M do
        @behavior GenServer
        @typep tp :: :x
        @opaque op :: :y
        @macrocallback mc(integer) :: Macro.t()
        @optional_callbacks mc: 1
        @derive Jason.Encoder
        defexception [:message]

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        @behavior GenServer
        @typep tp :: :x
        @opaque op :: :y
        @macrocallback mc(integer) :: Macro.t()
        @optional_callbacks mc: 1
        @derive Jason.Encoder
        defexception [:message]

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
    end

    test "a realistic mixed header reorders and is a fixed point" do
      source = """
      defmodule M do
        @moduledoc "M"
        use GenServer
        @behaviour GenServer

        @enforce_keys [:name]
        defstruct [:name]

        @type t :: %__MODULE__{name: String.t()}

        def beta(%__MODULE__{} = s) do
          s
        end

        def alpha(%__MODULE__{} = s) do
          s
        end
      end
      """

      expected = """
      defmodule M do
        @moduledoc "M"
        use GenServer
        @behaviour GenServer

        @enforce_keys [:name]
        defstruct [:name]

        @type t :: %__MODULE__{name: String.t()}

        def alpha(%__MODULE__{} = s) do
          s
        end

        def beta(%__MODULE__{} = s) do
          s
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a nested module in the body bails (outer left untouched)" do
      # A nested `defmodule` is an unrecognized construct sitting among the defs,
      # so the outer module bails. The inner module isn't a top-level expr, so it
      # isn't separately reordered either - the whole thing keeps source order.
      source = """
      defmodule Outer do
        def beta, do: :b

        defmodule Inner do
          def y, do: :y
          def x, do: :x
        end

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "an unrecognized macro in the header bails" do
      source = """
      defmodule M do
        plug(:authenticate)

        def beta do
          :beta
        end

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == source
    end

    test "a recognized attribute interleaved after the first def still bails" do
      # `@type` is header-safe, but only as a *header* statement. Once it sits
      # between defs it can't ride a moving function, so the module must bail.
      source = """
      defmodule M do
        def beta do
          :beta
        end

        @type t :: :x

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == source
    end
  end
end
