defmodule NPM.Install.NestedLockfileTest do
  use ExUnit.Case, async: true

  alias NPM.Install.NestedLockfile

  describe "add/3" do
    test "leaves lockfile unchanged when there are no nested packages" do
      lockfile = %{
        "parent" => %{
          version: "1.0.0",
          integrity: "sha512-parent==",
          tarball: "https://registry.npmjs.org/parent/-/parent-1.0.0.tgz",
          dependencies: %{},
          optional_dependencies: %{},
          has_install_script: false,
          nested_dependencies: %{}
        }
      }

      assert NestedLockfile.add(lockfile, %{}) == lockfile
    end
  end
end
