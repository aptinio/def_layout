defmodule Mix.Tasks.DefLayout.SkippedTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.DefLayout.Skipped

  defp skipped(source), do: Skipped.skipped_modules(source, "lib/example.ex")

  describe "skipped_modules/2 - what counts as skipped" do
    test "a module the engine reorders is NOT skipped" do
      source = """
      defmodule M do
        def beta, do: 2
        def alpha, do: 1
      end
      """

      assert skipped(source) == []
    end

    test "an already-conformant module is NOT skipped (case c)" do
      source = """
      defmodule M do
        def alpha, do: 1
        def beta, do: 2
      end
      """

      assert skipped(source) == []
    end

    test "a module with an interleaved expression IS skipped (case a - partition bail)" do
      source = """
      defmodule M do
        def beta, do: 2
        @x 1
        def alpha, do: 1
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "M", "an expression interleaved among the functions"}]
    end

    test "a module with an unrecognized header construct IS skipped (case a - header bail)" do
      source = """
      defmodule M do
        @timeout 5_000
        def beta, do: 2
        def alpha, do: 1
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "M", "an unrecognized construct above the first def"}]
    end

    test "a keyword-form module IS skipped (case b - no :do line)" do
      source = """
      defmodule M, do: (def b, do: 2; def a, do: 1)
      """

      assert skipped(source) == [{"lib/example.ex", 1, "M", "keyword-form module body"}]
    end

    test "a module with no def-family at all is NOT skipped" do
      source = """
      defmodule M do
        @moduledoc "docs"
      end
      """

      assert skipped(source) == []
    end

    test "a declaration-only module body (use + @moduledoc, no defs) is NOT skipped" do
      source = """
      defmodule M do
        @moduledoc "docs"
        use Foo
      end
      """

      assert skipped(source) == []
    end

    test "a module with several declarations but no defs is NOT skipped" do
      source = """
      defmodule M do
        @moduledoc "docs"
        use Boundary
        @behaviour SomeBehaviour
      end
      """

      assert skipped(source) == []
    end

    test "an unmovable construct WITH defs to lay out is still skipped" do
      # No def-family means nothing to lay out, but once there are defs an
      # unmovable construct above them genuinely blocks the layout, so it must
      # still be reported - the no-defs suppression must not swallow this.
      source = """
      defmodule M do
        plug(:authenticate)
        def beta, do: 2
        def alpha, do: 1
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "M", "an unrecognized construct above the first def"}]
    end

    test "unparseable source is NOT reported" do
      assert skipped("defmodule M do") == []
    end
  end

  describe "skipped_modules/2 - reason per bail site" do
    test "a nested module among the functions reports that reason" do
      source = """
      defmodule M do
        def beta, do: 2

        defmodule Inner do
          def x, do: 1
        end

        def alpha, do: 1
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "M", "a nested module among the functions"}]
    end

    test "non-adjacent clauses of the same function report that reason" do
      source = """
      defmodule M do
        def a, do: 1
        def b, do: 2
        def a, do: 3
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "M", "non-adjacent clauses of the same function"}]
    end

    test "a used macro below the first def reports that reason" do
      source = """
      defmodule M do
        def a do
          mac()
        end

        defmacro mac, do: quote(do: :ok)
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "M", "a used macro below the first def"}]
    end

    test "expansion-time code calling a function reports that reason" do
      source = """
      defmodule M do
        defmacro one do
          quote do
            unquote(helper())
          end
        end

        defmacro two, do: quote(do: :ok)

        def use_one do
          one()
        end

        def use_two do
          two()
        end

        defp helper, do: :ok
      end
      """

      assert skipped(source) ==
               [
                 {"lib/example.ex", 1, "M", "expansion-time code calls one of the module's functions"}
               ]
    end
  end

  describe "skipped_modules/2 - per module, per nesting" do
    test "an inner module is skipped while the outer lays out" do
      source = """
      defmodule Outer do
        defmodule Inner do
          def b, do: 2
          @x 1
          def a, do: 1
        end

        def beta, do: 2
        def alpha, do: 1
      end
      """

      assert skipped(source) ==
               [
                 {"lib/example.ex", 2, "Outer.Inner", "an expression interleaved among the functions"}
               ]
    end

    test "the outer module is skipped while an inner lays out" do
      source = """
      defmodule Outer do
        @timeout 1
        defmodule Inner do
          def b, do: 2
          def a, do: 1
        end

        def beta, do: 2
        def alpha, do: 1
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "Outer", "an unrecognized construct above the first def"}]
    end

    test "a defimpl block is labelled with its protocol and target" do
      source = """
      defimpl String.Chars, for: MyType do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """

      assert skipped(source) ==
               [
                 {"lib/example.ex", 1, "String.Chars (for: MyType)", "an unrecognized construct above the first def"}
               ]
    end

    test "a defimpl without an explicit for: keeps just the protocol name" do
      source = """
      defimpl Inspect do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "Inspect", "an unrecognized construct above the first def"}]
    end

    test "a __MODULE__-named module is labelled __MODULE__" do
      source = """
      defimpl Inspect, for: __MODULE__ do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """

      assert skipped(source) ==
               [
                 {"lib/example.ex", 1, "Inspect (for: __MODULE__)", "an unrecognized construct above the first def"}
               ]
    end

    test "a dynamically-named module falls back to its source text" do
      source = """
      defmodule Module.concat([Foo, Bar]) do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """

      assert skipped(source) ==
               [
                 {"lib/example.ex", 1, "Module.concat([Foo, Bar])", "an unrecognized construct above the first def"}
               ]
    end

    test "both outer and inner can be skipped, reported in source order" do
      source = """
      defmodule Outer do
        @timeout 1
        defmodule Inner do
          def b, do: 2
          @y 1
          def a, do: 1
        end

        def beta, do: 2
        def alpha, do: 1
      end
      """

      assert skipped(source) == [
               {"lib/example.ex", 1, "Outer", "an unrecognized construct above the first def"},
               {"lib/example.ex", 3, "Outer.Inner", "an expression interleaved among the functions"}
             ]
    end

    test "an option-only module with no body reports nothing and does not crash" do
      assert skipped("defmodule M, foo: 1\n") == []
      assert skipped("defmodule(M)\n") == []
      assert skipped("defimpl Inspect\n") == []
    end

    test "a keyword-form defimpl carrying for: and a block body IS skipped (case b)" do
      source = """
      defimpl Inspect, for: MyType, do: (def b, do: 2; def a, do: 1)
      """

      assert skipped(source) ==
               [{"lib/example.ex", 1, "Inspect (for: MyType)", "keyword-form module body"}]
    end

    test "a keyword-form module with extra options and a block body IS skipped (case b)" do
      source = """
      defmodule M, foo: 1, do: (def b, do: 2; def a, do: 1)
      """

      assert skipped(source) == [{"lib/example.ex", 1, "M", "keyword-form module body"}]
    end

    test "a keyword-form module with a non-block body is NOT skipped" do
      assert skipped("defimpl Inspect, for: MyType, do: :ok\n") == []
    end

    test "a keyword-form module with no defs of its own still descends" do
      source = """
      defmodule Outer, do: (defmodule Inner do
        def b, do: 2
        @x 1
        def a, do: 1
      end)
      """

      assert skipped(source) ==
               [
                 {"lib/example.ex", 1, "Outer.Inner", "an expression interleaved among the functions"}
               ]
    end

    test "sibling top-level modules each report independently" do
      source = """
      defmodule A do
        @x 1
        def b, do: 2
        def a, do: 1
      end

      defmodule Ok do
        def b, do: 2
        def a, do: 1
      end

      defmodule C do
        def b, do: 2
        @y 1
        def a, do: 1
      end
      """

      assert skipped(source) == [
               {"lib/example.ex", 1, "A", "an unrecognized construct above the first def"},
               {"lib/example.ex", 12, "C", "an expression interleaved among the functions"}
             ]
    end
  end

  describe "run/1 - CLI" do
    @tag :tmp_dir
    test "lists skipped modules across the given files", %{tmp_dir: tmp_dir} do
      skip_path = Path.join(tmp_dir, "skip.ex")
      ok_path = Path.join(tmp_dir, "ok.ex")

      File.write!(skip_path, """
      defmodule Skip do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """)

      File.write!(ok_path, """
      defmodule Ok do
        def b, do: 2
        def a, do: 1
      end
      """)

      output = ExUnit.CaptureIO.capture_io(fn -> Skipped.run([skip_path, ok_path]) end)

      assert output =~ skip_path
      assert output =~ "Skip"
      refute output =~ "ok.ex"
      refute output =~ "Ok\n"
    end

    @tag :tmp_dir
    test "with no arguments, reads :inputs from .formatter.exs", %{tmp_dir: tmp_dir} do
      lib_dir = Path.join(tmp_dir, "lib")
      formatter_path = Path.join(tmp_dir, ".formatter.exs")
      skip_path = Path.join(lib_dir, "skip.ex")
      File.mkdir_p!(lib_dir)
      File.write!(formatter_path, ~s([inputs: ["lib/**/*.ex"]]))

      File.write!(skip_path, """
      defmodule Skip do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """)

      output =
        File.cd!(tmp_dir, fn ->
          ExUnit.CaptureIO.capture_io(fn -> Skipped.run([]) end)
        end)

      assert output == "lib/skip.ex:1: Skip - an unrecognized construct above the first def\n"
    end

    @tag :tmp_dir
    test "reports nothing when no module is skipped", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "ok.ex")

      File.write!(path, """
      defmodule Ok do
        def b, do: 2
        def a, do: 1
      end
      """)

      output = ExUnit.CaptureIO.capture_io(fn -> Skipped.run([path]) end)

      assert output =~ "No skipped modules"
    end

    @tag :tmp_dir
    test "a directory among the given paths is ignored, not read", %{tmp_dir: tmp_dir} do
      sub = Path.join(tmp_dir, "sub")
      skip = Path.join(tmp_dir, "skip.ex")
      File.mkdir_p!(sub)

      File.write!(skip, """
      defmodule Skip do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """)

      output =
        ExUnit.CaptureIO.capture_io(fn -> Skipped.run([tmp_dir <> "/*"]) end)

      assert output =~ "Skip"
    end

    @tag :tmp_dir
    test "non-.ex/.exs files among the given paths are ignored", %{tmp_dir: tmp_dir} do
      text = Path.join(tmp_dir, "notes.txt")
      File.write!(text, "defmodule NotCode do\n@x 1\ndef b, do: 2\ndef a, do: 1\nend\n")

      output = ExUnit.CaptureIO.capture_io(fn -> Skipped.run([text]) end)

      assert output =~ "No skipped modules"
    end

    @tag :tmp_dir
    test "a file matched by overlapping globs is reported once", %{tmp_dir: tmp_dir} do
      skip = Path.join(tmp_dir, "skip.ex")

      File.write!(skip, """
      defmodule Skip do
        @x 1
        def b, do: 2
        def a, do: 1
      end
      """)

      output =
        ExUnit.CaptureIO.capture_io(fn -> Skipped.run([skip, tmp_dir <> "/*.ex"]) end)

      assert output
             |> String.split("\n", trim: true)
             |> Enum.count(&(&1 =~ "Skip")) == 1
    end
  end

  describe "inputs/1 - mix format file-selection parity" do
    @tag :tmp_dir
    test "expands :inputs relative to the formatter's directory", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      nested_dir = Path.join(tmp_dir, "lib/nested")
      a = Path.join(tmp_dir, "lib/a.ex")
      b = Path.join(tmp_dir, "lib/nested/b.ex")
      File.write!(formatter, ~s([inputs: ["lib/**/*.ex"]]))
      File.mkdir_p!(nested_dir)
      File.write!(a, "defmodule A do\nend\n")
      File.write!(b, "defmodule B do\nend\n")

      selected = Skipped.inputs(tmp_dir)
      assert Enum.sort(selected) == ["lib/a.ex", "lib/nested/b.ex"]
    end

    @tag :tmp_dir
    test "drops files matched by :excludes", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      lib_dir = Path.join(tmp_dir, "lib")
      keep = Path.join(tmp_dir, "lib/keep.ex")
      skip = Path.join(tmp_dir, "lib/skip_me.ex")
      File.write!(formatter, ~s([inputs: ["lib/**/*.ex"], excludes: ["lib/skip_me.ex"]]))
      File.mkdir_p!(lib_dir)
      File.write!(keep, "defmodule Keep do\nend\n")
      File.write!(skip, "defmodule SkipMe do\nend\n")

      assert Skipped.inputs(tmp_dir) == ["lib/keep.ex"]
    end

    @tag :tmp_dir
    test "recurses into :subdirectories, each with its own .formatter.exs", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      root = Path.join(tmp_dir, "root.ex")
      app_dir = Path.join(tmp_dir, "apps/my_app")
      app_lib = Path.join(app_dir, "lib")
      app_formatter = Path.join(app_dir, ".formatter.exs")
      app_file = Path.join(app_dir, "lib/thing.ex")
      File.write!(formatter, ~s([inputs: ["root.ex"], subdirectories: ["apps/*"]]))
      File.write!(root, "defmodule Root do\nend\n")
      File.mkdir_p!(app_lib)
      File.write!(app_formatter, ~s([inputs: ["lib/**/*.ex"]]))
      File.write!(app_file, "defmodule Thing do\nend\n")

      selected = Skipped.inputs(tmp_dir)
      assert Enum.sort(selected) == ["apps/my_app/lib/thing.ex", "root.ex"]
    end

    @tag :tmp_dir
    test "a :subdirectories glob does not match dot directories (mix parity)", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      hidden = Path.join(tmp_dir, ".hidden_app")
      hidden_formatter = Path.join(hidden, ".formatter.exs")
      hidden_file = Path.join(hidden, "thing.ex")
      File.write!(formatter, ~s([subdirectories: ["*"]]))
      File.mkdir_p!(hidden)
      File.write!(hidden_formatter, ~s([inputs: ["*.ex"]]))
      File.write!(hidden_file, "defmodule Thing do\nend\n")

      assert Skipped.inputs(tmp_dir) == []
    end

    @tag :tmp_dir
    test "a subdirectory glob without a .formatter.exs contributes nothing", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      bare = Path.join(tmp_dir, "apps/bare")
      stray = Path.join(bare, "stray.ex")
      File.write!(formatter, ~s([subdirectories: ["apps/*"]]))
      File.mkdir_p!(bare)
      File.write!(stray, "defmodule Stray do\nend\n")

      assert Skipped.inputs(tmp_dir) == []
    end

    @tag :tmp_dir
    test "dedups a file claimed by overlapping inputs", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      lib_dir = Path.join(tmp_dir, "lib")
      a = Path.join(tmp_dir, "lib/a.ex")
      File.write!(formatter, ~s([inputs: ["lib/**/*.ex", "lib/a.ex"]]))
      File.mkdir_p!(lib_dir)
      File.write!(a, "defmodule A do\nend\n")

      assert Skipped.inputs(tmp_dir) == ["lib/a.ex"]
    end

    @tag :tmp_dir
    test "keeps only .ex/.exs files", %{tmp_dir: tmp_dir} do
      formatter = Path.join(tmp_dir, ".formatter.exs")
      lib_dir = Path.join(tmp_dir, "lib")
      ex = Path.join(tmp_dir, "lib/a.ex")
      exs = Path.join(tmp_dir, "lib/b.exs")
      heex = Path.join(tmp_dir, "lib/c.heex")
      File.write!(formatter, ~s([inputs: ["lib/**/*"]]))
      File.mkdir_p!(lib_dir)
      File.write!(ex, "defmodule A do\nend\n")
      File.write!(exs, "x = 1\n")
      File.write!(heex, "<div></div>\n")

      selected = Skipped.inputs(tmp_dir)
      assert Enum.sort(selected) == ["lib/a.ex", "lib/b.exs"]
    end
  end
end
