defmodule Presentem.Updater do
  use GenServer

  require Logger

  @root_path "_presentations"

  @spec start_link([module]) :: GenServer.on_start()
  def start_link([repository_provider]) do
    GenServer.start_link(__MODULE__, repository_provider, name: __MODULE__)
  end

  def init(repository_provider) do
    {:ok, repository_provider}

    {:ok, %{provider: repository_provider, repo: repository_provider.repository()},
     {:continue, :start_polling_repository}}
  end

  def handle_continue(:start_polling_repository, state) do
    File.mkdir_p!(@root_path)

    :timer.send_interval(20_000, :poll_repository)

    {:noreply, state}
  end

  def handle_info(:poll_repository, %{provider: provider, repo: repo} = state) do
    case provider.fetch(repo) do
      :no_updates ->
        Logger.debug("No updates from repo, continuing to check")

      {:updates, updates} ->
        Logger.info("All files #{inspect(provider.list_files("./presentations"))}")
        Logger.info("Updates #{inspect(updates)}")

        diff = provider.diff(updates)
        Logger.info("Diff #{inspect(diff)}")

        Enum.each(diff.updates, fn update ->
          file_name = Path.basename(update)
          destination = Path.join(@root_path, file_name)

          File.cp!(Path.join(provider.local_path(), update), destination)

          Rambo.run("npx", ["marp", file_name], cd: @root_path)
        end)
    end

    {:noreply, state}
  end
end
