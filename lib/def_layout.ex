defmodule DefLayout do
  @moduledoc false

  @behaviour Mix.Tasks.Format

  alias DefLayout.Engine
  alias DefLayout.Scan

  @module_kinds [:defmodule, :defimpl]

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
    #
    # This also raises on unparseable input exactly as the base formatter does:
    # a plugin replaces the default formatter for its extensions, so swallowing
    # a syntax error here would let `mix format --check-formatted` pass a broken
    # file. The formatted text is guaranteed to parse, so the reparse is strict.
    formatted = format_string(source, opts)
    {:ok, ast} = Code.string_to_quoted(formatted, token_metadata: true)

    formatted
    |> reorder(ast)
    |> format_string(opts)
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
    |> replacements(source_lines)
    |> Enum.sort_by(fn {region_start, _region_stop, _region_lines} -> region_start end, :desc)
    |> assert_disjoint()
    |> Enum.reduce(source_lines, fn {region_start, region_stop, region_lines}, acc ->
      {pre, rest} = Enum.split(acc, region_start - 1)
      {_replaced_region, post} = Enum.split(rest, region_stop - region_start + 1)
      pre ++ region_lines ++ post
    end)
    |> Enum.join("\n")
  end

  # Distinct modules' regions never overlap - a nested module's region lies
  # strictly inside lines its outer never moves - and the bottom-up splice
  # silently corrupts if that ever breaks, so assert it rather than assume it.
  defp assert_disjoint(replacements) do
    replacements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [{upper_start, _, _}, {_, lower_stop, _}] ->
      true = lower_stop < upper_start
    end)

    replacements
  end

  # Collects replacements from every module-shaped expr in a block - the file's
  # top level or a module body.
  defp replacements(block, source_lines) do
    block
    |> block_exprs()
    |> Enum.flat_map(&module_replacements(&1, source_lines))
  end

  defp block_exprs({:__block__, _, exprs}) when is_list(exprs), do: exprs
  defp block_exprs(expr), do: [expr]

  # A `defmodule`/`defimpl` yields its own replacement plus, recursively, those
  # of the module-shaped exprs in its body - regardless of whether it bails
  # itself, so e.g. a facade's nested modules still lay out. A defimpl body is
  # a plain module body; `defprotocol` bodies are signature defs, never
  # entered. The walk descends through module-body positions only: a
  # `defmodule` inside a def body rides with its def.
  #
  # `do_line` anchors the header span; a keyword-form module (`defmodule M,
  # do: ...`) carries no `:do` line metadata, so its own layout has nothing
  # to splice against and bails - but only per node: the walk still descends,
  # since nested modules carry their own anchors. The descent fetches `:do`
  # from the trailing option list, which the keyword form of defimpl shares
  # with `for:`.
  defp module_replacements({kind, meta, args}, source_lines) when kind in @module_kinds and is_list(args) do
    do_line = meta[:do][:line]

    case List.last(args) do
      [{:do, {:__block__, _, exprs} = body}] when is_list(exprs) and is_integer(do_line) ->
        own_replacement(exprs, do_line, source_lines) ++ replacements(body, source_lines)

      [_ | _] = opts ->
        case List.keyfind(opts, :do, 0) do
          {:do, body} -> replacements(body, source_lines)
          nil -> []
        end

      _ ->
        []
    end
  end

  defp module_replacements(_expr, _source_lines), do: []

  defp own_replacement(exprs, do_line, source_lines) do
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
