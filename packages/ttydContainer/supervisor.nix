# Main entrypoint: serves a shared zellij session through ttyd
{ pkgs }:
let
  # zellij reads this through ZELLIJ_CONFIG_DIR (set in the image environment)
  zellijConfig = pkgs.writeTextDir "etc/zellij/config.kdl" ''
    // Mouse capture breaks text selection and copy in the browser terminal
    mouse_mode false
  '';
in
{
  inherit zellijConfig;

  supervisor = pkgs.writeShellApplication {
    name = "webshell-supervisor";

    runtimeInputs = [
      pkgs.ttyd
      pkgs.zellij
    ];

    text = ''
      SESSION="''${ZELLIJ_SESSION:-main}"
      PORT="''${TTYD_PORT:-8000}"

      # Each browser connection attaches to the same session, which is created on demand
      exec ttyd --port="$PORT" --writable zellij attach --create "$SESSION"
    '';
  };
}
