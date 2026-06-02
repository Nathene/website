defmodule WebsiteWeb.TerminalLive do
  use WebsiteWeb, :live_view

  def mount(_params, _session, socket) do
    banner = ~S"""
      _   _       _   _                  _   _                _
     | \ | |     | | | |                | | | |              | |
     |  \| | __ _| |_| |__   __ _ _ __  | |_| | ___ _ __  ___| |__  _   _
     | . ` |/ _` | __| '_ \ / _` | '_ \ |  _  |/ _ \ '_ \/ __| '_ \| | | |
     | |\  | (_| | |_| | | | (_| | | | || | | |  __/ | | \__ \ |_) | |_| |
     \_| \_/\__,_|\__|_| |_|\__,_|_| |_|\_| |_/\___|_| |_|___/_.__/ \__, |
                                                                     __/ |
                                                                    |___/
    """

    boot_text = """
    NATHAN-OS v2.0.26 (x86_64-beam-linux-gnu)

    [ OK ] Initialized BEAM Virtual Machine
    [ OK ] Mounted /home/nathan/resume
    [ OK ] Started Authentication Service
    [ OK ] Loaded Profile: Software Engineer @ Macquarie Group

    Website is ready. Type 'help' to list available utilities.
    """

    initial_buffer = [
      %{type: :ascii, content: banner},
      %{type: :text, content: boot_text}
    ]

    {:ok,
     assign(socket,
       buffer: initial_buffer,
       current_input: "",
       show_sticky: true,
       active_window: nil
     )}
  end

  # Intercept the 'open' command before it hits the normal evaluator
  def handle_event("execute", %{"command" => "open " <> filename}, socket) do
    path = Path.join([:code.priv_dir(:website), "resume", String.trim(filename)])

    case File.read(path) do
      {:ok, content} ->
        {:ok, html, _} = Earmark.as_html(content)
        # Add the command to history, but open the window!
        new_buffer = socket.assigns.buffer ++ [%{type: :input, content: "❯ open #{filename}"}]

        {:noreply,
         assign(socket, buffer: new_buffer, active_window: %{title: filename, content: html})}

      {:error, _} ->
        nil
        # ... handle error (file not found)
    end
  end

  def handle_event("close_window", _, socket) do
    {:noreply, assign(socket, active_window: nil)}
  end

  # --------------------------------------------------
  # 1. Execute Command Handler
  # --------------------------------------------------
  def handle_event("execute", %{"command" => input}, socket) do
    input = String.trim(input)

    if input == "" do
      new_buffer = socket.assigns.buffer ++ [%{type: :input, content: "❯ "}]
      {:noreply, assign(socket, buffer: new_buffer, current_input: "")}
    else
      [cmd | args] = String.split(input, " ")

      case evaluate_command(cmd, args) do
        :clear ->
          {:noreply, assign(socket, buffer: [], current_input: "")}

        output when is_list(output) ->
          new_buffer =
            socket.assigns.buffer ++
              [%{type: :input, content: "❯ #{input}"}] ++
              output

          {:noreply, assign(socket, buffer: new_buffer, current_input: "")}
      end
    end
  end

  # --------------------------------------------------
  # 2. Autocomplete Handler (Array Mode)
  # --------------------------------------------------
  def handle_event("autocomplete", %{"value" => current_input}, socket) do
    parts = String.split(current_input, " ", parts: 2)

    matches =
      case parts do
        # Case A: Base commands
        [cmd] ->
          commands = ["help", "ls", "cat", "bat", "clear", "sysinfo", "tree", "sudo"]
          Enum.filter(commands, fn c -> String.starts_with?(c, cmd) end)

        # Case B: File targeting
        [cmd, file_prefix] when cmd in ["cat", "bat"] ->
          dir_path = Path.join(:code.priv_dir(:website), "resume")

          case File.ls(dir_path) do
            {:ok, files} ->
              files
              |> Enum.filter(fn f -> String.starts_with?(f, file_prefix) end)
              |> Enum.map(fn f -> "#{cmd} #{f}" end)

            _ ->
              []
          end

        _ ->
          []
      end

    # If we found at least one match, push the whole array to JS
    if matches != [] do
      {:noreply, push_event(socket, "update_autocomplete", %{matches: matches})}
    else
      {:noreply, socket}
    end
  end

  # --------------------------------------------------
  # 3. UI Interactions
  # --------------------------------------------------
  def handle_event("remove_sticky", _, socket) do
    {:noreply, assign(socket, show_sticky: false)}
  end

  defp evaluate_command("help", _args) do
    man_page = """
    NATHAN-SHELL(1)             General Commands Manual            NATHAN-SHELL(1)

    NAME
           help - display information about available portfolio utilities

    SYNOPSIS
           help

    DESCRIPTION
           The following commands are compiled and native to this live session:

           ls               List all valid markdown targets inside the directory tree.
           tree             Display the current file system structure in a visual hierarchy.
           cat <file>       Render contents inside a custom syntax-highlighted frame.
           sysinfo          Query the underlying virtual machine for real-time telemetry.
           clear            Wipe the terminal buffer, returning prompt to the origin.
           help             Display this system reference documentation.

    AUTHOR
           Nathan Hensby <nathanvisnjic@gmail.com>
    """

    [%{type: :text, content: man_page}]
  end

  defp evaluate_command("sysinfo", _args) do
    # Introspect the BEAM VM for real-time telemetry
    memory = :erlang.memory()
    total_mb = Float.round(memory[:total] / 1024 / 1024, 2)
    proc_mb = Float.round(memory[:processes] / 1024 / 1024, 2)

    procs = :erlang.system_info(:process_count)
    procs_limit = :erlang.system_info(:process_limit)

    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_secs = div(uptime_ms, 1000)
    threads = :erlang.system_info(:schedulers_online)
    arch = :erlang.system_info(:system_architecture) |> to_string()

    telemetry = """
    SYSTEM TELEMETRY [BEAM VM]
    --------------------------------------------------
    Architecture:  #{arch}
    Schedulers:    #{threads} thread(s) active
    Uptime:        #{uptime_secs} seconds
    Processes:     #{procs} active / #{procs_limit} limit
    Memory Total:  #{total_mb} MB
    Memory Procs:  #{proc_mb} MB
    --------------------------------------------------
    """

    [%{type: :text, content: telemetry}]
  end

  defp evaluate_command("sudo", _args) do
    content = """
    nathan is not in the sudoers file.
    This incident will be reported to.. me actually.
    """

    [%{type: :error, content: content}]
  end

  defp evaluate_command("ls", _args) do
    dir_path = Path.join(:code.priv_dir(:website), "resume")

    files =
      case File.ls(dir_path) do
        {:ok, list} -> Enum.sort(list)
        _ -> []
      end

    # Pass the actual array of files to the frontend using a custom :ls type
    [%{type: :ls, files: files}]
  end

  defp evaluate_command("clear", _args) do
    :clear
  end

  defp evaluate_command("tree", _args) do
    dir_path = Path.join(:code.priv_dir(:website), "resume")

    # Kick off the recursive tree builder
    case build_tree(dir_path, "") do
      {:ok, tree_lines, dir_count, file_count} ->
        # Pluralize output correctly (e.g., "1 directory" vs "2 directories")
        dir_label = if dir_count == 1, do: "directory", else: "directories"
        file_label = if file_count == 1, do: "file", else: "files"

        tree_output = """
        resume/
        #{tree_lines}

        #{dir_count} #{dir_label}, #{file_count} #{file_label}
        """

        [%{type: :text, content: tree_output}]

      {:error, _} ->
        [%{type: :error, content: "tree: permission denied or directory not found"}]
    end
  end

  defp evaluate_command("cat", [filename]) do
    path = Path.join([:code.priv_dir(:website), "resume", filename])

    if String.contains?(path, "..") do
      [%{type: :error, content: "no path traversal pls"}]
    else
      path
      |> safe_read(filename)
    end
  end

  defp evaluate_command(unknown, _args) do
    [%{type: :error, content: "Unknown command: #{unknown}"}]
  end

  defp safe_read(path, filename) do
    case File.read(path) do
      {:ok, content} ->
        # Parse the entire file cleanly as a single string block
        {:ok, html_content, _} = Earmark.as_html(content)
        [%{type: :bat, filename: filename, html: html_content}]

      {:error, _} ->
        [%{type: :error, content: "cat: #{filename}: No such file or directory"}]
    end
  end

  # --- Recursive Helper Function ---
  defp build_tree(path, prefix) do
    case File.ls(path) do
      {:ok, items} ->
        sorted_items = Enum.sort(items)
        count = length(sorted_items)

        {tree_str, d_count, f_count} =
          sorted_items
          |> Enum.with_index()
          |> Enum.reduce({"", 0, 0}, fn {item, index}, {acc_str, acc_d, acc_f} ->
            is_last? = index == count - 1
            connector = if is_last?, do: "└── ", else: "├── "
            child_prefix = if is_last?, do: "    ", else: "│   "

            full_path = Path.join(path, item)
            is_dir? = File.dir?(full_path)

            # THE FIX: Just return raw 1 or 0 for the current item
            {d_inc, f_inc} = if is_dir?, do: {1, 0}, else: {0, 1}
            current_line = "#{prefix}#{connector}#{item}\n"

            {sub_str, sub_d, sub_f} =
              if is_dir? do
                case build_tree(full_path, prefix <> child_prefix) do
                  {:ok, s_str, s_d, s_f} -> {s_str, s_d, s_f}
                  _ -> {"", 0, 0}
                end
              else
                {"", 0, 0}
              end

            # Add the raw increments (1 or 0) to the running accumulator
            {acc_str <> current_line <> sub_str, acc_d + d_inc + sub_d, acc_f + f_inc + sub_f}
          end)

        {:ok, String.trim_trailing(tree_str, "\n"), d_count, f_count}

      error ->
        error
    end
  end
end
