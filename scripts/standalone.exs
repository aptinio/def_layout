# Validation sweep: runs DefLayout over a corpus and checks that its output
# only reorders. Point it at any Elixir codebase and see for yourself.
#
#   mix run scripts/standalone.exs PATH [PATH ...]
#
# Each PATH is a directory; every `lib/**/*.ex` file under it is checked.
# Run from this repo's root so `mix run` compiles and loads DefLayout first.
#
# Per file, DefLayout's output is compared against the same file run through
# the base formatter alone (`Code.format_string!`), so the only difference
# under test is the reordering:
#
#   * reorder-only  - the sorted multiset of non-blank lines is unchanged
#                     (the diff is positions, never content)
#   * def inventory - the set of `def*` heads is unchanged (no def is dropped,
#                     duplicated, or rewritten)
#   * idempotent    - a second DefLayout pass leaves the def order alone
#   * compile parity - when the original file compiles on its own in this VM,
#                     the reordered output must compile too. This is what
#                     catches a reorder that moves a use below its definition;
#                     the line-based checks can't see it. Files that don't
#                     compile on their own (they import deps this VM lacks) are
#                     gated out and counted as skipped, not failed.
#
# Pass: each corpus prints a one-line summary with FAILURES=0 and the script
# exits 0. Fail: the offending {check, file} pairs are printed and the script
# exits 1.
roots = System.argv()

if roots == [] do
  IO.puts(:stderr, "usage: mix run scripts/standalone.exs PATH [PATH ...]")
  System.halt(2)
end

Code.put_compiler_option(:ignore_module_conflict, true)

defmodule Check do
  # The core formatter can be non-idempotent under opts=[] (wrap oscillation
  # that settles on the second application). DefLayout formats before laying
  # out, so its output sits at the settled state - baseline against the core
  # formatter's fixed point, not its first application.
  def base(src) do
    src
    |> format_once()
    |> settle(3)
  rescue
    # The core formatter can't parse it with default opts; nothing to verify.
    _ -> nil
  end

  defp settle(s, 0), do: s

  defp settle(s, n) do
    case format_once(s) do
      ^s -> s
      next -> settle(next, n - 1)
    end
  end

  defp format_once(s),
    do:
      s
      |> Code.format_string!()
      |> IO.iodata_to_binary()
      |> Kernel.<>("\n")

  # Compiles in this VM; warnings are expected corpus noise, only success
  # matters. Diagnostics are captured so the sweep output stays readable.
  def compiles?(src) do
    {result, _diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_string(src)
          true
        rescue
          _ -> false
        catch
          _, _ -> false
        end
      end)

    result
  end

  # `[\s(]` so parenthesized heads (`def(foo, do: ...)`) - which the base
  # formatter preserves verbatim - are counted, not silently skipped.
  @def_head ~r/^(def|defp|defdelegate|defmacro|defmacrop|defguard|defguardp)[\s(]/

  def def_heads(s) do
    s
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(@def_head, &1))
    |> Enum.sort()
  end

  def def_order(s) do
    s
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(@def_head, &1))
  end

  def macro_module?(s), do: Regex.match?(~r/^\s*(defmacro|defmacrop|defguard|defguardp)[\s(]/m, s)

  def sorted_nonblank(s),
    do:
      s
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.sort()
end

sweep = fn root ->
  zero = %{
    n: 0,
    reordered: 0,
    macro_mods: 0,
    macro_reordered: 0,
    compile_checked: 0,
    compile_skipped: 0,
    fails: []
  }

  files =
    root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()

  if files == [], do: raise("no lib/**/*.ex files under #{root} - is the path right?")

  stats =
    Enum.reduce(files, zero, fn f, acc ->
      src = File.read!(f)

      case Check.base(src) do
        nil ->
          acc

        base ->
          out = DefLayout.format(src, [])
          again = DefLayout.format(out, [])
          macro? = Check.macro_module?(src)
          reordered? = out != base

          problems =
            []
            |> then(
              &if Check.sorted_nonblank(out) == Check.sorted_nonblank(base),
                do: &1,
                else: [{:content, f} | &1]
            )
            |> then(&if Check.def_heads(out) == Check.def_heads(base), do: &1, else: [{:heads, f} | &1])
            |> then(&if Check.def_order(again) == Check.def_order(out), do: &1, else: [{:idem, f} | &1])

          {compile_checked, compile_skipped, problems} =
            cond do
              # No reorder - output is the base formatter's alone; nothing of
              # DefLayout's to compile-check.
              not reordered? -> {0, 0, problems}
              not Check.compiles?(src) -> {0, 1, problems}
              Check.compiles?(out) -> {1, 0, problems}
              true -> {1, 0, [{:compile, f} | problems]}
            end

          %{
            acc
            | n: acc.n + 1,
              reordered: acc.reordered + if(reordered?, do: 1, else: 0),
              macro_mods: acc.macro_mods + if(macro?, do: 1, else: 0),
              macro_reordered: acc.macro_reordered + if(macro? and reordered?, do: 1, else: 0),
              compile_checked: acc.compile_checked + compile_checked,
              compile_skipped: acc.compile_skipped + compile_skipped,
              fails: problems ++ acc.fails
          }
      end
    end)

  IO.puts(
    "#{root}: files=#{stats.n} reordered=#{stats.reordered} " <>
      "macro_modules=#{stats.macro_mods} macro_reordered=#{stats.macro_reordered} " <>
      "compile_checked=#{stats.compile_checked} compile_skipped=#{stats.compile_skipped} " <>
      "FAILURES=#{length(stats.fails)}"
  )

  Enum.each(Enum.take(stats.fails, 10), &IO.inspect/1)
  stats.fails
end

failed? = Enum.reduce(roots, false, fn root, acc -> sweep.(root) != [] or acc end)

if failed?, do: System.halt(1)
