# Builds the demo-menu script that provides a TUI for launching demos
{ pkgs, demosPath }:
let
  runtimeDeps = builtins.attrValues {
    inherit (pkgs)
      gum
      jq
      coreutils
      bashInteractive
      ;
  };
in
pkgs.writeShellApplication {
  name = "demo-menu";

  runtimeInputs = runtimeDeps;

  text = ''
    DEMOS_DIR="${demosPath}"

    # Collect demo directories that have a demo.json
    demos=()
    descriptions=()

    for dir in "$DEMOS_DIR"/*/; do
      meta="$dir/demo.json"
      if [ -f "$meta" ]; then
        name="$(basename "$dir")"
        if ! desc="$(jq -er '.description | strings' "$meta" 2>/dev/null)"; then
          continue
        fi
        demos+=("$name")
        descriptions+=("$name — $desc")
      fi
    done

    if [ "''${#demos[@]}" -eq 0 ]; then
      echo "No demos found in $DEMOS_DIR"
      exit 1
    fi

    echo "Select a demo to run:"
    echo ""

    if ! choice="$(printf '%s\n' "''${descriptions[@]}" | gum choose)"; then
      echo "No demo selected."
      exit 0
    fi

    if [ -z "$choice" ]; then
      echo "No demo selected."
      exit 0
    fi

    # Extract the demo name (everything before " — ")
    selected="''${choice%% — *}"

    meta="$DEMOS_DIR/$selected/demo.json"
    if ! run_cmd="$(jq -er '.run | strings' "$meta" 2>/dev/null)"; then
      echo "Demo metadata is missing a runnable command: $selected" >&2
      exit 1
    fi

    echo ""
    echo "Launching: $selected"
    echo "Command:   $run_cmd"
    echo ""

    cd "$DEMOS_DIR/$selected"
    exec bash -c "$run_cmd"
  '';
}
