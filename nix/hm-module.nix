# Home-manager module for Pressay speech-to-text
#
# Provides a systemd user service for autostart.
# Usage: imports = [ pressay.homeManagerModules.default ];
#        services.pressay.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.pressay;
in
{
  options.services.pressay = {
    enable = lib.mkEnableOption "Pressay speech-to-text user service";

    package = lib.mkOption {
      type = lib.types.package;
      defaultText = lib.literalExpression "pressay.packages.\${system}.pressay";
      description = "The Pressay package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.pressay = {
      Unit = {
        Description = "Pressay speech-to-text";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package}/bin/pressay";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
