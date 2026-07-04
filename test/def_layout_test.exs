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

    test "a comment hugging a def's bottom rides with that def, not the next" do
      # The base formatter groups a comment with the code it is not separated
      # from by a blank line: this note is adjacent below `beta` with a blank
      # after it, so it trails `beta`. When `alpha` sorts above, the note stays
      # with `beta` rather than re-homing onto `alpha`.
      source = """
      defmodule M do
        def beta, do: :beta
        # note about beta

        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :alpha

        def beta, do: :beta
        # note about beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a multi-line comment block hugging a def's bottom rides with that def" do
      source = """
      defmodule M do
        def beta, do: :beta
        # note one
        # note two

        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :alpha

        def beta, do: :beta
        # note one
        # note two
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

    test "source that fails to parse raises, like the base formatter" do
      # DefLayout replaces the default formatter for .ex/.exs, so on unparseable
      # input it must fail the same way `mix format` does rather than passing it
      # through silently - otherwise `mix format --check-formatted` would stop
      # catching syntax errors.
      assert_raise TokenMissingError, fn -> format("defmodule M do") end
      assert_raise MismatchedDelimiterError, fn -> format("defmodule M do\n  def a(\nend") end
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
  # conservative scan of the header and the movable groups (the trailer is
  # excluded - it sits below everything the engine moves): the name occurs
  # nowhere in them outside its own group, and its own group references no
  # in-module compile-time name. Every doubt (quote contents, variables
  # sharing the name, atom literals) resolves to "used" - pinned - so the
  # failure direction is over-pinning, never a define-before-use break.
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

    test "a def with an unquote-fragment head bails rather than crashing" do
      # `def unquote(name)()` is legal, compiling Elixir but its head is not a
      # plain atom, so there is no `{name, arity}` key to sort by. The scanner
      # must bail (leave the module in source order), not crash on the head.
      source = """
      defmodule M do
        name = :hello
        def unquote(name)(), do: :world

        def alpha, do: :ok
      end
      """

      assert format(source) == source
    end

    test "a def with a remote-call head bails rather than crashing" do
      # `def Foo.bar()` parses (the base formatter handles it; it is rejected
      # only at compile time). A non-atom head has no local key, so the module
      # bails instead of crashing when it sits among movable defs.
      source = """
      defmodule M do
        def alpha, do: 1
        def Foo.bar(), do: 2
        def zed, do: 3
      end
      """

      assert format(source) == source
    end

    test "a defmacro with an unquote-fragment head bails rather than crashing" do
      source = """
      defmodule M do
        which = :gen

        defmacro unquote(which)(x) do
          quote(do: unquote(x))
        end

        def alpha, do: :ok
      end
      """

      assert format(source) == source
    end

    test "a bare def token with no head bails rather than crashing" do
      # `def` alone parses (to `{:def, _, nil}`) though it never compiles. With
      # no head there is no key, so it is not a movable def part and the module
      # bails instead of crashing on the missing head.
      source = """
      defmodule M do
        def alpha, do: 1
        def
        def zed, do: 2
      end
      """

      assert format(source) == source
    end

    test "a def with a parenless unquote head bails rather than reordering" do
      # `def unquote(:hello)` parses to a head whose name *is* the atom
      # `:unquote` - a special form standing in for a computed name, not a real
      # function called `unquote`. It has no stable `{name, arity}` key, so the
      # module must bail rather than sort it as if it were named `unquote`.
      source = """
      defmodule M do
        def unquote(:hello), do: :world
        def alpha, do: :ok
      end
      """

      assert format(source) == source
    end

    test "a def with an unquote_splicing head bails rather than reordering" do
      source = """
      defmodule M do
        def unquote_splicing([:hello]), do: :world
        def alpha, do: :ok
      end
      """

      assert format(source) == source
    end

    test "a defguard with a parenless unquote head bails rather than reordering" do
      source = """
      defmodule M do
        defguard unquote(:hello) when true
        def alpha, do: :ok
      end
      """

      assert format(source) == source
    end

    test "a defdelegate with a parenless unquote head bails rather than reordering" do
      source = """
      defmodule M do
        defdelegate unquote(:hello), to: String
        def alpha, do: :ok
      end
      """

      assert format(source) == source
    end

    test "a bare defdelegate token with no head bails rather than crashing" do
      # Like a bare `def`, `defdelegate` alone parses (to `{:defdelegate, _,
      # nil}`) without a head to key on, so it is not a movable def part and the
      # module bails.
      source = """
      defmodule M do
        defdelegate
        def a, do: 1
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

    test "a plain value attribute in the header still reorders" do
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

      expected = """
      defmodule M do
        @timeout 5_000

        def alpha do
          :alpha
        end

        def beta do
          @timeout
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "an accumulating attribute assigned twice in the header still reorders" do
      source = """
      defmodule M do
        @steps :one
        @steps :two

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        @steps :one
        @steps :two

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a plain value attribute interleaved after the first def still bails" do
      # A value attribute is header-safe, but only as a *header* statement. A
      # def reads attributes at its definition position, so moving one across a
      # mid-module assignment would change the value it compiles with - bail.
      source = """
      defmodule M do
        def beta do
          :beta
        end

        @timeout 5_000

        def alpha do
          @timeout
        end
      end
      """

      assert format(source) == source
    end

    test "an @on_definition hook in the header bails (order-sensitive callback)" do
      # `@on_definition` fires per def in definition order and can consume
      # per-def attributes, so reordering defs would change what it sees. It is
      # not a header-safe value attribute - the module must bail.
      source = """
      defmodule M do
        @on_definition {SomeModule, :handle}
        @timeout 5_000

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

    test "an @on_definition hook never strands a per-def attribute it consumes" do
      # The classic strand shape: `@tag :beta` sits directly above `beta` for
      # the hook to read at beta's definition. Reordering would move `alpha`
      # above the tag and let the hook tag the wrong def. The header bail covers
      # it; lock the never-strand shape explicitly.
      source = """
      defmodule M do
        @on_definition {SomeModule, :handle}

        @tag :beta
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

    test "a header attribute referencing an in-module macro keeps it pinned" do
      # The header attribute mentions the macro's name (`:limit`), so the macro
      # is no longer provably inert: it pins via the `header_refs` path in
      # `classify_pinned` and stays at the top, rather than sorting down among
      # the publics the way an unreferenced inert macro would.
      source = """
      defmodule M do
        @names [:limit]

        defmacro limit, do: 5

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        @names [:limit]

        defmacro limit, do: 5

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "an attachment attribute above the first def attaches to it, not the header" do
      # `@doc`/`@spec` are def-attaching, never header constructs: the leading
      # `@doc` rides with `beta` as it moves below `alpha`, rather than being
      # absorbed into the header and stranded.
      source = """
      defmodule M do
        @doc "beta docs"
        def beta, do: :beta

        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        def alpha, do: :alpha

        @doc "beta docs"
        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
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

    test "a nested module in the body bails the outer (its own body still lays out)" do
      # A nested `defmodule` interleaved among the defs (rather than bracketing
      # them) bails the outer module, which keeps source order. Its body is a
      # module body of its own, though, and gets the layout independently.
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

      expected = """
      defmodule Outer do
        def beta, do: :b

        defmodule Inner do
          def x, do: :x

          def y, do: :y
        end

        def alpha, do: :a
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
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

    test "a @doc documenting a header @callback stays frozen while publics sort" do
      # `@doc` is def-attaching, but a `@doc` run terminated by `@callback`
      # documents the callback declaration - module-level setup, not the start
      # of the def region. The whole block stays frozen in the header; only the
      # publics below it reorder. (The plausible `Cache` shape, minus `__using__`.)
      source = """
      defmodule M do
        @moduledoc "M"

        @doc "the name callback"
        @callback name() :: atom()

        @doc "the count callback"
        @callback count() :: integer()

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        @moduledoc "M"

        @doc "the name callback"
        @callback name() :: atom()

        @doc "the count callback"
        @callback count() :: integer()

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a @doc/@spec/@callback chain in the header stays frozen while publics sort" do
      # A `@doc` then `@spec` then `@callback` run compiles and documents the
      # callback - the recognition rule allows the whole attaching-attr chain,
      # not just a bare `@doc` adjacency.
      source = """
      defmodule M do
        @doc "init the thing"
        @spec init(term) :: term
        @callback init(term) :: term

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        @doc "init the thing"
        @spec init(term) :: term
        @callback init(term) :: term

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a bare @callback block in the header still reorders" do
      # Regression guard: a `@callback` run with no leading `@doc` was already
      # header-legal and must stay so.
      source = """
      defmodule M do
        @callback name() :: atom()
        @callback count() :: integer()

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        @callback name() :: atom()
        @callback count() :: integer()

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a @doc/@callback pair below the first def still bails" do
      # The recognition rule applies only while still in the header. The same
      # shape sitting among the defs is genuinely interleaved and must bail.
      source = """
      defmodule M do
        def beta, do: :beta

        @doc "the name callback"
        @callback name() :: atom()

        def alpha, do: :alpha
      end
      """

      assert format(source) == source
    end

    test "a dangling @doc with no def or callback after it still bails" do
      # A `@doc` run terminated by neither a def nor a `@callback` (here, the
      # module ends) leaves the `@doc` pending with nothing to attach to - the
      # generic interleaved/unrecognized case, still a bail.
      source = """
      defmodule M do
        def beta, do: :beta
        def alpha, do: :alpha

        @doc "trailing, attaches to nothing"
      end
      """

      assert format(source) == source
    end

    test "a header match assignment above the defs still reorders" do
      # A module-body `=` binds a var unreachable from any def body and stays
      # frozen in the header. It is module-level setup like a value attribute,
      # so the publics below it sort while it stays put.
      source = """
      defmodule M do
        base = [:a, :b, :c]
        @names base

        def beta, do: @names
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        base = [:a, :b, :c]
        @names base

        def alpha, do: :alpha

        def beta, do: @names
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a header write-buffer match assignment reorders and is a fixed point" do
      # The write-buffer idiom: a `=` computes a value the header then feeds to
      # an attribute (and a directive). The assignment, its consumers, and the
      # defs all sit in source order; only the defs sort.
      source = """
      defmodule M do
        path = "priv/data.js"
        @external_resource path
        @data path

        def beta, do: @data
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        path = "priv/data.js"
        @external_resource path
        @data path

        def alpha, do: :alpha

        def beta, do: @data
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a header match destructuring a tuple still reorders" do
      source = """
      defmodule M do
        {a, b} = {:x, :y}
        @pair {a, b}

        def beta, do: @pair
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        {a, b} = {:x, :y}
        @pair {a, b}

        def alpha, do: :alpha

        def beta, do: @pair
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a match assignment interleaved after the first def still bails" do
      # A `=` is header-safe only as a header statement. Once it sits among the
      # defs, moving a function across it could change what the compiler sees,
      # so the module must bail.
      source = """
      defmodule M do
        def beta, do: :beta

        x = compute()
        @cached x

        def alpha, do: :alpha
      end
      """

      assert format(source) == source
    end

    test "a header match whose RHS mentions an in-module macro keeps it pinned" do
      # The match RHS mentions the macro's name (`:limit`), so the macro is no
      # longer provably inert: it pins via the `header_refs` path (the existing
      # `referenced_names` prewalk walks the match node) and stays at the top,
      # rather than sorting down among the publics.
      source = """
      defmodule M do
        names = [:limit]
        @names names

        defmacro limit, do: 5

        def beta, do: :beta
        def alpha, do: :alpha
      end
      """

      expected = """
      defmodule M do
        names = [:limit]
        @names names

        defmacro limit, do: 5

        def alpha, do: :alpha

        def beta, do: :beta
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a def hidden in a header match RHS bails" do
      # `_ = def hidden(), do: :ok` compiles and defines `hidden`, but it is a
      # `:=` node, not a def-part, so admitting matches would freeze the def
      # invisibly in the header. The RHS-contains-a-def guard bails instead.
      source = """
      defmodule M do
        _ = def hidden(), do: :ok

        def visible, do: hidden()
        def another, do: :another
      end
      """

      assert format(source) == source
    end

    test "a qualified def hidden in a header match RHS bails" do
      # `Kernel.defmacro hidden(), ...` parses as a dotted call, not a bare
      # `{:defmacro, _, _}` node, but it still defines a macro and compiles. If
      # admitted, the macro freezes in the header invisible to the engine, and
      # reordering a function its expansion calls below the expansion site
      # breaks the build. The guard must catch the qualified form too.
      source = """
      defmodule M do
        _ = Kernel.defmacro(hidden(), do: helper())

        def helper, do: quote(do: :ok)
        def beta, do: hidden()
        def alpha, do: :alpha
      end
      """

      assert format(source) == source
    end
  end

  describe "nested modules" do
    test "a facade module's nested module bodies each lay out" do
      source = """
      defmodule Outer do
        defmodule One do
          def beta, do: :b

          def alpha, do: :a
        end

        defmodule Two do
          def zeta, do: :z

          def epsilon, do: :e
        end
      end
      """

      expected = """
      defmodule Outer do
        defmodule One do
          def alpha, do: :a

          def beta, do: :b
        end

        defmodule Two do
          def epsilon, do: :e

          def zeta, do: :z
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a top-level defimpl body gets the layout: publics sort, privates sink" do
      source = """
      defimpl Render, for: Thing do
        defp helper(t), do: t

        def beta(t), do: helper(t)

        def alpha(t), do: t
      end
      """

      expected = """
      defimpl Render, for: Thing do
        def alpha(t), do: t

        def beta(t), do: helper(t)

        defp helper(t), do: t
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "@impl defs in a defimpl stay a callback tier in source order" do
      source = """
      defimpl Render, for: Thing do
        def build(t), do: t

        @impl true
        def zeta(t), do: t

        @impl true
        def count(t), do: t
      end
      """

      expected = """
      defimpl Render, for: Thing do
        @impl true
        def zeta(t), do: t

        @impl true
        def count(t), do: t

        def build(t), do: t
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defimpl for the defining struct lays out (outer bails)" do
      # `defimpl Render do ... end` defaults `for:` to the enclosing module -
      # the two-argument AST shape, no `for:` list among the args.
      source = """
      defmodule Thing do
        defstruct [:name]

        defimpl Render do
          def beta(t), do: t.name

          def alpha(t), do: t.name
        end
      end
      """

      expected = """
      defmodule Thing do
        defstruct [:name]

        defimpl Render do
          def alpha(t), do: t.name

          def beta(t), do: t.name
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defimpl for a list of types lays out its single body" do
      source = """
      defimpl Render, for: [List, Map] do
        def beta(x), do: x

        def alpha(x), do: x
      end
      """

      expected = """
      defimpl Render, for: [List, Map] do
        def alpha(x), do: x

        def beta(x), do: x
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a nested module in a defimpl's header is frozen while the impl's defs sort" do
      # A defimpl body is a plain module body, tiers included.
      source = """
      defimpl Render, for: Thing do
        defmodule Helper do
          def beta, do: :b

          def alpha, do: :a
        end

        def zeta(t), do: t

        def render(t), do: t
      end
      """

      expected = """
      defimpl Render, for: Thing do
        defmodule Helper do
          def alpha, do: :a

          def beta, do: :b
        end

        def render(t), do: t

        def zeta(t), do: t
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defprotocol body is never touched" do
      source = """
      defprotocol Render do
        def beta(x)
        def alpha(x)
      end
      """

      assert format(source) == source
    end

    test "nested module bodies lay out at every depth" do
      source = """
      defmodule Outer do
        defmodule Mid do
          defmodule Inner do
            def beta, do: :b

            def alpha, do: :a
          end
        end
      end
      """

      expected = """
      defmodule Outer do
        defmodule Mid do
          defmodule Inner do
            def alpha, do: :a

            def beta, do: :b
          end
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a keyword-form nested module bails (everything around it untouched)" do
      # The parenthesized defimpls are the base formatter's fixed point for the
      # keyword-call form under default opts; DefLayout adds no change to them.
      # The do-less ones parse (they only fail at compile), so the walk shrugs
      # them off rather than crashing.
      source = """
      defmodule Outer do
        def beta, do: :b

        defmodule Inner, do: :x

        def alpha, do: :a
      end

      defimpl(Render, for: Thing, do: :ok)

      defimpl(Render, for: OtherThing)

      defimpl(Render)
      """

      assert format(source) == source
    end

    test "a keyword-form module's nested module bodies still lay out" do
      # The keyword form bails per node - only its own layout has nothing to
      # splice against; the walk still descends, so a regular nested module
      # inside one lays out.
      source = """
      defmodule Outer,
        do:
          (defmodule Inner do
             def beta, do: :b
             def alpha, do: :a
           end)
      """

      expected = """
      defmodule Outer,
        do:
          (defmodule Inner do
             def alpha, do: :a

             def beta, do: :b
           end)
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a keyword-form defimpl's nested module bodies still lay out" do
      # The keyword form of defimpl merges `for:` and `do:` into one trailing
      # option list - the descent fetches `:do` from wherever it sits.
      source = """
      defimpl(KWRender,
        for: KWThing,
        do:
          (
            defmodule Helper do
              def beta, do: :b
              def alpha, do: :a
            end

            def render(t), do: t
          )
      )
      """

      expected = """
      defimpl(KWRender,
        for: KWThing,
        do:
          (
            defmodule Helper do
              def alpha, do: :a

              def beta, do: :b
            end

            def render(t), do: t
          )
      )
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defmodule inside a def body rides with its def" do
      # The walk descends through module-body positions only: a module defined
      # inside a function body is part of that function's text, so it rides
      # along on the def's move and its own body is left alone.
      source = """
      defmodule Outer do
        def beta do
          defmodule Inner do
            def y, do: :y
            def x, do: :x
          end
        end

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta do
          defmodule Inner do
            def y, do: :y
            def x, do: :x
          end
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a nested module above the defs is frozen in the header while the defs sort" do
      source = """
      defmodule Outer do
        defmodule Inner do
          def go, do: :ok
        end

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defmodule Inner do
          def go, do: :ok
        end

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a header nested module's body and the outer's defs lay out in one pass" do
      # The shape where the disjoint-splice-regions assert goes load-bearing:
      # the inner's region sits inside the frozen header, strictly above the
      # outer's def region, and both splice in the same pass.
      source = """
      defmodule Outer do
        @moduledoc false

        defmodule Inner do
          def y, do: :y

          def x, do: :x
        end

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        @moduledoc false

        defmodule Inner do
          def x, do: :x

          def y, do: :y
        end

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "two header nested modules' bodies and the outer's defs lay out in one pass" do
      # Three disjoint regions in one splice: each frozen header module keeps
      # its (deliberately non-alphabetical) position while its body lays out.
      source = """
      defmodule Outer do
        defmodule Inner2 do
          def y, do: :y

          def x, do: :x
        end

        defmodule Inner1 do
          def b, do: :b

          def a, do: :a
        end

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defmodule Inner2 do
          def x, do: :x

          def y, do: :y
        end

        defmodule Inner1 do
          def a, do: :a

          def b, do: :b
        end

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defimpl above the defs is frozen in the header while the defs sort" do
      source = """
      defmodule Outer do
        defstruct [:name]

        defimpl Render do
          def render(t), do: t.name
        end

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defstruct [:name]

        defimpl Render do
          def render(t), do: t.name
        end

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defprotocol above the defs is frozen in the header while the defs sort" do
      source = """
      defmodule Outer do
        defprotocol Marker do
          def beta(x)
          def alpha(x)
        end

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defprotocol Marker do
          def beta(x)
          def alpha(x)
        end

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a keyword-form nested module above the defs is frozen in the header" do
      # Header exprs are never spliced, so the missing `:do` line that bails
      # keyword-form modules elsewhere doesn't matter here.
      source = """
      defmodule Outer do
        defmodule Inner, do: :x

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defmodule Inner, do: :x

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a nested module below a pinned macro bails (its own body still lays out)" do
      # The header tier ends at the first def*-family expr, pinned macros
      # included - a nested module below one is interleaved, so the outer
      # keeps source order.
      source = """
      defmodule Outer do
        defmacrop mac(x), do: x

        defmodule Inner do
          def y, do: :y

          def x, do: :x
        end

        def beta, do: mac(:b)

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defmacrop mac(x), do: x

        defmodule Inner do
          def x, do: :x

          def y, do: :y
        end

        def beta, do: mac(:b)

        def alpha, do: :a
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a macro referenced from a header nested module's body pins" do
      # Header nested modules feed the inert-macro analysis like any other
      # header expr: `:zmac` inside Inner's body counts as a reference, so
      # `zmac` pins (stays first, source order) instead of sorting below beta.
      source = """
      defmodule Outer do
        defmodule Inner do
          def tag, do: :zmac
        end

        defmacro zmac(x), do: x

        def beta, do: :b

        def alpha, do: :a
      end
      """

      expected = """
      defmodule Outer do
        defmodule Inner do
          def tag, do: :zmac
        end

        defmacro zmac(x), do: x

        def alpha, do: :a

        def beta, do: :b
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a nested module below the defs is frozen in the trailer while the defs sort" do
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule Inner do
          def go, do: :ok
        end
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        defmodule Inner do
          def go, do: :ok
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defimpl below the defs is frozen in the trailer while the defs sort" do
      source = """
      defmodule Thing do
        defstruct [:name]

        def beta(t), do: t

        def alpha(t), do: t

        defimpl Render do
          def render(t), do: t.name
        end
      end
      """

      expected = """
      defmodule Thing do
        defstruct [:name]

        def alpha(t), do: t

        def beta(t), do: t

        defimpl Render do
          def render(t), do: t.name
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a defprotocol below the defs is frozen in the trailer while the defs sort" do
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defprotocol Marker do
          def beta(x)
          def alpha(x)
        end
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        defprotocol Marker do
          def beta(x)
          def alpha(x)
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a keyword-form nested module below the defs is frozen in the trailer" do
      # Trailer exprs are never spliced, so the missing `:do` line that bails
      # keyword-form modules elsewhere doesn't matter here either.
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule Inner, do: :x
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        defmodule Inner, do: :x
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a run of trailing nested modules is frozen in source order" do
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule Zed do
          def go, do: :ok
        end

        defimpl Render, for: Ant do
          def render(t), do: t
        end
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        defmodule Zed do
          def go, do: :ok
        end

        defimpl Render, for: Ant do
          def render(t), do: t
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a trailing nested module's body and the outer's defs lay out in one pass" do
      # The disjoint-splice-regions assert in the direction the header shape
      # can't produce: the outer's def region sits strictly ABOVE the trailing
      # module's inner region, and both splice in the same pass.
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule Inner do
          def y, do: :y

          def x, do: :x
        end
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        defmodule Inner do
          def x, do: :x

          def y, do: :y
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "defs sort between a header nested module and a trailing one" do
      # The straddle shape: both frozen tiers present, the def region lays out
      # between them.
      source = """
      defmodule Outer do
        defmodule Above do
          def go, do: :ok
        end

        def beta, do: :b

        def alpha, do: :a

        defmodule Below do
          def stop, do: :ok
        end
      end
      """

      expected = """
      defmodule Outer do
        defmodule Above do
          def go, do: :ok
        end

        def alpha, do: :a

        def beta, do: :b

        defmodule Below do
          def stop, do: :ok
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a comment between the last def and the trailer stays put" do
      # The def region stops at the last function, so the comment below it
      # never rides along with a moving def.
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        # implementations live below

        defmodule Inner do
          def go, do: :ok
        end
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        # implementations live below

        defmodule Inner do
          def go, do: :ok
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a trailing non-module expression bails the outer (nested bodies still lay out)" do
      # Passes before A2 too (the bail path also leaves the outer untouched) -
      # a deliberate boundary guard against over-recognition: the trailer is
      # STRICTLY the maximal run of nested modules at the very end, so any
      # other expression below the defs keeps the whole module in source order.
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule Inner do
          def y, do: :y

          def x, do: :x
        end

        IO.puts("loaded")
      end
      """

      expected = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule Inner do
          def x, do: :x

          def y, do: :y
        end

        IO.puts("loaded")
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a def between trailing nested modules bails the outer (nested bodies still lay out)" do
      # Also passes before A2 - the same boundary guard: a def below a nested
      # module makes that module interleaved, not trailing, even when another
      # nested module closes the file.
      source = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule One do
          def y, do: :y

          def x, do: :x
        end

        def gamma, do: :g

        defmodule Two do
          def go, do: :ok
        end
      end
      """

      expected = """
      defmodule Outer do
        def beta, do: :b

        def alpha, do: :a

        defmodule One do
          def x, do: :x

          def y, do: :y
        end

        def gamma, do: :g

        defmodule Two do
          def go, do: :ok
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end

    test "a macro referenced only from a trailing module's body still sorts" do
      # Mirror of the header `:zmac` test, opposite outcome: trailer bodies
      # deliberately do NOT feed the inert-macro analysis. The trailer sits
      # below everything the engine moves, so even a genuine reference from
      # there lands below the macro wherever it sorts - constraint-free.
      source = """
      defmodule Outer do
        defmacro zmac(x), do: x

        def beta, do: :b

        def alpha, do: :a

        defmodule Inner do
          def tag, do: :zmac
        end
      end
      """

      expected = """
      defmodule Outer do
        def alpha, do: :a

        def beta, do: :b

        defmacro zmac(x), do: x

        defmodule Inner do
          def tag, do: :zmac
        end
      end
      """

      assert format(source) == expected
      assert format(expected) == expected
    end
  end
end
