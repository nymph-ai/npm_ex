defmodule NPM.Install.ScriptInstallTest do
  use ExUnit.Case, async: false

  alias NPM.Install.ScriptInstall

  @test_opts [__skip_project_check__: true]

  setup do
    :persistent_term.erase(:npm_script_installed)
    :ok
  end

  test "installs packages to content-addressed cache dir" do
    deps = %{"is-number" => "^7.0.0"}
    assert :ok = ScriptInstall.install(deps, @test_opts)
    assert ScriptInstall.installed?()

    nm = ScriptInstall.node_modules_dir!()
    assert File.exists?(Path.join(nm, "is-number/package.json"))
  end

  test "second call with same deps is a noop" do
    deps = %{"is-number" => "^7.0.0"}
    assert :ok = ScriptInstall.install(deps, @test_opts)
    assert :ok = ScriptInstall.install(deps, @test_opts)
  end

  test "second call with different deps raises" do
    deps1 = %{"is-number" => "^7.0.0"}
    deps2 = %{"is-odd" => "^3.0.0"}
    assert :ok = ScriptInstall.install(deps1, @test_opts)

    assert_raise Mix.Error, ~r/same dependencies/, fn ->
      ScriptInstall.install(deps2, @test_opts)
    end
  end

  test "force reinstalls" do
    deps = %{"is-number" => "^7.0.0"}
    assert :ok = ScriptInstall.install(deps, @test_opts)
    assert :ok = ScriptInstall.install(deps, [force: true] ++ @test_opts)
  end

  @tag :integration
  test "persists and restores nested dependencies" do
    deps = %{"@vue-flow/core" => "1.48.2", "reka-ui" => "2.10.1"}

    assert :ok = ScriptInstall.install(deps, [force: true] ++ @test_opts)

    nm = ScriptInstall.node_modules_dir!()
    assert package_version(nm, "@vue-flow/core/node_modules/@vueuse/core") == "10.11.1"

    assert package_version(
             nm,
             "@vue-flow/core/node_modules/@vueuse/core/node_modules/@vueuse/shared"
           ) ==
             "10.11.1"

    lock_path = Path.join(ScriptInstall.install_dir!(), "npm.lock")
    assert {:ok, lockfile} = NPM.Lockfile.read(lock_path)
    nested_core = lockfile["@vue-flow/core"].nested_dependencies["@vueuse/core"]
    assert nested_core.version == "10.11.1"
    assert nested_core.nested_dependencies["@vueuse/shared"].version == "10.11.1"
    assert nested_core.nested_dependencies["@vueuse/metadata"].version == "10.11.1"

    File.rm_rf!(Path.join(nm, "@vue-flow/core/node_modules/@vueuse/core"))
    :persistent_term.erase(:npm_script_installed)

    assert :ok = ScriptInstall.install(deps, @test_opts)
    assert package_version(nm, "@vue-flow/core/node_modules/@vueuse/core") == "10.11.1"
  end

  test "install_dir! raises when not installed" do
    assert_raise Mix.Error, ~r/not been called/, fn ->
      ScriptInstall.install_dir!()
    end
  end

  defp package_version(node_modules, path) do
    node_modules
    |> Path.join(path)
    |> Path.join("package.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("version")
  end
end
