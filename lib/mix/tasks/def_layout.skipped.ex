defmodule Mix.Tasks.DefLayout.Skipped do
  @shortdoc "Lists the modules DefLayout declines to lay out"

  @moduledoc """
  Lists the module bodies DefLayout skips - the ones it leaves in source order
  rather than laying out.

      mix def_layout.skipped [PATHS...]

  With no arguments it reads the `:inputs` from your `.formatter.exs`, matching
  the files `mix format` would format. Pass file paths or globs to scan those
  instead.

  Each skipped module is listed with its location and the reason it was
  skipped, one per line:

      path:line: Module.Label - reason

  A module is reported when DefLayout can't safely move its definitions - an
  expression or nested module interleaved among the functions, non-adjacent
  clauses of the same function, an unrecognized construct above the first def,
  a used macro below the first def, expansion-time code that calls one of the
  module's functions, or a keyword-form module body. Reporting is per module,
  including nested ones: an inner module can be skipped while its outer lays
  out, and the reverse. Already-laid-out modules are not reported. The reason
  echoes the README's "What gets skipped" vocabulary, so it indexes the section
  that explains why each case is skipped.
  """

  use Mix.Task

  alias DefLayout.Scan

  @module_kinds [:defmodule, :defimpl]

  @impl Mix.Task
  def run(argv) do
    {_opts, paths, _} = OptionParser.parse(argv, strict: [])

    paths
    |> files()
    |> Enum.flat_map(fn path -> skipped_modules(File.read!(path), path) end)
    |> report()
  end

  defp report([]) do
    Mix.shell().info("No skipped modules.")
  end

  defp report(skips) do
    for {path, line, label, reason} <- skips do
      Mix.shell().info("#{path}:#{line}: #{label} - #{reason}")
    end
  end

  defp files([]), do: inputs(File.cwd!())

  defp files(paths) do
    paths
    |> Enum.flat_map(fn path -> Path.wildcard(path, match_dot: true) end)
    |> Enum.uniq()
    |> Enum.filter(&elixir_file?/1)
  end

  # Mirrors `mix format`'s no-argument file selection (`Mix.Tasks.Format`'s
  # `expand_dot_inputs`/`eval_subs_opts`): the top-level `.formatter.exs`
  # `:inputs` minus `:excludes`, then each `:subdirectories` entry's own
  # `.formatter.exs` resolved relative to that subdirectory, deduped across
  # overlapping claims. Only the file SET is mimicked - never plugin loading or
  # formatting - so a no-argument run scans exactly what would be formatted.
  @doc false
  def inputs(cwd) do
    cwd
    |> dot_formatter_files(Path.join(cwd, ".formatter.exs"))
    |> Enum.uniq()
    |> Enum.filter(&elixir_file?/1)
    |> Enum.map(&Path.relative_to(&1, cwd))
  end

  defp dot_formatter_files(cwd, dot_formatter) do
    opts = eval_formatter(dot_formatter)

    excluded =
      opts
      |> Keyword.get(:excludes)
      |> List.wrap()
      |> Enum.flat_map(&wildcard(&1, cwd))
      |> MapSet.new()

    inputs =
      for input <- List.wrap(opts[:inputs]),
          file <- wildcard(input, cwd),
          file not in excluded,
          do: file

    inputs ++ subdirectory_files(opts, cwd)
  end

  defp eval_formatter(path) do
    if File.regular?(path) do
      {opts, _} = Code.eval_file(path)
      opts
    else
      []
    end
  end

  defp wildcard(glob, cwd) do
    glob
    |> Path.expand(cwd)
    |> Path.wildcard(match_dot: true)
  end

  defp subdirectory_files(opts, cwd) do
    # `mix format` expands `:subdirectories` with a plain `Path.wildcard` - no
    # `match_dot:` - so dot directories are not matched here (unlike `:inputs`).
    for sub_glob <- List.wrap(opts[:subdirectories]),
        sub <-
          sub_glob
          |> Path.expand(cwd)
          |> Path.wildcard(),
        sub_formatter = Path.join(sub, ".formatter.exs"),
        File.exists?(sub_formatter),
        file <- dot_formatter_files(sub, sub_formatter),
        do: file
  end

  defp elixir_file?(path) do
    Path.extname(path) in ~w(.ex .exs) and File.regular?(path)
  end

  @doc """
  Returns a `{path, line, label, reason}` tuple for every skipped module body
  in `source`, in source order, descending through nested modules. `line` is
  the module node's source line and `reason` is the explanatory phrase.
  """
  @spec skipped_modules(String.t(), Path.t()) :: [{Path.t(), pos_integer, String.t(), String.t()}]
  def skipped_modules(source, path) do
    case Code.string_to_quoted(source, token_metadata: true) do
      {:ok, ast} ->
        source_lines = String.split(source, "\n")

        ast
        |> module_skips(source_lines, "")
        |> Enum.map(fn {line, label, reason} -> {path, line, label, phrase(reason)} end)

      {:error, _} ->
        []
    end
  end

  # Mirrors DefLayout's own module walk: each `defmodule`/`defimpl` is checked,
  # then its body is descended into regardless of whether it bailed, so a
  # facade's nested modules are still reported. The name prefix accumulates so
  # nested labels read fully-qualified.
  defp module_skips(block, source_lines, prefix) do
    block
    |> block_exprs()
    |> Enum.flat_map(&one_module(&1, source_lines, prefix))
  end

  defp block_exprs({:__block__, _, exprs}) when is_list(exprs), do: exprs
  defp block_exprs(expr), do: [expr]

  defp one_module({kind, meta, args}, source_lines, prefix) when kind in @module_kinds and is_list(args) do
    label = label(kind, args, prefix)
    line = Keyword.fetch!(meta, :line)
    do_line = meta[:do][:line]

    case List.last(args) do
      [{:do, {:__block__, _, exprs} = body}] when is_list(exprs) and is_integer(do_line) ->
        own_skip(exprs, do_line, source_lines, line, label) ++
          module_skips(body, source_lines, label)

      [_ | _] = opts ->
        # Any other options list is keyword-form (no `do/end` block, so no
        # integer `:do` line). When its `:do` is a block of expressions -
        # whether the list is just `[do: ...]` or also carries `for:`/other
        # options, as the keyword form of `defimpl` does - DefLayout can't
        # splice it, so it's a skip (case b). A non-block body (a literal or a
        # single statement) has nothing to lay out. Either way, descend in case
        # the body holds a nested module.
        case List.keyfind(opts, :do, 0) do
          {:do, {:__block__, _, exprs} = body} when is_list(exprs) ->
            [{line, label, :keyword_form} | module_skips(body, source_lines, label)]

          {:do, body} ->
            module_skips(body, source_lines, label)

          nil ->
            []
        end

      _ ->
        []
    end
  end

  defp one_module(_expr, _source_lines, _prefix), do: []

  defp label(:defimpl, [name | rest], prefix) do
    base = qualify(prefix, alias_name(name))

    rest
    |> List.first()
    |> for_target()
    |> case do
      nil -> base
      target -> "#{base} (for: #{target})"
    end
  end

  defp label(_kind, [name | _], prefix), do: qualify(prefix, alias_name(name))

  defp qualify("", name), do: name
  defp qualify(prefix, name), do: "#{prefix}.#{name}"

  defp for_target(opts) when is_list(opts) do
    case List.keyfind(opts, :for, 0) do
      {:for, target} -> alias_name(target)
      nil -> nil
    end
  end

  defp for_target(_), do: nil

  defp alias_name({:__aliases__, _, segments}), do: Enum.map_join(segments, ".", &to_string/1)
  defp alias_name({:__MODULE__, _, _}), do: "__MODULE__"
  defp alias_name(other), do: Macro.to_string(other)

  # Case (a): the scan bails, carrying which bail fired. A successful scan -
  # whether it reorders or the module is already conformant (case c) - is not a
  # skip. A `:no_defs` body has no def-family to lay out, so it's vacuously
  # conformant too, not a decline: never reported.
  defp own_skip(exprs, do_line, source_lines, line, label) do
    case Scan.def_groups(exprs, do_line, source_lines) do
      {:ok, _groups} -> []
      {:error, :no_defs} -> []
      {:error, reason} -> [{line, label, reason}]
    end
  end

  # The scan's reason atoms and the keyword-form case map to phrases that echo
  # the README's "What gets skipped" vocabulary verbatim.
  defp phrase(:interleaved_expression), do: "an expression interleaved among the functions"
  defp phrase(:nested_module), do: "a nested module among the functions"
  defp phrase(:non_adjacent_clauses), do: "non-adjacent clauses of the same function"
  defp phrase(:unrecognized_header), do: "an unrecognized construct above the first def"
  defp phrase(:used_macro_below_def), do: "a used macro below the first def"

  defp phrase(:expansion_calls_function), do: "expansion-time code calls one of the module's functions"

  defp phrase(:keyword_form), do: "keyword-form module body"
end
