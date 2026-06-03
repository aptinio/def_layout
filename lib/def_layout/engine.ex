defmodule DefLayout.Engine do
  @moduledoc false

  # Roots are the public defs: callbacks (`@impl`) first in source order - their
  # lifecycle order (init/mount/terminate) is meaningful, so it's preserved, not
  # alphabetized - then the remaining publics alphabetical by `{name, arity}`.
  # Each private sinks just below its bottom-most caller (the caller that lands
  # lowest in the final layout), recursively: a private called only by another
  # private rides below that private. A private called by a callback anchors below
  # that callback. Co-anchored privates (several under one caller) follow the
  # caller's first-call-site order.
  #
  # Privates are placed in topological waves - a private is ready once every one
  # of its callers is already placed - so "bottom-most" reads off the order built
  # so far, which never reorders earlier entries. A reference cycle reachable from
  # a placed caller is broken at one member and anchored below it; only privates
  # with no placed caller at all - orphans, or a cycle no caller reaches - tail in
  # source order.
  @spec order([DefLayout.Scan.def_group()]) :: [DefLayout.Scan.def_group()]
  def order(def_groups) do
    by_key = Map.new(def_groups, &{&1.key, &1})
    callbacks = for g <- def_groups, g.kind == :def, g.callback?, do: g.key
    publics = for g <- def_groups, g.kind == :def, not g.callback?, do: g.key
    roots = callbacks ++ Enum.sort_by(publics, &sort_key(by_key, &1))
    privates = for g <- def_groups, g.kind == :defp, do: g.key

    {children, placed} = anchor(privates, by_key, roots, %{}, MapSet.new(roots))
    leftover = for k <- privates, not MapSet.member?(placed, k), do: k

    Enum.map(emit(roots, children, by_key) ++ leftover, &Map.fetch!(by_key, &1))
  end

  defp anchor(pending, by_key, roots, children, placed) do
    case Enum.filter(pending, &ready?(&1, by_key, placed)) do
      [] ->
        break_cycle(pending, by_key, roots, children, placed)

      ready ->
        order = emit(roots, children, by_key)

        children =
          Enum.reduce(ready, children, fn key, acc ->
            anchor_key = bottom_most_caller(key, by_key, order, placed)
            Map.update(acc, anchor_key, [key], &[key | &1])
          end)

        placed = Enum.reduce(ready, placed, &MapSet.put(&2, &1))
        anchor(pending -- ready, by_key, roots, children, placed)
    end
  end

  # A private is ready once it has at least one caller and all its callers are
  # placed. Orphans (no caller) never qualify and drop to the source-order fallback.
  defp ready?(key, by_key, placed) do
    callers = callers_of(key, by_key)
    callers != [] and Enum.all?(callers, &MapSet.member?(placed, &1))
  end

  # Nothing is ready, so a reference cycle is blocking progress. Break it at one
  # genuine cycle member that has a placed caller, then resume - its non-cycle
  # dependents (merely blocked by the cycle) become ready naturally and anchor to
  # their true bottom-most caller. The member is chosen by key, not source order,
  # so the break is identical across runs (idempotent). When no cycle member has a
  # placed caller, only unreachable privates remain and `order/1` tails them.
  defp break_cycle(pending, by_key, roots, children, placed) do
    pending_set = MapSet.new(pending)

    breakable =
      Enum.filter(pending, fn key ->
        on_cycle?(key, pending_set, by_key) and has_placed_caller?(key, by_key, placed)
      end)

    case breakable do
      [] ->
        {children, placed}

      _ ->
        key = Enum.min_by(breakable, &sort_key(by_key, &1))
        order = emit(roots, children, by_key)
        anchor_key = bottom_most_caller(key, by_key, order, placed)
        children = Map.update(children, anchor_key, [key], &[key | &1])
        anchor(pending -- [key], by_key, roots, children, MapSet.put(placed, key))
    end
  end

  # A pending private is on a cycle when one of its pending callees can reach it
  # back, following call edges that stay within the pending set.
  defp on_cycle?(key, pending_set, by_key) do
    key
    |> pending_callees(pending_set, by_key)
    |> Enum.any?(&reaches?(&1, key, pending_set, by_key, MapSet.new()))
  end

  defp reaches?(target, target, _pending_set, _by_key, _visited), do: true

  defp reaches?(from, target, pending_set, by_key, visited) do
    if MapSet.member?(visited, from) do
      false
    else
      visited = MapSet.put(visited, from)

      from
      |> pending_callees(pending_set, by_key)
      |> Enum.any?(&reaches?(&1, target, pending_set, by_key, visited))
    end
  end

  defp pending_callees(key, pending_set, by_key) do
    for callee <- Map.fetch!(by_key, key).calls, MapSet.member?(pending_set, callee), do: callee
  end

  defp has_placed_caller?(key, by_key, placed) do
    key
    |> callers_of(by_key)
    |> Enum.any?(&MapSet.member?(placed, &1))
  end

  defp sort_key(by_key, key) do
    {name, arity} = Map.fetch!(by_key, key).key
    {Atom.to_string(name), arity}
  end

  defp emit(keys, children, by_key) do
    Enum.flat_map(keys, fn key ->
      kids =
        children
        |> Map.get(key, [])
        |> Enum.sort_by(&first_call_site(by_key, key, &1))

      [key | emit(kids, children, by_key)]
    end)
  end

  defp first_call_site(by_key, caller_key, child_key) do
    by_key
    |> Map.fetch!(caller_key)
    |> Map.fetch!(:calls)
    |> Enum.find_index(&(&1 == child_key))
  end

  # Among the key's placed callers, the one lowest in the layout built so far.
  # In a topological wave every caller is placed; mid-cycle, only some are.
  defp bottom_most_caller(key, by_key, order, placed) do
    key
    |> callers_of(by_key)
    |> Enum.filter(&MapSet.member?(placed, &1))
    |> Enum.max_by(fn caller -> Enum.find_index(order, &(&1 == caller)) end)
  end

  defp callers_of(key, by_key) do
    for {caller, g} <- by_key, key != caller, key in g.calls, do: caller
  end
end
