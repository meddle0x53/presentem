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

  def handle_continue(:start_polling_repository, %{provider: provider, repo: repo} = state) do
    unless File.exists?(@root_path) do
      File.mkdir_p!(@root_path)

      provider.fetch(repo)

      source_assets = Path.join(provider.local_path(), "assets")
      destination_assets = Path.join(@root_path, "assets")
      File.cp_r!(source_assets, destination_assets)

      source_presentations = Path.join(provider.local_path(), "presentations")

      source_presentations
      |> File.ls!()
      |> Enum.each(fn file_name ->
        if String.ends_with?(file_name, ".md") do
          source = Path.join(source_presentations, file_name)
          destination = Path.join(@root_path, file_name)

          File.cp!(source, destination)

          Rambo.run("npx", ["marp", "--htmml", file_name], cd: @root_path)

          File.rm!(destination)
        end
      end)

      # If no assets existed
      File.mkdir_p!(destination_assets)
    end

    :timer.send_interval(25_000, :poll_repository)

    {:noreply, state}
  end

  def handle_info(:poll_repository, %{provider: provider, repo: repo} = state) do
    case provider.fetch(repo) do
      :no_updates ->
        Logger.debug("No updates from repo, continuing to check")

      {:updates, updates} ->
        Logger.info("Updates #{inspect(updates)}")

        diff = provider.diff(updates)
        Logger.info("Diff #{inspect(diff)}")

        Enum.each(diff.updates, fn update ->
          file_name = Path.basename(update)
          source = Path.join(provider.local_path(), update)

          if source =~ ~r/^.*\/presentations\/.*\.md$/ do
            destination = Path.join(@root_path, file_name)
            File.cp!(source, destination)

            Rambo.run("npx", ["marp", file_name], cd: @root_path)

            File.rm!(destination)
          end

          if source =~ ~r/^.*\/assets\/.*$/ do
            destination = Path.join(@root_path, Path.join("assets", file_name))
            File.cp!(source, destination)
          end

          # Recreate index.html
          slide_data =
            @root_path
            |> File.ls!()
            |> Enum.filter(&String.ends_with?(&1, ".html"))
            |> Enum.reject(&(&1 == "index.html"))
            |> Enum.map(&{&1, File.stat!(Path.join(@root_path, &1))})
            |> Enum.sort_by(fn {_, %{ctime: ctime}} -> ctime end)
            |> Enum.map(fn {file_name, stats} ->
              html = File.read!(Path.join(@root_path, file_name))

              h1s = Regex.scan(~r/(<h1.*?>(.*?)<\/h1>)/, html)
              titles = List.first(h1s) || Regex.scan(~r/(<h2.*?>(.*?)<\/h2>)/, html) |> List.first()

              title =
                if is_list(titles) && !Enum.empty?(titles) do
                  List.last(titles)
                else
                  String.trim_trailing(file_name)
                end

                {Path.join("/slides", file_name), title, stats}
            end)


          html = Phoenix.View.render_to_string(PresentemWeb.PageView, "index.html", [slide_data: slide_data, layout: {PresentemWeb.LayoutView, "root.html"}])
          File.write!(Path.join(@root_path, "index.html"), html)
        end)
    end

    {:noreply, state}
  end
end
