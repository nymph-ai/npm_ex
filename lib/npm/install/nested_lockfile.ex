defmodule NPM.Install.NestedLockfile do
  @moduledoc false

  @doc "Attach persisted nested dependency entries to a lockfile."
  @spec add(map(), map(), (String.t(), String.t(), map() -> term())) :: map()
  def add(lockfile, nested_info, on_package \\ fn _name, _version, _info -> :ok end)
  def add(lockfile, nested_info, _on_package) when nested_info == %{}, do: lockfile

  def add(lockfile, nested_info, on_package) do
    Enum.reduce(nested_info, lockfile, fn {nested_pkg, _}, acc ->
      original_deps = NPM.Resolver.get_original_deps(nested_pkg)

      Enum.reduce(acc, acc, fn {parent_name, parent_entry}, inner_acc ->
        key = "#{parent_name}@#{parent_entry.version}"

        case Map.get(original_deps, key) do
          nil -> inner_acc
          range -> add_nested_dependency(inner_acc, parent_name, nested_pkg, range, on_package)
        end
      end)
    end)
  end

  defp add_nested_dependency(lockfile, parent_name, nested_pkg, range, on_package) do
    with {:ok, nested_entry} <-
           build_nested_entry(nested_pkg, range, lockfile, on_package, MapSet.new()) do
      update_in(lockfile, [parent_name, :nested_dependencies], fn nested ->
        Map.put(nested || %{}, nested_pkg, nested_entry)
      end)
    else
      _ -> lockfile
    end
  end

  defp build_nested_entry(name, range, flat_lockfile, on_package, visited) do
    with {:ok, version_str, info} <- resolve_version(name, range) do
      key = "#{name}@#{version_str}"

      if MapSet.member?(visited, key) do
        :error
      else
        on_package.(name, version_str, info)
        visited = MapSet.put(visited, key)

        nested_dependencies =
          info
          |> dependencies_from_info()
          |> Enum.reject(fn {dep, dep_range} ->
            flat_dependency_satisfies?(flat_lockfile, dep, dep_range)
          end)
          |> Enum.reduce(%{}, fn {dep, dep_range}, acc ->
            case build_nested_entry(dep, dep_range, flat_lockfile, on_package, visited) do
              {:ok, entry} -> Map.put(acc, dep, entry)
              :error -> acc
            end
          end)

        {:ok,
         %{
           version: version_str,
           integrity: info.dist.integrity,
           tarball: info.dist.tarball,
           dependencies: info.dependencies,
           optional_dependencies: info.optional_dependencies,
           has_install_script: info.has_install_script,
           nested_dependencies: nested_dependencies
         }}
      end
    end
  end

  defp dependencies_from_info(info) do
    info.dependencies
    |> Map.merge(NPM.PlatformOptional.select(info.optional_dependencies))
  end

  defp flat_dependency_satisfies?(flat_lockfile, dep, range) do
    case Map.get(flat_lockfile, dep) do
      %{version: version} -> version_matches?(version, range)
      _ -> false
    end
  end

  defp resolve_version(name, range) do
    case NPM.Registry.get_packument(name) do
      {:ok, packument} ->
        packument.versions
        |> Enum.filter(fn {v, _} ->
          version_matches?(v, range) and match?({:ok, _}, Version.parse(v))
        end)
        |> Enum.sort_by(fn {v, _} -> Version.parse!(v) end, {:desc, Version})
        |> case do
          [{version_str, info} | _] -> {:ok, version_str, info}
          [] -> :error
        end

      _ ->
        :error
    end
  end

  defp version_matches?(version, range) do
    NPMSemver.matches?(version, range)
  rescue
    ArgumentError -> false
  end
end
