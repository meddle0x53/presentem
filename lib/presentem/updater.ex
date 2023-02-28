defmodule Presentem.Updater do
  @moduledoc """
  The Updater GenServer process has to be created with a module that implements the `Presentem.RepositoryProvider`
  behavior.

  The provider's repository is being checked periodically for updates and if there are any, the Updater will try to
  build html slides for them and put them in a folder they can be served from. For now we use the marp_cli external
  tool for that, but the idea is to have replacable converters.

  A simple index.html, listing the presentations is also built on every update.
  """
  use GenServer

  require Logger

  @root_path "_presentations"

  @rebuild_index_delay 3_000
  @update_interval 30_000

  @spec start_link([module]) :: GenServer.on_start()
  def start_link([repository_provider]) do
    GenServer.start_link(__MODULE__, repository_provider, name: __MODULE__)
  end

  def init(repository_provider) do
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
          {:ok, _md_content, _} = generate_presentation_and_return_content(source, destination)
        end
      end)

      # If no assets existed
      File.mkdir_p!(destination_assets)
      rebuild_index()
    end

    :timer.send_interval(@update_interval, :poll_repository)
    Process.send_after(self(), :rebuild_index, @rebuild_index_delay)

    {:noreply, state}
  end

  def handle_info(:rebuild_index, state) do
    rebuild_index()

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

            {:ok, md_content, file_name} =
              generate_presentation_and_return_content(source, destination)

            live_md_content =
              md_content
              |> Enum.filter(fn slide -> String.contains?(slide, "```elixir") end)
              |> Enum.join("")
              |> String.trim()

            if live_md_content != "" do
              title = slide_title(String.replace_suffix(file_name, ".md", ".html"))

              live_md_content = "# #{title}\n\n#{live_md_content}"

              livemd_destination = String.replace_suffix(destination, ".md", ".livemd")
              Logger.info("Writing livemd to #{livemd_destination}")

              File.write!(livemd_destination, live_md_content)
            else
              Logger.warn("No livemd content")
            end
          end

          if source =~ ~r/^.*\/assets\/.*$/ do
            destination = Path.join(@root_path, Path.join("assets", file_name))
            File.cp!(source, destination)
          end
        end)

        # Recreate index.html
        Process.send_after(self(), :rebuild_index, @rebuild_index_delay)
    end

    {:noreply, state}
  end

  defp generate_presentation_and_return_content(source, destination) do
    md_content =
      source
      |> File.read!()
      |> String.split("---")

    directives =
      md_content
      |> Enum.drop_while(fn slide -> String.trim(slide) == "" end)
      |> List.first()

    hidden = directives =~ ~r/\s*hidden\s*:\s*true\s*/
    pre_output = String.replace_suffix(destination, ".md", ".html")

    output =
      if hidden do
        if File.exists?(pre_output) do
          Logger.info("Hiding a previously visible file.")
          File.rm!(pre_output)
        end

        [file | rest] =
          pre_output
          |> Path.split()
          |> Enum.reverse()

        [".#{file}" | rest]
        |> Enum.reverse()
        |> Path.join()
      else
        pre_output
      end

    port = Port.open({:spawn, "npx marp #{source} --html -o #{output}"}, [])
    Port.close(port)

    wait_for_output(output)

    file_name = Path.basename(output)

    {:ok, md_content, file_name}
  end

  defp rebuild_index do
    slide_data =
      @root_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".html"))
      |> Enum.reject(&(&1 == "index.html"))
      |> Enum.map(&{&1, File.stat!(Path.join(@root_path, &1))})
      |> Enum.sort_by(fn {_, %{ctime: ctime}} -> ctime end)
      |> Enum.map(fn {file_name, stats} ->
        if String.starts_with?(file_name, ".") do
          :hidden
        else
          title = slide_title(file_name)

          livemd_file = String.replace_suffix(file_name, ".html", ".livemd")
          livemd_path = Path.join(@root_path, livemd_file)

          livemd_location =
            if File.exists?(livemd_path) do
              Path.join("/slides", livemd_file)
            else
              :no_live_md
            end

          {Path.join("/slides", file_name), title, stats, livemd_location}
        end
      end)
      |> Enum.reject(fn file_data -> file_data == :hidden end)

    html =
      Phoenix.View.render_to_string(PresentemWeb.PageView, "index.html",
        slide_data: slide_data,
        layout: {PresentemWeb.LayoutView, "root.html"}
      )

    File.write!(Path.join(@root_path, "index.html"), html)
  end

  defp slide_title(file_name) do
    html = File.read!(Path.join(@root_path, file_name))

    h1s = Regex.scan(~r/(<h1.*?>(.*?)<\/h1>)/, html)
    titles = List.first(h1s) || Regex.scan(~r/(<h2.*?>(.*?)<\/h2>)/, html) |> List.first()

    if is_list(titles) && !Enum.empty?(titles) do
      List.last(titles)
    else
      String.trim_trailing(file_name)
    end
  end

  defp wait_for_output(path) do
    if File.exists?(path) do
      :ok
    else
      Logger.info("Waiting for output file #{path}")

      Process.sleep(100)
      wait_for_output(path)
    end
  end
end
