#!/usr/bin/env bash

# Prevent multiple watchers from stacking
pid_file="/tmp/tmux_mode_watcher_$(tmux display-message -p '#{socket_path}' 2>/dev/null | tr '/' '_').pid"

if [ -f "$pid_file" ]; then
    old_pid=$(cat "$pid_file" 2>/dev/null)
    if kill -0 "$old_pid" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$pid_file"
trap 'rm -f "$pid_file"' EXIT

# Read current values from tmux options
read_opts() {
    tmux show-option -gqv "$1"
}

prefix_prompt=$(read_opts "@mode_indicator_prefix_prompt")
copy_prompt=$(read_opts "@mode_indicator_copy_prompt")
sync_prompt=$(read_opts "@mode_indicator_sync_prompt")
empty_prompt=$(read_opts "@mode_indicator_empty_prompt")

prefix_style=$(read_opts "@mode_indicator_prefix_mode_style")
copy_style=$(read_opts "@mode_indicator_copy_mode_style")
sync_style=$(read_opts "@mode_indicator_sync_mode_style")
empty_style=$(read_opts "@mode_indicator_empty_mode_style")

# Default fallbacks if options are not set
prefix_prompt="${prefix_prompt:- WAIT }"
copy_prompt="${copy_prompt:- COPY }"
sync_prompt="${sync_prompt:- SYNC }"
empty_prompt="${empty_prompt:- TMUX }"

prefix_style="${prefix_style:-bg=blue,fg=black}"
copy_style="${copy_style:-bg=yellow,fg=black}"
sync_style="${sync_style:-bg=red,fg=black}"
empty_style="${empty_style:-bg=cyan,fg=black}"

# Processed styles (#[bg=blue]#[fg=black])
style_prefix="#[${prefix_style//,/]#[}]"
style_copy="#[${copy_style//,/]#[}]"
style_sync="#[${sync_style//,/]#[}]"
style_empty="#[${empty_style//,/]#[}]"

while true; do
    tmux list-sessions -F '#{session_id}' 2>/dev/null | while IFS= read -r session_id; do
        client_prefix=$(tmux display-message -p -t "$session_id" '#{?client_prefix,1,0}' 2>/dev/null)
        pane_in_mode=$(tmux display-message -p -t "$session_id" '#{?pane_in_mode,1,0}' 2>/dev/null)
        pane_synchronized=$(tmux display-message -p -t "$session_id" '#{?pane_synchronized,1,0}' 2>/dev/null)

        if [ "$client_prefix" = "1" ]; then
            mode="prefix"
            prompt="$prefix_prompt"
            style="$style_prefix"
        elif [ "$pane_in_mode" = "1" ]; then
            mode="copy"
            prompt="$copy_prompt"
            style="$style_copy"
        elif [ "$pane_synchronized" = "1" ]; then
            mode="sync"
            prompt="$sync_prompt"
            style="$style_sync"
        else
            mode="empty"
            prompt="$empty_prompt"
            style="$style_empty"
        fi

        env_var="tmux_mode_${session_id}"

        # Check if already correct to avoid needless refresh
        current_val=$(tmux show-environment -t "$session_id" "$env_var" 2>/dev/null | sed 's/^[^=]*=//')
        if [ "$current_val" != "$mode" ]; then
            tmux set-environment -t "$session_id" "$env_var" "$mode" 2>/dev/null

            # Refresh all clients attached to this session so the update is immediate
            tmux list-clients -t "$session_id" -F '#{client_name}' 2>/dev/null | while IFS= read -r client_name; do
                tmux refresh-client -S -t "$client_name" 2>/dev/null || true
            done
        fi
    done

    sleep 0.2
done

