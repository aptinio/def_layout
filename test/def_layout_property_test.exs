defmodule DefLayout.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Property companion to the example-based `idempotency` tests: generates
  # scrambled modules over the whole def* family with random call edges to
  # exercise the ordering engine (anchoring, cycles, orphans, callbacks, macro
  # pinning, inert sorting, and arity-range resolution through defaulted
  # heads). Bodies are kept trivial so the base `Code.format_string!` is
  # itself a fixed point, leaving the property to test DefLayout's reordering
  # alone.

  @names [:a, :b, :c, :d, :e, :f]
  @arities [0, 1, 2]
  @all_keys for name <- @names, arity <- @arities, do: {name, arity}
  @headers ["@moduledoc false", "use GenServer", "import Enum", "alias Foo.Bar"]

  defp format(source), do: DefLayout.format(source, [])

  property "format(format(x)) == format(x) for a scrambled module" do
    check all(source <- module_gen()) do
      once = format(source)
      assert format(once) == once
    end
  end

  property "DefLayout + Quokka compose to a fixed point" do
    # The real dog-food pipeline is `plugins: [DefLayout, Quokka]`. A shared
    # explicit line_length keeps the two formatters from oscillating on width
    # (Quokka defaults 122, the base formatter 98); the property then checks the
    # composition is a fixed point - Quokka owns directives, DefLayout owns defs.
    opts = [line_length: 122, file: "lib/m.ex"]

    pipeline = fn src ->
      src
      |> DefLayout.format(opts)
      |> Quokka.format(opts)
    end

    check all(source <- module_gen()) do
      once = pipeline.(source)
      assert pipeline.(once) == once
    end
  end

  defp module_gen do
    gen all(
          keys <- keys_gen(),
          specs <- fixed_list(Enum.map(keys, &spec_gen(&1, keys))),
          header <- header_gen()
        ) do
      render(header, specs)
    end
  end

  # Selects a non-empty, distinct subset of `{name, arity}` keys in scrambled
  # order. A per-key keep flag guarantees uniqueness without StreamData's
  # uniq_list_of duplicate budget (which overflows on the small key space); a
  # random sort index scrambles the order so the input genuinely needs
  # reordering. Capped at 8 so modules stay small enough to read on failure.
  defp keys_gen do
    gen all(picks <- fixed_list(Enum.map(@all_keys, fn _ -> tuple({boolean(), integer()}) end))) do
      selected =
        @all_keys
        |> Enum.zip(picks)
        |> Enum.filter(fn {_key, {keep?, _ord}} -> keep? end)
        |> Enum.sort_by(fn {_key, {_keep?, ord}} -> ord end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.take(8)

      if selected == [], do: [hd(@all_keys)], else: selected
    end
  end

  # A distinct subset of recognized header lines, via the same keep-flag trick.
  defp header_gen do
    gen all(flags <- fixed_list(Enum.map(@headers, fn _ -> boolean() end))) do
      for {line, true} <- Enum.zip(@headers, flags), do: line
    end
  end

  defp spec_gen(key, keys) do
    others = List.delete(keys, key)

    # Plain list_of (not uniq): duplicate call edges are harmless - Scan dedups
    # calls - and requiring uniqueness over a tiny `others` space overflows
    # StreamData's duplicate budget. The boolean alongside each callee asks the
    # call site to drop a defaulted argument when the callee has one.
    calls_gen =
      case others do
        [] -> constant([])
        _ -> list_of(tuple({member_of(others), boolean()}), max_length: 3)
      end

    gen all(
          kind <- member_of([:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]),
          impl? <- boolean(),
          defaulted? <- boolean(),
          calls <- calls_gen
        ) do
      %{
        key: key,
        kind: kind,
        callback?: kind in [:def, :defmacro] and impl?,
        defaulted?: defaulted? and elem(key, 1) > 0,
        calls: calls
      }
    end
  end

  defp render(header, specs) do
    by_key = Map.new(specs, &{&1.key, &1})
    body = Enum.join(header ++ Enum.map(specs, &render_fun(&1, by_key)), "\n\n")

    "defmodule M do\n" <> body <> "\nend\n"
  end

  defp render_fun(%{key: {name, arity}, kind: kind, callback?: callback?, calls: calls} = spec, by_key) do
    impl = if callback?, do: "@impl true\n", else: ""
    body = Enum.map_join(calls, "", &"#{render_call(&1, by_key)}\n") <> ":ok"

    cond do
      kind in [:defguard, :defguardp] ->
        "#{impl}#{kind} #{name}#{params(spec)} when #{guard_expr(arity)}"

      kind in [:defmacro, :defmacrop] ->
        # Calls live inside a quote: quoted code imposes no expansion-time
        # constraint, so a referenced macro pins (or an unreferenced one
        # sorts) instead of the module bailing, and the quote's calls
        # exercise private anchoring under macros.
        "#{impl}#{kind} #{name}#{params(spec)} do\nquote do\n#{body}\nend\nend"

      true ->
        "#{impl}#{kind} #{name}#{params(spec)} do\n#{body}\nend"
    end
  end

  defp guard_expr(0), do: "1 > 0"
  defp guard_expr(_arity), do: "arg0 > 0"

  # Parens are always emitted so each call is a real local-call edge: a bare
  # zero-arity name (no parens) is AST-identical to a variable and deliberately
  # not recorded as an edge, so it would not exercise the call graph. A call
  # marked drop? omits the callee's defaulted argument, so the edge only
  # anchors (or cycles) through arity-range resolution.
  defp render_call({{name, arity} = key, drop?}, by_key) do
    arity = if drop? and by_key[key].defaulted?, do: arity - 1, else: arity

    "#{name}(#{Enum.map_join(1..arity//1, ", ", fn _ -> "0" end)})"
  end

  defp params(%{key: {_name, 0}}), do: ""

  defp params(%{key: {_name, arity}, defaulted?: defaulted?}) do
    args = Enum.map(0..(arity - 1)//1, &"arg#{&1}")
    args = if defaulted?, do: List.update_at(args, -1, &(&1 <> " \\\\ 0")), else: args

    "(" <> Enum.join(args, ", ") <> ")"
  end
end
