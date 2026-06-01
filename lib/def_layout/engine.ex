defmodule DefLayout.Engine do
  @moduledoc false

  @spec order([DefLayout.Scan.def_group()]) :: [DefLayout.Scan.def_group()]
  def order(def_groups), do: Enum.sort_by(def_groups, &sort_key/1)

  defp sort_key(%{key: {name, arity}}), do: {Atom.to_string(name), arity}
end
