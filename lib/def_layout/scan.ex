defmodule DefLayout.Scan do
  @moduledoc false

  @def_kinds [:def, :defp]
  @attaching_attrs [:doc, :spec, :impl, :deprecated, :dialyzer]
  @attaching_macros [:attr, :slot]

  # Module-level constructs allowed to sit in the header above the functions.
  # Anything else in the header -> bail (see `header_safe?/1`).
  @header_attrs [:moduledoc]
  @header_directives [:use, :import, :alias, :require]

  @type def_group :: %{
          key: {atom, non_neg_integer},
          start: pos_integer,
          stop: pos_integer,
          lines: [String.t()]
        }

  # Slices a module body into ordered def_groups carrying their verbatim
  # source-line span. Returns :error (the caller bails, leaving the module
  # untouched) for anything it can't safely move: a non-function expression
  # interleaved among the functions, a private, an `@impl` def, non-adjacent
  # duplicate-key clauses, or a header with an unrecognized module-level construct.
  @spec def_groups([Macro.t()], pos_integer, [String.t()]) :: {:ok, [def_group]} | :error
  def def_groups(exprs, do_line, source_lines) do
    with {:ok, header, groups} <- partition(exprs),
         true <- header_safe?(header),
         true <- in_scope?(groups) do
      header_stop = Enum.max([do_line | Enum.map(header, &max_line/1)])
      {:ok, materialize(header_stop, groups, source_lines)}
    else
      _ -> :error
    end
  end

  defp partition(exprs) do
    {header, rest} = Enum.split_while(exprs, &(not def_group_part?(&1)))

    if rest != [] and Enum.all?(rest, &def_group_part?/1) do
      group_def_parts(rest, header)
    else
      :error
    end
  end

  defp group_def_parts(rest, header) do
    {groups, pending} = Enum.reduce(rest, {[], []}, &group_def_part/2)

    if pending == [] do
      groups =
        groups
        |> Enum.reverse()
        |> Enum.map(fn {key, exprs} -> {key, Enum.reverse(exprs)} end)

      # The reduce merges only *adjacent* same-key clauses into one def_group, so
      # non-adjacent clauses of one function leave duplicate keys; bail rather
      # than reorder a shape the scanner didn't model.
      unique_key_count =
        groups
        |> Enum.map(&elem(&1, 0))
        |> Enum.uniq()
        |> length()

      if unique_key_count == length(groups), do: {:ok, header, groups}, else: :error
    else
      :error
    end
  end

  # `pending` holds a function's leading attrs until its `def` arrives; same-key
  # clauses then merge into one group, so multi-clause functions stay together.
  defp group_def_part(expr, {groups, pending}) do
    if def_expr?(expr) do
      key = key_of(expr)

      case groups do
        [{^key, exprs} | rest] -> {[{key, [expr | pending] ++ exprs} | rest], []}
        _ -> {[{key, [expr | pending]} | groups], []}
      end
    else
      {groups, [expr | pending]}
    end
  end

  # An unrecognized attribute hugging the first def would be stranded when that
  # def moves, so bail. (`@doc`/`@spec`/... attach to their def, never the header.)
  defp header_safe?(header), do: Enum.all?(header, &allowed_header_expr?/1)

  defp allowed_header_expr?({:@, _, [{name, _, _}]}), do: name in @header_attrs
  defp allowed_header_expr?({directive, _, _}) when directive in @header_directives, do: true
  defp allowed_header_expr?(_), do: false

  # In scope (for now): only purely public defs not marked `@impl`.
  defp in_scope?(groups) do
    Enum.all?(groups, fn {_key, exprs} -> def_kind_of(exprs) == :def and not impl_group?(exprs) end)
  end

  # Slices each group into a verbatim list of source lines, extending upward to
  # capture leading comments. The gap above a group (between it and the previous
  # group, or the header) belongs to it from its first comment line down, so
  # free-floating comments ride along rather than being dropped.
  defp materialize(header_stop, groups, source_lines) do
    {def_groups, _prev_stop} =
      Enum.reduce(groups, {[], header_stop}, fn {key, exprs}, {acc, prev_stop} ->
        first_expr_line =
          exprs
          |> hd()
          |> meta_line()

        group_stop =
          exprs
          |> List.last()
          |> max_line()

        group_start = lead_start(source_lines, prev_stop + 1, first_expr_line)
        lines = Enum.slice(source_lines, (group_start - 1)..(group_stop - 1)//1)

        def_group = %{
          key: key,
          start: group_start,
          stop: group_stop,
          lines: lines
        }

        {[def_group | acc], group_stop}
      end)

    Enum.reverse(def_groups)
  end

  # First non-blank line in the gap is the topmost leading comment; the group
  # starts there. An all-blank gap means the group starts at its own first expr.
  defp lead_start(source_lines, gap_start, first_expr_line) do
    Enum.find(gap_start..(first_expr_line - 1)//1, &non_blank_line?(source_lines, &1)) ||
      first_expr_line
  end

  defp non_blank_line?(source_lines, line) do
    source_lines
    |> Enum.fetch!(line - 1)
    |> String.trim()
    |> Kernel.!=("")
  end

  defp def_kind_of(exprs) do
    exprs
    |> Enum.find(&def_expr?/1)
    |> elem(0)
  end

  defp impl_group?(exprs), do: Enum.any?(exprs, &match?({:@, _, [{:impl, _, _}]}, &1))

  defp def_group_part?({kind, _, _}) when kind in @def_kinds, do: true
  defp def_group_part?({:@, _, [{name, _, _}]}) when name in @attaching_attrs, do: true

  defp def_group_part?({macro, _, args}) when macro in @attaching_macros and is_list(args), do: true

  defp def_group_part?(_), do: false

  defp def_expr?({kind, _, _}) when kind in @def_kinds, do: true
  defp def_expr?(_), do: false

  defp key_of({_kind, _, [head | _]}), do: head_name_arity(head)

  defp head_name_arity({:when, _, [inner | _]}), do: head_name_arity(inner)
  defp head_name_arity({name, _, args}) when is_atom(name), do: {name, arity_of(args)}

  defp arity_of(args) when is_list(args), do: length(args)
  defp arity_of(_), do: 0

  defp meta_line({_, meta, _}), do: Keyword.fetch!(meta, :line)

  # Largest source line a node touches: its own `:line` plus the `:line` of any
  # nested metadata block (`:end`, `:closing`, `:do`, ... - handled generically).
  defp max_line(root_node) do
    {_node, max} =
      Macro.prewalk(root_node, 0, fn
        {_, meta, _} = node, acc when is_list(meta) -> {node, max(acc, meta_max_line(meta))}
        node, acc -> {node, acc}
      end)

    max
  end

  defp meta_max_line(meta) do
    Enum.reduce(meta, 0, fn
      {:line, line}, acc when is_integer(line) -> max(acc, line)
      {_key, nested_meta}, acc when is_list(nested_meta) -> max(acc, nested_meta[:line] || 0)
      {_key, _value}, acc -> acc
    end)
  end
end
