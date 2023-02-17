defmodule Presentem.RepositoryProviders.Local do
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

  def init(args) do
    {:ok, watcher_pid} = FileSystem.start_link(args)

    FileSystem.subscribe(watcher_pid)
    {:ok, %{watcher_pid: watcher_pid, changes: []}}
  end

  def handle_info(
        {:file_event, watcher_pid, {path, events}},
        %{watcher_pid: watcher_pid, changes: changes} = state
      )
      when events in [[:modified], [:modified, :closed], [:created]] do
    path_parts =
      path
      |> String.split("/")
      |> Enum.reverse()

    case path_parts do
      [file, "presentations" | _] ->
        if String.ends_with?(file, ".md") do
          new_changes = [Path.join("presentations", file) | changes]

          {:noreply, %{state | changes: Enum.uniq(new_changes)}}
        else
          {:noreply, state}
        end

      [file, "assets" | _] ->
        new_changes = [Path.join("presentations", file) | changes]
        {:noreply, %{state | changes: Enum.uniq(new_changes)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:file_event, watcher_pid, {_path, _events}},
        %{watcher_pid: watcher_pid} = state
      ) do
    {:noreply, state}
  end

  def handle_info({:file_event, watcher_pid, :stop}, %{watcher_pid: watcher_pid} = state) do
    {:noreply, state}
  end

  def handle_call(:get_changes_and_reset, _from, %{changes: changes} = state) do
    {:reply, changes, %{state | changes: []}}
  end
end
