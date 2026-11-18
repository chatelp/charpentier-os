# The X250's development variant (docs/PLAN.md phase 5.10 bis): the writing
# system, plus what the build machine needs to update it (5.10), reinstall it
# from zero (nixos-anywhere) and run the app's device tests against it.
# It never reaches a normal X250: it has its own update channel (D-42, phase
# 5.12 bis: /api/updates/dev, published by scripts/publish-dev.sh, never with
# the releases), and its marker, /etc/charpentier/variant, is refused by the
# update service of a writing system (5.12), which reads the releases only.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.charpentier.dev;
  # The home network only: private IPv4 ranges, IPv6 link-local and ULA.
  # No Tailscale: nothing reaches the X250 from outside the house.
  lan4 = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
  ];
  lan6 = [
    "fe80::/10"
    "fd00::/8"
  ];
in
{
  options.charpentier.dev.authorizedKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "SSH public keys allowed in, as the author (the build machine's).";
  };

  config = {
    assertions = [
      {
        assertion = cfg.authorizedKeys != [ ];
        message = "the development variant needs at least one SSH key (charpentier.dev.authorizedKeys)";
      }
    ];

    environment.etc."charpentier/variant".text = "developpement";
    system.nixos.tags = [ "developpement" ];

    # The app's test mode: Chromium's debugging port, reached through SSH only.
    charpentier.testPort = 9222;

    # SSH by key only, as the author (sudo without a password, as the rescue
    # terminal already has); never as root, never by password.
    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [ "auteur" ];
        AllowTcpForwarding = "local";
      };
    };
    users.users.auteur.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    # Port 22 open to the home network only.
    networking.firewall.extraCommands =
      lib.concatMapStrings (n: "iptables -A nixos-fw -p tcp --dport 22 -s ${n} -j nixos-fw-accept\n") lan4
      + lib.concatMapStrings (
        n: "ip6tables -A nixos-fw -p tcp --dport 22 -s ${n} -j nixos-fw-accept\n"
      ) lan6;
    # Reachable from the build machine: no sleep when idle (the app's
    # swayidle would suspend it after 15 minutes, out of SSH's reach). The
    # lid still suspends (logind's LidSwitchIgnoreInhibited, on by default),
    # and a test sleeps on purpose with `systemctl suspend --ignore-inhibitors`.
    systemd.services.charpentier-dev-awake = {
      description = "Version développement : joignable par SSH, pas de veille sur inactivité";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=sleep:idle --who=charpentier-dev --why=ssh --mode=block ${pkgs.coreutils}/bin/sleep infinity";
    };

    # Kept awake, it would empty its batteries until it dies: on battery, at
    # 10 % or less, it goes to sleep all the same (./dev-low-battery.sh).
    systemd.services.charpentier-dev-low-battery = {
      description = "Version développement : veille sur batterie à 10 %";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "charpentier-dev-low-battery";
            runtimeInputs = [
              pkgs.coreutils
              config.systemd.package
            ];
            text = builtins.readFile ./dev-low-battery.sh;
          }
        );
      };
    };
    systemd.timers.charpentier-dev-low-battery = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1min";
        AccuracySec = "10s";
      };
    };

    # nixos-rebuild --target-host sends the system as the author.
    nix.settings.trusted-users = [ "auteur" ];
  };
}
