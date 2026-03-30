# Builds the demo-menu script that provides a TUI for launching demos
{ pkgs, demosPath }:
let
  runtimeDeps = builtins.attrValues {
    inherit (pkgs) gum jq coreutils bashInteractive;
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
        desc="$(jq -r '.description' "$meta")"
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

    choice="$(printf '%s\n' "''${descriptions[@]}" | gum choose)"

    if [ -z "$choice" ]; then
      echo "No demo selected."
      exit 0
    fi

    # Extract the demo name (everything before " — ")
    selected="''${choice%% — *}"

    meta="$DEMOS_DIR/$selected/demo.json"
    run_cmd="$(jq -r '.run' "$meta")"

    echo ""
    echo "Launching: $selected"
    echo "Command:   $run_cmd"
    echo ""

    cd "$DEMOS_DIR/$selected"
    exec bash -c "$run_cmd"
  '';
}
