defmodule DefLayoutTest do
  use ExUnit.Case, async: true

  doctest DefLayout

  test "greets the world" do
    assert DefLayout.hello() == :world
  end
end
