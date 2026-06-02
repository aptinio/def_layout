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
  end

  # Slice 1 only reorders modules that are purely public defs + attachments.
  # Anything else is left in source order (still canonically formatted).
  describe "silent bail (out of strict scope)" do
    test "a private definition leaves public order untouched" do
      source = """
      defmodule M do
        def beta do
          :beta
        end

        def alpha do
          :alpha
        end

        defp helper do
          :helper
        end
      end
      """

      assert format(source) == source
    end

    test "a private definition ahead of the publics still bails" do
      source = """
      defmodule M do
        defp helper do
          :helper
        end

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
