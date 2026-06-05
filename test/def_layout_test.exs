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

  describe "callbacks first" do
    test "a callback sorts above a public whose name sorts earlier" do
      source = """
      defmodule M do
        def alpha do
          :alpha
        end

        @impl true
        def zzz do
          :zzz
        end
      end
      """

      expected = """
      defmodule M do
        @impl true
        def zzz do
          :zzz
        end

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == expected
    end

    test "two callbacks keep their source order, not alphabetical" do
      source = """
      defmodule M do
        @impl true
        def zzz do
          :zzz
        end

        @impl true
        def aaa do
          :aaa
        end
      end
      """

      assert format(source) == source
    end

    test "callbacks first, then alphabetical publics, then privates" do
      source = """
      defmodule M do
        def zebra do
          :zebra
        end

        defp helper do
          :helper
        end

        @impl true
        def terminate(_reason, _state) do
          helper()
        end

        def alpha do
          :alpha
        end

        @impl true
        def init(arg) do
          {:ok, arg}
        end
      end
      """

      expected = """
      defmodule M do
        @impl true
        def terminate(_reason, _state) do
          helper()
        end

        defp helper do
          :helper
        end

        @impl true
        def init(arg) do
          {:ok, arg}
        end

        def alpha do
          :alpha
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a private called only by a callback anchors below it" do
      source = """
      defmodule M do
        defp via_callback do
          :ok
        end

        def alpha do
          :alpha
        end

        @impl true
        def handle_info(_msg, state) do
          via_callback()
          {:noreply, state}
        end
      end
      """

      expected = """
      defmodule M do
        @impl true
        def handle_info(_msg, state) do
          via_callback()
          {:noreply, state}
        end

        defp via_callback do
          :ok
        end

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == expected
    end

    test "@impl false is a normal public, not hoisted as a callback" do
      # `@impl false` is an explicit *non*-callback marker (Elixir errors if it
      # actually matches a callback), so it must stay in the alphabetical public
      # section - never the callbacks-first prefix.
      source = """
      defmodule M do
        @impl false
        def zzz do
          :zzz
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

        @impl false
        def zzz do
          :zzz
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a moving callback carries its leading comment, @impl, and @spec" do
      source = """
      defmodule M do
        def alpha do
          :alpha
        end

        # mounts the thing
        @impl true
        @spec mount(map) :: {:ok, map}
        def mount(socket) do
          {:ok, socket}
        end
      end
      """

      expected = """
      defmodule M do
        # mounts the thing
        @impl true
        @spec mount(map) :: {:ok, map}
        def mount(socket) do
          {:ok, socket}
        end

        def alpha do
          :alpha
        end
      end
      """

      assert format(source) == expected
    end
  end

  # Out-of-scope constructs (interleaved statements) leave the module in source
  # order - still run through the base formatter, just not reordered.
  describe "pinned macros and guards" do
    test "a macro above the first def stays pinned while publics sort below it" do
      source = """
      defmodule M do
        defmacro mac(x), do: x

        def beta, do: mac(1)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro mac(x), do: x

        def alpha, do: :a

        def beta, do: mac(1)
      end
      """

      assert format(source) == expected
    end

    test "a pinned module is a fixed point" do
      source = """
      defmodule M do
        defmacro mac(x), do: x

        def alpha, do: :a

        def beta, do: mac(1)
      end
      """

      assert format(source) == source
    end

    test "a guard used in a def head stays pinned" do
      source = """
      defmodule M do
        defguard is_small(x) when x < 10

        def beta(x) when is_small(x), do: x

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defguard is_small(x) when x < 10

        def alpha, do: :a

        def beta(x) when is_small(x), do: x
      end
      """

      assert format(source) == expected
    end

    test "private macros pin like public ones" do
      source = """
      defmodule M do
        defmacrop double(x), do: quote(do: 2 * unquote(x))

        def beta, do: double(2)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacrop double(x), do: quote(do: 2 * unquote(x))

        def alpha, do: :a

        def beta, do: double(2)
      end
      """

      assert format(source) == expected
    end

    test "attachments stay with the pin and ride with the moving def" do
      source = """
      defmodule M do
        @doc "expands to its argument"
        defmacro mac(x), do: x

        @doc "calls the macro"
        def beta, do: mac(1)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        @doc "expands to its argument"
        defmacro mac(x), do: x

        def alpha, do: :a

        @doc "calls the macro"
        def beta, do: mac(1)
      end
      """

      assert format(source) == expected
    end

    test "a multi-clause macro pins as one group" do
      source = """
      defmodule M do
        defmacro mac(0), do: 0
        defmacro mac(x), do: x

        def beta, do: mac(1)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro mac(0), do: 0
        defmacro mac(x), do: x

        def alpha, do: :a

        def beta, do: mac(1)
      end
      """

      assert format(source) == expected
    end

    test "several pins keep their source order" do
      source = """
      defmodule M do
        defmacro zeta(x), do: x

        defguard is_small(x) when x < 10

        def beta(x) when is_small(x), do: zeta(x)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro zeta(x), do: x

        defguard is_small(x) when x < 10

        def alpha, do: :a

        def beta(x) when is_small(x), do: zeta(x)
      end
      """

      assert format(source) == expected
    end

    test "a macro-only module stays untouched" do
      source = """
      defmodule M do
        defmacro zeta(x), do: x

        defmacro alpha(x), do: quote(do: unquote(zeta(x)))
      end
      """

      assert format(source) == source
    end

    test "a used macro below the first def bails" do
      # Repositioning it (or permuting defs around it) safely would require
      # edge-accurate movement - a scanner miss would be a compile error, not a
      # cosmetic miss - so the module keeps source order.
      source = """
      defmodule M do
        def beta, do: :b

        defmacro mac(x), do: x

        def alpha, do: mac(:a)
      end
      """

      assert format(source) == source
    end

    test "a def sharing the last pin's line is split and laid out" do
      source = """
      defmodule M do
        defmacro mac(x), do: x; def beta, do: mac(:b)
        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro mac(x), do: x

        def alpha, do: :a

        def beta, do: mac(:b)
      end
      """

      assert format(source) == expected
    end

    test "a private called only from a pin's quote tails as an orphan" do
      # Pins never anchor privates: a private lifted into the pinned tier could
      # land above a later pin it uses (define-before-use break), so a private
      # whose only reference sits in a pinned macro's quote falls back to the
      # source-order tail instead.
      source = """
      defmodule M do
        defmacro mac do
          quote do
            helper()
          end
        end

        def beta, do: mac()

        def alpha, do: :a

        defp helper, do: :h
      end
      """

      expected = """
      defmodule M do
        defmacro mac do
          quote do
            helper()
          end
        end

        def alpha, do: :a

        def beta, do: mac()

        defp helper, do: :h
      end
      """

      assert format(source) == expected
    end

    test "arity-range resolution does not make a pin anchor a defaulted private" do
      # Same shape with a defaulted head: the quoted `helper()` now resolves
      # into `helper/1`'s range, but pins still never anchor, so the private
      # still tails instead of landing under the macro.
      source = """
      defmodule M do
        defmacro mac do
          quote do
            helper()
          end
        end

        def beta, do: mac()

        def alpha, do: :a

        defp helper(x \\\\ :ok), do: x
      end
      """

      expected = """
      defmodule M do
        defmacro mac do
          quote do
            helper()
          end
        end

        def alpha, do: :a

        def beta, do: mac()

        defp helper(x \\\\ :ok), do: x
      end
      """

      assert format(source) == expected
    end
  end

  describe "silent bail (interleaved attribute)" do
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
  end

  # A public macro/guard the module provably never uses is position-free, so
  # it's just a public: it sorts by `{name, arity}`. Inert is decided by a
  # conservative whole-module scan - its name occurs nowhere outside its own
  # group, and its own group references no in-module compile-time name. Every
  # doubt (quote contents, variables sharing the name, atom literals) resolves
  # to "used" -> pinned, so the failure direction is over-pinning, never a
  # define-before-use break.
  describe "inert macro sorting" do
    test "an inert macro between defs sorts with the publics" do
      source = """
      defmodule M do
        def beta, do: :b

        defmacro mac(x), do: x

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :a

        def beta, do: :b

        defmacro mac(x), do: x
      end
      """

      assert format(source) == expected
    end

    test "an inert macro above the first def sorts down" do
      source = """
      defmodule M do
        defmacro zeta(x), do: x

        def alpha, do: :a

        def beta, do: :b
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :a

        def beta, do: :b

        defmacro zeta(x), do: x
      end
      """

      assert format(source) == expected
    end

    test "a _web.ex-style module lays out: __using__ sorts first, helpers anchor" do
      source = """
      defmodule M do
        def controller do
          quote do
            unquote(html_helpers())
          end
        end

        defmacro __using__(which) when is_atom(which) do
          apply(__MODULE__, which, [])
        end

        defp html_helpers do
          quote do
            :helpers
          end
        end
      end
      """

      expected = """
      defmodule M do
        defmacro __using__(which) when is_atom(which) do
          apply(__MODULE__, which, [])
        end

        def controller do
          quote do
            unquote(html_helpers())
          end
        end

        defp html_helpers do
          quote do
            :helpers
          end
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a multi-clause inert macro sorts as one group with its attachments" do
      source = """
      defmodule M do
        @doc "expands to its argument"
        defmacro zeta(0), do: 0
        defmacro zeta(x), do: x

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :a

        @doc "expands to its argument"
        defmacro zeta(0), do: 0
        defmacro zeta(x), do: x
      end
      """

      assert format(source) == expected
    end

    test "an inert macro anchors a private referenced in its quote" do
      # Unlike pins, a sorted macro is a regular root: nothing in the module
      # references it, so a private under it can never be lifted above a
      # compile-time definition it needs.
      source = """
      defmodule M do
        defmacro zeta do
          quote do
            unquote(helper())
          end
        end

        def alpha, do: :a

        defp helper, do: :h
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :a

        defmacro zeta do
          quote do
            unquote(helper())
          end
        end

        defp helper, do: :h
      end
      """

      assert format(source) == expected
    end

    test "an @impl macro joins the callbacks tier" do
      source = """
      defmodule M do
        def beta, do: :b

        @impl true
        defmacro zeta(x), do: x

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        @impl true
        defmacro zeta(x), do: x

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
    end

    test "pins compact upward past a departing inert macro" do
      # The pin only ever jumps over inert macros sorting away below it -
      # nothing it depends on, so define-before-use holds.
      source = """
      defmodule M do
        defmacro zeta(x), do: x

        defguard is_small(x) when x < 10

        def beta(x) when is_small(x), do: x

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defguard is_small(x) when x < 10

        def alpha, do: :a

        def beta(x) when is_small(x), do: x

        defmacro zeta(x), do: x
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a variable sharing the macro's name pins it" do
      # The scan can't cheaply tell a variable from a bare reference, so the
      # name occurring at all counts as use.
      source = """
      defmodule M do
        defmacro zeta, do: :z

        def beta do
          zeta = 1
          zeta + 1
        end

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro zeta, do: :z

        def alpha, do: :a

        def beta do
          zeta = 1
          zeta + 1
        end
      end
      """

      assert format(source) == expected
    end

    test "a reference inside a quote pins the macro" do
      source = """
      defmodule M do
        defmacro zeta(x), do: x

        def beta do
          quote do
            zeta(1)
          end
        end

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro zeta(x), do: x

        def alpha, do: :a

        def beta do
          quote do
            zeta(1)
          end
        end
      end
      """

      assert format(source) == expected
    end

    test "an atom literal sharing the macro's name pins it" do
      source = """
      defmodule M do
        defmacro zeta(x), do: x

        def beta, do: Keyword.get([], :zeta)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro zeta(x), do: x

        def alpha, do: :a

        def beta, do: Keyword.get([], :zeta)
      end
      """

      assert format(source) == expected
    end

    test "a use of the module itself never pins __using__" do
      # `use M` expands `__using__` without the name appearing - but a
      # non-quoted in-module use/import/require of self is a compile error
      # ("currently being defined"), and a quoted one expands in another
      # module where this one is already loaded, so `__using__`'s position is
      # never load-bearing in compilable code. No self-use rule needed; the
      # callback discriminates (pinned would keep `__using__` above it).
      source = """
      defmodule M do
        defmacro __using__(_opts) do
          quote do
            :ok
          end
        end

        @impl true
        def init(_state), do: :ok

        def beta do
          quote do
            use unquote(__MODULE__)
          end
        end
      end
      """

      expected = """
      defmodule M do
        @impl true
        def init(_state), do: :ok

        defmacro __using__(_opts) do
          quote do
            :ok
          end
        end

        def beta do
          quote do
            use unquote(__MODULE__)
          end
        end
      end
      """

      assert format(source) == expected
    end

    test "a self-referencing after_compile hook's function sorts freely" do
      # `@after_compile __MODULE__` invokes the `__after_compile__/2` function
      # after compilation, so its position is free and it sorts like any
      # public. (No macro equivalent exists: `@before_compile __MODULE__` and
      # `@on_definition __MODULE__` are compile errors - a module can't invoke
      # itself mid-compile, the same reason no `use`-self rule is needed.)
      source = """
      defmodule M do
        @after_compile __MODULE__

        def beta, do: :b

        def __after_compile__(_env, _bytecode), do: :ok

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        @after_compile __MODULE__

        def __after_compile__(_env, _bytecode), do: :ok

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
    end

    test "an expanded macro suppresses sorting: its expansion could hide a macro call" do
      # `gen` expands during this module's compile (beta invokes it outside any
      # quote), and an expansion runs arbitrary code - here it synthesizes a
      # call to `mac` whose name never appears in source. No syntactic scan
      # can see that, so when any pinned defmacro is referenced in an
      # expansion-time position, no macro sorts: `mac` stays pinned above the
      # defs instead of sorting below `beta` and breaking the build.
      source = """
      defmodule M do
        defmacro mac(x), do: x

        defmacro gen do
          name = String.to_atom("mac")
          call = {name, [], [1]}

          quote do
            unquote(call)
          end
        end

        def beta, do: gen()

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro mac(x), do: x

        defmacro gen do
          name = String.to_atom("mac")
          call = {name, [], [1]}

          quote do
            unquote(call)
          end
        end

        def alpha, do: :a

        def beta, do: gen()
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "an expanded macro calling a private at expansion time bails the module" do
      # `unquote(helper())` runs `helper` while `beta` compiles, so `helper`
      # must stay above `beta` - but it isn't a pin (privates sink), and
      # orphan-tailing it lands it below the expansion site (build break,
      # verified). The engine can't honor that constraint, so bail.
      source = """
      defmodule M do
        defmacro mac do
          quote do
            unquote(helper())
          end
        end

        defp helper, do: :ok

        def beta, do: mac()

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "an expanded macro calling a public at expansion time bails the module" do
      source = """
      defmodule M do
        defmacro mac do
          quote do
            unquote(zeta())
          end
        end

        def zeta, do: :ok

        def beta, do: mac()

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "same-name macro arities pin each other without suppressing the sort" do
      # `pad/1` and `pad/2` are separate groups, and each one's name occurs in
      # the other's defining head - that pins both (a bare occurrence can't be
      # told apart from a use) but a definition isn't an expansion, so the
      # inert `zeta` still sorts.
      source = """
      defmodule M do
        defmacro pad(x), do: x

        defmacro pad(x, y) do
          quote do
            unquote(x) <> unquote(y)
          end
        end

        defmacro zeta(x), do: x

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro pad(x), do: x

        defmacro pad(x, y) do
          quote do
            unquote(x) <> unquote(y)
          end
        end

        def alpha, do: :a

        def beta, do: :b

        defmacro zeta(x), do: x
      end
      """

      assert format(source) == expected
    end

    test "an expanded macro evaluating a private via bind_quoted bails the module" do
      # `bind_quoted:` values evaluate at expansion, the same constraint as
      # `unquote(helper())`.
      source = """
      defmodule M do
        defmacro mac do
          quote bind_quoted: [x: helper()] do
            x
          end
        end

        defp helper, do: :ok

        def beta, do: mac()

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "a quote with a non-literal opts argument doesn't crash the scan" do
      # `quote(unquote(opts), do: ...)` is "unquote called outside quote" at
      # compile time, but it parses, and a formatter must survive anything
      # parseable. The do-block stays treated as quoted, so the module lays
      # out normally.
      source = """
      defmodule M do
        defmacro mac(opts) do
          quote(unquote(opts), do: helper())
        end

        defp helper, do: :ok

        def beta, do: mac([])

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro mac(opts) do
          quote(unquote(opts), do: helper())
        end

        def alpha, do: :a

        def beta, do: mac([])

        defp helper, do: :ok
      end
      """

      assert format(source) == expected
    end

    test "a macro expanded from a default argument creates the same constraints" do
      # `def beta(x \\ mac())` expands `mac` while `beta` compiles - a default
      # is an expansion-time position, exactly like a body call. `mac`'s own
      # expansion calls `helper` at expansion time, so the module bails.
      source = """
      defmodule M do
        defmacro mac do
          quote do
            unquote(helper())
          end
        end

        defp helper, do: :ok

        def beta(x \\\\ mac()), do: x

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "a macro expanded from a guard's default argument suppresses sorting" do
      # Defaults on defguard heads expand at definition too: `one()` runs while
      # `is_one` compiles and its expansion could hide a call to `zeta`, so
      # `zeta` must not sort below the guard.
      source = """
      defmodule M do
        defmacro zeta, do: 1

        defmacro one do
          name = String.to_atom("zeta")
          call = {name, [], []}

          quote do
            unquote(call)
          end
        end

        defguard is_one(x \\\\ one()) when x == 1

        def beta, do: is_one()

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro zeta, do: 1

        defmacro one do
          name = String.to_atom("zeta")
          call = {name, [], []}

          quote do
            unquote(call)
          end
        end

        defguard is_one(x \\\\ one()) when x == 1

        def alpha, do: :a

        def beta, do: is_one()
      end
      """

      assert format(source) == expected
    end

    test "a macro referenced only inside quotes triggers no closure" do
      # `pinned_by_quote` is pinned (doubt resolves to used) but never expands during
      # this module's compile - its references live in quoted code that runs
      # elsewhere - so it can't hide anything and `zeta` still sorts.
      source = """
      defmodule M do
        defmacro pinned_by_quote(x), do: x

        defmacro zeta(x), do: x

        def beta do
          quote do
            pinned_by_quote(1)
          end
        end

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacro pinned_by_quote(x), do: x

        def alpha, do: :a

        def beta do
          quote do
            pinned_by_quote(1)
          end
        end

        defmacro zeta(x), do: x
      end
      """

      assert format(source) == expected
    end

    test "a private macro never sorts, even when nothing references it" do
      # An unused defmacrop/defguardp is a compiler warning, so in
      # warnings-clean code private compile-time definitions are always used:
      # they pin (or bail below the first def) regardless of what the scan
      # finds.
      source = """
      defmodule M do
        defmacrop unused_helper(x), do: x

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule M do
        defmacrop unused_helper(x), do: x

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
    end
  end

  # The plugin formats before laying out, so layout decisions run on
  # formatter-stable text: a shape the base formatter rewrites (`;`-joined
  # defs) can't bail on one pass and lay out on the next - a single pass
  # reaches the fixed point.
  describe "delegates" do
    test "a defdelegate sorts with the publics by its local name and arity" do
      source = """
      defmodule M do
        def zebra do
          :zebra
        end

        defdelegate parse(x), to: String, as: :to_integer

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

        defdelegate parse(x), to: String, as: :to_integer

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a module of only delegates lays out" do
      source = """
      defmodule M do
        defdelegate to_atom(x), to: String
        defdelegate downcase(x), to: String
      end
      """

      # The blank separator between the reordered delegates is synthesized,
      # as for any dense module.
      expected = """
      defmodule M do
        defdelegate downcase(x), to: String

        defdelegate to_atom(x), to: String
      end
      """

      assert format(source) == expected
    end

    test "a delegate's leading comment, @doc and @spec ride along" do
      source = """
      defmodule M do
        # delegates to the parser
        @doc "Parses the input."
        @spec parse(term) :: term
        defdelegate parse(x), to: Parser

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

        # delegates to the parser
        @doc "Parses the input."
        @spec parse(term) :: term
        defdelegate parse(x), to: Parser
      end
      """

      assert format(source) == expected
    end

    test "an @impl delegate joins the callback tier in source order" do
      source = """
      defmodule M do
        def beta do
          :beta
        end

        @impl true
        defdelegate init(arg), to: Impl

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        @impl true
        defdelegate init(arg), to: Impl

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

    test "a bare zero-arity delegate sorts at arity zero" do
      source = """
      defmodule M do
        def zebra do
          :zebra
        end

        defdelegate version, to: Meta

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

        defdelegate version, to: Meta

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a delegate head's defaults are recognized and the layout is undisturbed" do
      source = """
      defmodule M do
        def zebra do
          fetch(:key)
        end

        defdelegate fetch(key, default \\\\ nil), to: Store

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

        defdelegate fetch(key, default \\\\ nil), to: Store

        def zebra do
          fetch(:key)
        end
      end
      """

      assert format(source) == expected
    end

    test "a private anchors below its caller alongside delegates" do
      source = """
      defmodule M do
        defp helper do
          :ok
        end

        def zebra do
          helper()
        end

        defdelegate parse(x), to: Parser

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

        defdelegate parse(x), to: Parser

        def zebra do
          helper()
        end

        defp helper do
          :ok
        end
      end
      """

      assert format(source) == expected
    end

    test "a macro expanded by a delegate's default pins above it" do
      # The default expands while the delegate compiles, so `mac` is used -
      # pinned, in source order - and the delegate sorts below with the publics.
      source = """
      defmodule M do
        defmacro mac, do: 1

        defdelegate foo(a \\\\ mac()), to: Target

        def alpha do
          :alpha
        end
      end
      """

      expected = """
      defmodule M do
        defmacro mac, do: 1

        def alpha do
          :alpha
        end

        defdelegate foo(a \\\\ mac()), to: Target
      end
      """

      assert format(source) == expected
    end

    test "a private called from a delegate's argument default anchors below it" do
      # The delegate's options carry no code, but its argument defaults do -
      # the generated reduced-arity clause calls `fallback` at runtime.
      source = """
      defmodule M do
        defp fallback do
          :fb
        end

        defdelegate fetch(key \\\\ fallback()), to: Store

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        defdelegate fetch(key \\\\ fallback()), to: Store

        defp fallback do
          :fb
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a used macro below the first delegate bails the module" do
      # A delegate counts as a def for the pin boundary: a used macro below it
      # is the same documented used-below-first-def bail.
      source = """
      defmodule M do
        defdelegate parse(x), to: Parser

        defmacro mac, do: 1

        def beta, do: mac()

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "an expanded macro calling a delegate at expansion time bails the module" do
      # A delegate is a local function too: `unquote(zeta())` runs while
      # `beta` compiles, so the delegate must stay above the expansion site -
      # the same constraint as a def, which placement can't honor.
      source = """
      defmodule M do
        defmacro mac do
          quote do
            unquote(zeta())
          end
        end

        defdelegate zeta, to: Target

        def beta, do: mac()

        def alpha, do: :a
      end
      """

      assert format(source) == source
    end

    test "the deprecated list form bails the module" do
      # `defdelegate [a(x), b(y)], to: T` warns at compile (deprecated), so it
      # can't occur in warnings-clean code; the scanner has no single key for
      # it, and the module keeps its source order.
      source = """
      defmodule M do
        defdelegate [a(x), b(y)], to: Target

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
  end

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

    test "a private with a defaulted argument called without it anchors below its caller" do
      # `helper/1` (one defaulted param) also defines `helper/0`, so the
      # `helper()` call resolves into the head's arity range and the call graph
      # sees the caller instead of orphan-tailing the private.
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

        defp helper(x \\\\ :ok) do
          x
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defaulted private called at a middle arity anchors below its caller" do
      source = """
      defmodule M do
        defp helper(a, b \\\\ 1, c \\\\ 2) do
          {a, b, c}
        end

        def alpha do
          helper(:x, :y)
        end

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          helper(:x, :y)
        end

        defp helper(a, b \\\\ 1, c \\\\ 2) do
          {a, b, c}
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a leading default counts toward the arity range" do
      source = """
      defmodule M do
        defp helper(a \\\\ :none, b) do
          {a, b}
        end

        def alpha do
          helper(:x)
        end

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          helper(:x)
        end

        defp helper(a \\\\ :none, b) do
          {a, b}
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a reduced-arity capture anchors below the capturing caller" do
      source = """
      defmodule M do
        defp helper(a, b \\\\ :ok) do
          {a, b}
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

        defp helper(a, b \\\\ :ok) do
          {a, b}
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "a multi-clause private with a defaults-declaring head anchors as one group" do
      source = """
      defmodule M do
        defp helper(a, b \\\\ :ok)

        defp helper(:special, b) do
          b
        end

        defp helper(a, _b) do
          a
        end

        def alpha do
          helper(:x)
        end

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          helper(:x)
        end

        defp helper(a, b \\\\ :ok)

        defp helper(:special, b) do
          b
        end

        defp helper(a, _b) do
          a
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "the bottom-most caller wins across mixed call arities" do
      # The bottom-most caller reaches `helper` through the defaulted arity; if
      # that edge went unseen, `helper` would anchor under `alpha` instead.
      source = """
      defmodule M do
        defp helper(x \\\\ :ok) do
          x
        end

        def alpha do
          helper(:x)
        end

        def zebra do
          helper()
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          helper(:x)
        end

        def zebra do
          helper()
        end

        defp helper(x \\\\ :ok) do
          x
        end
      end
      """

      assert format(source) == expected
    end

    test "a cycle joined through defaulted calls anchors and stays idempotent" do
      source = """
      defmodule M do
        defp pong(x \\\\ :a) do
          ping()
        end

        defp ping(x \\\\ 0) do
          pong()
        end

        def run do
          ping(1)
        end

        def zzz do
          :ok
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          ping(1)
        end

        defp ping(x \\\\ 0) do
          pong()
        end

        defp pong(x \\\\ :a) do
          ping()
        end

        def zzz do
          :ok
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a private called from a def's argument default anchors below it" do
      # A default expression lands in the generated reduced-arity clause, so
      # the call is a real runtime edge from the defaulted function.
      source = """
      defmodule M do
        defp fallback do
          :fb
        end

        def fetch(key \\\\ fallback()) do
          key
        end

        def zebra do
          :zebra
        end
      end
      """

      expected = """
      defmodule M do
        def fetch(key \\\\ fallback()) do
          key
        end

        defp fallback do
          :fb
        end

        def zebra do
          :zebra
        end
      end
      """

      assert format(source) == expected
    end

    test "overlapping defaulted ranges resolve to the exact arity, independent of source order" do
      # `def helper` and the defaulted `defp helper(x \\ :ok)` both define
      # `helper/0` - a defaults conflict the compiler rejects, but WIP source
      # still gets formatted, so resolution must not read source order (which
      # changes between passes - the cycle-break lesson). The exact-arity
      # group wins: `helper()` is the public's, and the defp orphan-tails.
      source = """
      defmodule M do
        defp helper(x \\\\ :ok) do
          x
        end

        def helper do
          :zero
        end

        def alpha do
          helper()
        end
      end
      """

      expected = """
      defmodule M do
        def alpha do
          helper()
        end

        def helper do
          :zero
        end

        defp helper(x \\\\ :ok) do
          x
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end
  end

  # Known scanner limitations: the call-graph is built from source AST without
  # scope analysis, so a few constructs anchor a private somewhere other than
  # its true caller. None corrupt or crash - the layout stays a fixed point -
  # so these lock the current SAFE behavior against silent regression.
  describe "scanner limitations (safe mis-placement)" do
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

    test "a defaulted name inside a quote is over-collected as a call edge" do
      # Same class as above, reached through arity-range resolution: the quoted
      # `leaf()` resolves into `leaf/1`'s defaulted range, so `gen` counts as a
      # caller and wins bottom-most - where the arity mismatch used to mask the
      # spurious edge and `leaf` anchored under `aaa`. Safe mis-anchor, idempotent.
      source = """
      defmodule M do
        defp leaf(x \\\\ :ok) do
          x
        end

        defp gen do
          quote do
            leaf()
          end
        end

        def aaa do
          leaf(:x)
        end

        def zzz do
          gen()
        end
      end
      """

      expected = """
      defmodule M do
        def aaa do
          leaf(:x)
        end

        def zzz do
          gen()
        end

        defp gen do
          quote do
            leaf()
          end
        end

        defp leaf(x \\\\ :ok) do
          x
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
