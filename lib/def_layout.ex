defmodule DefLayout do
  @moduledoc false

  @behaviour Mix.Tasks.Format

  alias DefLayout.Engine
  alias DefLayout.Scan

  @impl Mix.Tasks.Format
  def features(_opts), do: [extensions: [".ex", ".exs"]]

  @impl Mix.Tasks.Format
  def format(source, opts) do
    # Format before laying out, so layout decisions run on formatter-stable
    # text: a shape the base formatter rewrites (`;`-joined defs) could
    # otherwise bail on this pass and lay out on the next, taking two passes
    # to reach the fixed point. Splicing relies on the same normalization -
    # formatted text never leaves two defs (or a def and the header) sharing
    # a line, so def_group line-spans are disjoint.
    case Code.string_to_quoted(source) do
      {:ok, _ast} ->
        formatted = format_string(source, opts)
        {:ok, ast} = Code.string_to_quoted(formatted, token_metadata: true)

        formatted
        |> reorder(ast)
        |> format_string(opts)

      {:error, _} ->
        source
    end
  end

  defp format_string(source, opts) do
    source
    |> Code.format_string!(opts)
    |> then(&IO.iodata_to_binary([&1, ?\n]))
  end

  # Collects a line-span replacement for each module that needs reordering, then
  # splices them into the source bottom-up (so earlier line numbers stay valid).
  defp reorder(source, ast) do
    source_lines = String.split(source, "\n")

    ast
    |> top_level_exprs()
    |> Enum.flat_map(&replacement(&1, source_lines))
    |> Enum.sort_by(fn {region_start, _region_stop, _region_lines} -> region_start end, :desc)
    |> Enum.reduce(source_lines, fn {region_start, region_stop, region_lines}, acc ->
      {pre, rest} = Enum.split(acc, region_start - 1)
      {_replaced_region, post} = Enum.split(rest, region_stop - region_start + 1)
      pre ++ region_lines ++ post
    end)
    |> Enum.join("\n")
  end

  defp top_level_exprs({:__block__, _, exprs}) when is_list(exprs), do: exprs
  defp top_level_exprs(expr), do: [expr]

  defp replacement({:defmodule, meta, [_, [{:do, body}]]}, source_lines) do
    do_line = meta[:do][:line]

    # `do_line` anchors the header span; a keyword-form `defmodule M, do: ...`
    # carries no `:do` line metadata, so there's nothing to splice against - bail.
    case body do
      {:__block__, _, exprs} when is_list(exprs) and is_integer(do_line) ->
        module_replacement(exprs, do_line, source_lines)

      _ ->
        []
    end
  end

  defp replacement(_expr, _source_lines), do: []

  defp module_replacement(exprs, do_line, source_lines) do
    with {:ok, def_groups} <- Scan.def_groups(exprs, do_line, source_lines),
         ordered = Engine.order(def_groups),
         true <- Enum.map(def_groups, & &1.key) != Enum.map(ordered, & &1.key) do
      region_start = hd(def_groups).start
      region_stop = List.last(def_groups).stop

      region_lines =
        ordered
        |> Enum.map(& &1.lines)
        |> Enum.intersperse([""])
        |> Enum.concat()

      [{region_start, region_stop, region_lines}]
    else
      _ -> []
    end
  end
end
