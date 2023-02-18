defmodule Presentem.RepositoryProviders.LocalNative do
  use GenServer

  require Logger

  @behaviour Presentem.RepositoryProvider

  @local_path Application.compile_env(:presentem, :repository_url)

  #############
  # Callbacks #
  #############

  defstruct [:folder_state]

  def repository do
    File.mkdir_p!(@local_path)
    File.mkdir_p!(Path.join(@local_path, "presentations"))
    File.mkdir_p!(Path.join(@local_path, "assets"))

    {:ok, repo} = start_link(dirs: [@local_path])

    repo
  end

  def fetch(repo) do
    changes = GenServer.call(repo, :get_changes_and_reset)

    if Enum.empty?(changes) do
      :no_updates
    else
      {:updates, changes}
    end
  end

  def local_path, do: @local_path

  defdelegate diff(updates), to: Presentem.RepositoryProviders.Git
  defdelegate list_files(folder), to: Presentem.RepositoryProviders.Git
  defdelegate read_file(file_path, folder \\ ""), to: Presentem.RepositoryProviders.Git

  def file_in?(file), do: File.exists?(Path.join(@local_path, file))

  def file_info(_repo, file_path) do
    file = Path.join(@local_path, file_path)

    %{
      atime: {{cyyyy, cmm, cdd}, {chh, cmmin, css}},
      mtime: {{uyyyy, umm, udd}, {uhh, ummin, uss}}
    } = File.stat!(file)

    %{
      created_at:
        DateTime.new!(Date.new!(cyyyy, cmm, cdd), Time.new!(chh, cmmin, css))
        |> DateTime.to_iso8601(),
      updated_at:
        DateTime.new!(Date.new!(uyyyy, umm, udd), Time.new!(uhh, ummin, uss))
        |> DateTime.to_iso8601()
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    {:ok, %{changes: [], current_state: []}, {:continue, :start_watching_local_path}}
  end

  def handle_continue(:start_watching_local_path, state) do
    :timer.send_interval(10_000, :check_local_path)
    {:noreply, %{state | current_state: local_state()}}
  end

  def handle_info(:check_local_path, %{current_state: current_state} = state) do
    files = local_state()

    updates =
      ((current_state -- files) ++ (files -- current_state))
      |> Enum.map(fn {file, _} -> file end)
      |> Enum.uniq()

    new_state =
      Enum.reduce(updates, state, fn path, %{changes: changes} = acc ->
        path_parts =
          path
          |> String.split("/")
          |> Enum.reverse()

        case path_parts do
          [file, "presentations" | _] ->
            if String.ends_with?(file, ".md") do
              new_changes = [Path.join("presentations", file) | changes]

              %{acc | changes: Enum.uniq(new_changes)}
            else
              acc
            end

          [file, "assets" | _] ->
            new_changes = [Path.join("assets", file) | changes]
            %{acc | changes: Enum.uniq(new_changes)}

          _ ->
            acc
        end
      end)

    {:noreply, %{new_state | current_state: files}}
  end

  def handle_call(:get_changes_and_reset, _from, %{changes: changes} = state) do
    {:reply, changes, %{state | changes: []}}
  end

  defp local_state do
    files = list_files("")

    Enum.map(files, fn file_path ->
      file = Path.join(@local_path, file_path)
      %{mtime: mtime} = File.stat!(file)

      {file, mtime}
    end)
  end
end
