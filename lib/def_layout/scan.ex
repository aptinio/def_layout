defmodule DefLayout.Scan do
  @moduledoc false

  @def_kinds [:def, :defp]
  @delegate_kinds [:defdelegate]
  @macro_kinds [:defmacro, :defmacrop, :defguard, :defguardp]
  @group_kinds @def_kinds ++ @macro_kinds
  @attaching_attrs [:doc, :spec, :impl, :deprecated, :dialyzer]
  @attaching_macros [:attr, :slot]

  # Module-level constructs allowed to sit in the header above the functions.
  # Anything else in the header -> bail (see `header_safe?/1`).
  @header_attrs [:moduledoc] ++
                  [:behaviour, :behavior] ++
                  [:type, :typep, :opaque, :callback, :macrocallback, :optional_callbacks] ++
                  [:derive, :enforce_keys] ++
                  [:compile, :before_compile, :after_compile, :after_verify, :on_load] ++
                  [:vsn, :external_resource]
  @header_directives [:use, :import, :alias, :require]
  # Recognized by name, like `def`/`import`: we assume standard Kernel semantics.
  # Shadowing these into def-attaching macros is out of scope (would strand silently).
  @header_macros [:defstruct, :defexception]
  # A nested module bracketing the functions is an opaque, immovable anchor:
  # frozen in source order, in the header above them or the trailer below
  # them. Deliberately broader than the plugin's recursion list -
  # `defprotocol` freezes in both tiers but is never recursed into.
  @nested_module_kinds [:defmodule, :defimpl, :defprotocol]

  @type def_group :: %{
          key: {atom, non_neg_integer},
          kind: :def | :defp | :defdelegate | :defmacro | :defmacrop | :defguard | :defguardp,
          callback?: boolean,
          pinned?: boolean,
          calls: [{atom, non_neg_integer}],
          start: pos_integer,
          stop: pos_integer,
          lines: [String.t()]
        }

  # Slices a module body into ordered def_groups carrying their verbatim
  # source-line span. Returns `{:error, reason}` (the caller bails, leaving the
  # module untouched) for anything it can't safely move: a non-function
  # expression interleaved among the functions (nested modules bracketing them
  # - above the first or below the last - are frozen tiers, not interleaved), a
  # used macro/guard below the first function definition, a nested module
  # sitting among the functions, expansion-time code in a pinned macro that
  # calls one of the module's functions, non-adjacent duplicate-key clauses,
  # or a header with an unrecognized module-level construct. The reason atom
  # names which bail fired (first one wins, via the short-circuiting
  # with-chain); `Mix.Tasks.DefLayout.Skipped` maps it to a phrase.
  @type bail_reason ::
          :no_defs
          | :interleaved_expression
          | :nested_module
          | :non_adjacent_clauses
          | :unrecognized_header
          | :used_macro_below_def
          | :expansion_calls_function

  @spec def_groups([Macro.t()], pos_integer, [String.t()]) ::
          {:ok, [def_group]} | {:error, bail_reason}
  def def_groups(exprs, do_line, source_lines) do
    with {:ok, header, groups} <- partition(exprs),
         :ok <- header_safe?(header),
         {:ok, pinned_keys} <- classify_pinned(header, groups) do
      header_stop = Enum.max([do_line | Enum.map(header, &max_line/1)])
      {:ok, materialize(header_stop, groups, pinned_keys, source_lines)}
    end
  end

  # Compile-time definitions (macros/guards) are define-before-use, so their
  # position is load-bearing exactly when the module uses them - which also
  # pushes them above the first function. Used ones pin: `DefLayout.Engine`
  # keeps them first, in source order. A provably inert public macro/guard is
  # just a public and sorts with the rest. Used *below* the first function
  # definition could only move (or have defs permute around it) safely with
  # edge-accurate call detection, where a scanner miss is a compile error
  # rather than a cosmetic miss, so bail instead.
  #
  # Inert is decided by a conservative scan of the header and the movable
  # groups: the macro's name occurs nowhere in them outside its own group, and
  # its own group references no in-module compile-time name. The trailer is
  # not scanned - sound, because it sits below everything the engine moves, so
  # a reference from there lands below the macro wherever it sorts. Every
  # doubt - quote contents, variables or atom literals sharing the name -
  # resolves to "used", so the failure direction is over-pinning, never a
  # broken build. Private macros/guards never sort: an unused
  # defmacrop/defguardp is a compiler warning, so in warnings-clean code
  # they're always used.
  defp classify_pinned(header, groups) do
    group_refs = Enum.map(groups, fn {_key, exprs} -> referenced_names(exprs) end)
    header_refs = referenced_names(header)

    macro_names =
      for {{name, _arity}, _exprs} = group <- groups,
          macro_group?(group),
          into: MapSet.new(),
          do: name

    pinned_keys =
      for {{{name, _arity} = key, exprs} = group, index} <- Enum.with_index(groups),
          macro_group?(group),
          def_kind_of(exprs) in [:defmacrop, :defguardp] or
            not inert?(name, index, {header_refs, group_refs}, macro_names),
          into: MapSet.new(),
          do: key

    with {:ok, pinned_keys} <- close_expansions(groups, pinned_keys) do
      first_def_index =
        Enum.find_index(groups, fn group -> not macro_group?(group) end) || length(groups)

      pinned_below_first_def? =
        groups
        |> Enum.with_index()
        |> Enum.any?(fn {{key, _exprs}, index} ->
          index > first_def_index and MapSet.member?(pinned_keys, key)
        end)

      if pinned_below_first_def?, do: {:error, :used_macro_below_def}, else: {:ok, pinned_keys}
    end
  end

  # A pinned defmacro referenced in an expansion-time position runs during
  # this module's compile, and an expansion is arbitrary code the syntactic
  # scan can't see into. Two consequences, both closed here: the expansion
  # could invoke a sorted macro by a name computed at expansion time, so no
  # macro may sort (every macro pins); and any local function the pin's own
  # expansion-time code calls must stay above the expansion site - a
  # constraint placement can't honor, so bail. Macros referenced only inside
  # quotes never expand here (quoted code runs at the expansion site's
  # runtime), an expanded guard is just a substitution of syntax the scan
  # already saw, and the header can't expand a macro at all (its expressions
  # evaluate above every macro definition - compile error), so none of those
  # trigger. Both break shapes were verified to compile in source order and
  # fail when sorted/tailed.
  defp close_expansions(groups, pinned_keys) do
    group_exp = Enum.map(groups, fn {_key, exprs} -> expansion_time_names(exprs) end)

    expanded_pins =
      for {{{name, _arity} = key, exprs}, index} <- Enum.with_index(groups),
          MapSet.member?(pinned_keys, key),
          def_kind_of(exprs) in [:defmacro, :defmacrop],
          group_exp
          |> List.delete_at(index)
          |> Enum.any?(&MapSet.member?(&1, name)),
          do: index

    def_names =
      for {{name, _arity}, exprs} <- groups,
          def_kind_of(exprs) in (@def_kinds ++ @delegate_kinds),
          into: MapSet.new(),
          do: name

    cond do
      expanded_pins == [] ->
        {:ok, pinned_keys}

      Enum.any?(expanded_pins, &(not MapSet.disjoint?(Enum.fetch!(group_exp, &1), def_names))) ->
        {:error, :expansion_calls_function}

      true ->
        {:ok, for({key, _exprs} = group <- groups, macro_group?(group), into: MapSet.new(), do: key)}
    end
  end

  defp inert?(name, index, {header_refs, group_refs}, macro_names) do
    own_refs = Enum.fetch!(group_refs, index)
    other_refs = List.delete_at(group_refs, index)

    not Enum.any?([header_refs | other_refs], &(name in &1)) and
      MapSet.disjoint?(own_refs, MapSet.delete(macro_names, name))
  end

  defp macro_group?({_key, exprs}), do: def_kind_of(exprs) in @macro_kinds

  # Every atom the AST mentions - call heads, bare names and variables,
  # literal atoms, quote contents. Nameless invocation forms need no special
  # handling: a non-quoted in-module use/import/require of the module itself
  # is a compile error ("currently being defined", so `__using__`'s position
  # is never load-bearing here), `@before_compile __MODULE__` and
  # `@on_definition __MODULE__` are compile errors for the same reason, and
  # `@after_compile`/`@after_verify` self-hooks target plain functions, whose
  # position is free. All verified empirically.
  defp referenced_names(ast) do
    {_node, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, _} = node, acc when is_atom(name) ->
          {node, MapSet.put(acc, name)}

        node, acc when is_atom(node) ->
          {node, MapSet.put(acc, node)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  # Call-shaped names evaluated when this code runs at macro expansion:
  # everything outside `quote`, plus `unquote`/`unquote_splicing` fragments
  # and a quote's opts (`bind_quoted:` values) within one. Code that's merely
  # quoted runs at the expansion site's runtime instead, so it imposes no
  # define-before-use constraint here.
  defp expansion_time_names(exprs) do
    exprs
    |> Enum.filter(&def_expr?/1)
    |> Enum.reduce(MapSet.new(), fn {_kind, _, [head | body]}, acc ->
      acc = exp_names(head_expansion_terms(head), false, acc)
      Enum.reduce(body, acc, &exp_names(&1, false, &2))
    end)
  end

  # A head contributes its guard and its default-argument expressions - a
  # macro in either expands when the def compiles (verified: `x \\ mac()`
  # errors at definition when `mac` isn't defined yet). The defining call
  # isn't a use of its own name, and argument patterns aren't expansion-time
  # code.
  defp head_expansion_terms({:when, _, [call | guards]}), do: guards ++ argument_defaults(call)
  defp head_expansion_terms(head), do: argument_defaults(head)

  defp argument_defaults({_name, _, args}) when is_list(args) do
    for {:\\, _, [_pattern, default]} <- args, do: default
  end

  defp argument_defaults(_head), do: []

  defp exp_names({:quote, _, args}, false, acc) when is_list(args) do
    Enum.reduce(args, acc, fn
      arg, acc when is_list(arg) ->
        Enum.reduce(arg, acc, fn
          {:do, block}, acc -> exp_names(block, true, acc)
          other, acc -> exp_names(other, false, acc)
        end)

      arg, acc ->
        exp_names(arg, false, acc)
    end)
  end

  defp exp_names({unquote_kind, _, [expr]}, true, acc) when unquote_kind in [:unquote, :unquote_splicing],
    do: exp_names(expr, false, acc)

  # A local capture evaluated at expansion requires the function defined too.
  defp exp_names({:&, _, [{:/, _, [{name, _, ctx}, arity]}]}, false, acc)
       when is_atom(name) and is_atom(ctx) and is_integer(arity), do: MapSet.put(acc, name)

  defp exp_names({name, _, args}, false, acc) when is_atom(name) and is_list(args),
    do: Enum.reduce(args, MapSet.put(acc, name), &exp_names(&1, false, &2))

  defp exp_names({head, _, args}, quoted?, acc) when is_list(args),
    do: Enum.reduce([head | args], acc, &exp_names(&1, quoted?, &2))

  defp exp_names({a, b}, quoted?, acc), do: exp_names(b, quoted?, exp_names(a, quoted?, acc))

  defp exp_names(list, quoted?, acc) when is_list(list), do: Enum.reduce(list, acc, &exp_names(&1, quoted?, &2))

  defp exp_names(_other, _quoted?, acc), do: acc

  # Header above the first def-family expr, the functions, then an optional
  # trailer: the maximal trailing run of nested modules, frozen in place - the
  # def region stops at the last function, so trailer lines are never touched.
  # STRICT: any other trailing expr lands in the middle and fails the
  # all-def-parts check, bailing the module. Trailer exprs are dropped here,
  # which also keeps them out of the inert-macro analysis - sound, because the
  # trailer sits below everything the engine moves, so even a genuine
  # reference from there lands below the macro wherever it sorts.
  defp partition(exprs) do
    {header, rest} = Enum.split_while(exprs, &(not def_group_part?(&1)))

    {_trailer, middle} =
      rest
      |> Enum.reverse()
      |> Enum.split_while(&nested_module?/1)

    middle = Enum.reverse(middle)

    cond do
      middle == [] ->
        # No def-family expression anywhere: a declaration-only module body
        # (a `@moduledoc` plus `use`/`@behaviour`/... ) has nothing to lay
        # out, so it's vacuously conformant - distinct from a module whose
        # functions are interleaved with a stray expression.
        {:error, :no_defs}

      Enum.all?(middle, &def_group_part?/1) ->
        group_def_parts(middle, header)

      true ->
        {:error, interleaved_reason(middle)}
    end
  end

  # A nested module sitting among (not bracketing) the functions reads
  # differently from a stray statement, so name it. Anything else - a reassigned
  # attribute or a bare expression among the functions - is the generic
  # interleaved case.
  defp interleaved_reason(middle) do
    if Enum.any?(middle, &nested_module?/1), do: :nested_module, else: :interleaved_expression
  end

  defp nested_module?({kind, _, _}) when kind in @nested_module_kinds, do: true
  defp nested_module?(_), do: false

  defp group_def_parts(middle, header) do
    {groups, pending} = Enum.reduce(middle, {[], []}, &group_def_part/2)

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

      if unique_key_count == length(groups),
        do: {:ok, header, groups},
        else: {:error, :non_adjacent_clauses}
    else
      # A def-part with no def to attach to is left pending - a dangling
      # attribute among the functions, the generic interleaved case.
      {:error, :interleaved_expression}
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
  defp header_safe?(header) do
    if Enum.all?(header, &allowed_header_expr?/1), do: :ok, else: {:error, :unrecognized_header}
  end

  defp allowed_header_expr?({:@, _, [{name, _, _}]}), do: name in @header_attrs
  defp allowed_header_expr?({directive, _, _}) when directive in @header_directives, do: true
  defp allowed_header_expr?({macro, _, _}) when macro in @header_macros, do: true
  defp allowed_header_expr?({kind, _, _}) when kind in @nested_module_kinds, do: true
  defp allowed_header_expr?(_), do: false

  # Slices each group into a verbatim list of source lines, extending upward to
  # capture leading comments. The gap above a group (between it and the previous
  # group, or the header) belongs to it from its first comment line down, so
  # free-floating comments ride along rather than being dropped.
  defp materialize(header_stop, groups, pinned_keys, source_lines) do
    ranges = arity_ranges(groups)

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
          kind: def_kind_of(exprs),
          callback?: callback_group?(exprs),
          pinned?: MapSet.member?(pinned_keys, key),
          calls: calls_in(exprs, ranges),
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

  # A group is a callback when it carries an `@impl` marker - except `@impl false`,
  # which is Elixir's explicit *non*-callback marker (it errors if the function
  # actually matches a callback), so such a def stays an ordinary public.
  defp callback_group?(exprs), do: Enum.any?(exprs, &callback_impl?/1)

  defp callback_impl?({:@, _, [{:impl, _, [false]}]}), do: false
  defp callback_impl?({:@, _, [{:impl, _, [_value]}]}), do: true
  defp callback_impl?(_), do: false

  # The `{name, arity}` local calls in a group's clause bodies and argument
  # defaults (a default lands in the generated reduced-arity clause, so a call
  # there is a real runtime edge), in first-call-site order (dedup keeps the
  # earliest). The defining head and guards aren't uses, attachments
  # (`@doc`/`@spec`/`attr`/`slot`) contribute nothing, and a recursive body's
  # self-edge is ignored by the engine. Each call resolves against the module's
  # arity ranges so a call through a defaulted head lands on the defining
  # group's key. Drives caller-anchoring in `DefLayout.Engine`.
  defp calls_in(exprs, ranges) do
    exprs
    |> Enum.filter(&def_expr?/1)
    |> Enum.flat_map(fn
      # A delegate's "body" is its to:/as: options, not code - only its head
      # defaults contribute edges.
      {:defdelegate, _, [head | _]} -> default_calls(head)
      {_kind, _, [head | body]} -> default_calls(head) ++ collect_calls(body)
    end)
    |> Enum.map(&resolve_call(&1, ranges))
    |> Enum.uniq()
  end

  defp default_calls(head) do
    head
    |> head_call()
    |> argument_defaults()
    |> collect_calls()
  end

  # A head with defaults defines every arity from full-minus-defaults to full.
  defp arity_ranges(groups) do
    for {{name, arity} = key, exprs} <- groups do
      {name, arity - max_default_count(exprs), arity, key}
    end
  end

  defp max_default_count(exprs) do
    exprs
    |> Enum.filter(&def_expr?/1)
    |> Enum.map(fn {_kind, _, [head | _]} ->
      head
      |> head_call()
      |> argument_defaults()
      |> length()
    end)
    |> Enum.max()
  end

  defp head_call({:when, _, [call | _]}), do: call
  defp head_call(head), do: head

  # A call inside a group's arity range resolves to that group's key. Among
  # overlapping ranges (a defaults conflict the compiler rejects anyway) the
  # lowest full arity wins - the exact-arity group when one exists - keeping
  # the choice independent of source order, which keeps reordering idempotent.
  defp resolve_call({name, arity} = call, ranges) do
    case for({^name, min, max, key} <- ranges, arity >= min, arity <= max, do: {max, key}) do
      [] ->
        call

      candidates ->
        candidates
        |> Enum.min()
        |> elem(1)
    end
  end

  defp collect_calls(ast) do
    {_node, calls} =
      ast
      |> Macro.prewalk(&unpipe/1)
      |> Macro.prewalk([], fn
        # A local function capture `&name/arity` references it without calling it.
        {:&, _, [{:/, _, [{name, _, ctx}, arity]}]} = node, acc
        when is_atom(name) and is_atom(ctx) and is_integer(arity) ->
          {node, [{name, arity} | acc]}

        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, [{name, length(args)} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end

  # `lhs |> f(a)` calls `f/2`, not `f/1`: the piped value is f's first argument.
  # Rewrite each local pipe into the plain call so the collector sees the real
  # arity. Remote targets (name is a `.`-tuple, not an atom) are left untouched.
  defp unpipe({:|>, _, [lhs, {name, meta, args}]}) when is_atom(name) and (is_list(args) or is_nil(args)) do
    {name, meta, [lhs | List.wrap(args)]}
  end

  defp unpipe(node), do: node

  defp def_group_part?({:defdelegate, _, _} = expr), do: def_expr?(expr)
  defp def_group_part?({kind, _, _}) when kind in @group_kinds, do: true
  defp def_group_part?({:@, _, [{name, _, _}]}) when name in @attaching_attrs, do: true

  defp def_group_part?({macro, _, args}) when macro in @attaching_macros and is_list(args), do: true

  defp def_group_part?(_), do: false

  # A delegate counts only with a call-shaped head: the deprecated list form
  # (`defdelegate [a(x), b(y)], to: M`) has no single key, so it stays
  # unrecognized and the module bails.
  defp def_expr?({:defdelegate, _, [{name, _, _} | _]}) when is_atom(name), do: true
  defp def_expr?({:defdelegate, _, _}), do: false
  defp def_expr?({kind, _, _}) when kind in @group_kinds, do: true
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
