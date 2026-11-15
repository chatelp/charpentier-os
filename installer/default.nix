# The X250's install key (docs/PLAN.md phase 5.9 bis, docs/DESIGN.md §4.12
# « Installation »): a minimal NixOS loaded in memory (the key may be pulled
# at the end), the X250's system already built for each keyboard, and the
# installer on the first console, in kmscon; on the kernel's console if
# kmscon fails. No menu, no kernel text. What the key and the network add:
# ./iso.nix and ./netboot.nix.
{
  config,
  lib,
  pkgs,
  modulesPath,
  systems,
  version,
  ...
}:
let
  label = "CHARPENTIER";
  # The system material (§3.1): background, ink, ink 2, faint.
  rgb = {
    bg = "20,22,26";
    ink = "223,227,234";
    ink2 = "185,192,202";
    faint = "85,91,102";
  };
  installer = pkgs.writeShellApplication {
    name = "charpentier-installer";
    runtimeInputs = with pkgs; [
      cryptsetup
      gptfdisk
      dosfstools
      e2fsprogs
      parted
      util-linux
      kbd
      ncurses
      gawk
      gnugrep
      gnused
      findutils
      coreutils
      systemd
      nix
      config.system.build.nixos-install
    ];
    bashOptions = [ ];
    # The author reads French: its apostrophe (’) is typographic, on purpose.
    excludeShellChecks = [ "SC1112" ];
    # kmscon starts the installer with an empty environment: what it needs is
    # written ahead of it, the system's tools as a last resort, and a UTF-8
    # locale (accents counted as one character, typed as one key).
    text =
      lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") env)
      + "export PATH=\"$PATH:/run/current-system/sw/bin\" LANG=C.UTF-8\n"
      + builtins.readFile ./install.sh;
  };
  env = {
    CHARPENTIER_VERSION = version;
    CHARPENTIER_KEY_LABEL = label;
    CHARPENTIER_NETBOOT = if config.charpentier.installer.netboot then "1" else "0";
    CHARPENTIER_SYSTEMS = lib.concatStringsSep "," (lib.mapAttrsToList (k: s: "${k}=${s}") systems);
  };
  # kmscon takes its keyboard when it starts: the installer restarts the
  # service when the author changes it.
  kmscon = pkgs.writeShellScript "charpentier-kmscon" ''
    layout=$(cat /run/charpentier/layout 2>/dev/null || echo azerty)
    case $layout in
      qwerty) xkb="--xkb-layout=us" ;;
      *) xkb="--xkb-layout=fr" ;;
    esac
    exec ${pkgs.kmscon}/bin/kmscon --vt=1 --no-switchvt --hwaccel \
      --font-name="JetBrains Mono" --font-size=12 \
      --palette=custom \
      --palette-background=${rgb.bg} --palette-foreground=${rgb.ink} \
      --palette-black=${rgb.bg} --palette-white=${rgb.ink} \
      --palette-light-grey=${rgb.ink2} --palette-dark-grey=${rgb.faint} \
      $xkb --login -- ${lib.getExe installer}
  '';
in
{
  options.charpentier.installer.netboot = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Started from the network (./netboot.nix), not from the key (./iso.nix).";
  };

  config = {
    # Quiet, straight on.
    boot.kernelParams = [
      "quiet"
      "loglevel=3"
      "rd.udev.log_level=3"
      "systemd.show_status=false"
      "vt.global_cursor_default=0"
    ];
    boot.consoleLogLevel = 0;
    boot.initrd.verbose = false;
    boot.loader.timeout = lib.mkForce 0;

    # The fallback: the kernel's console, Terminus, the same palette.
    console = {
      earlySetup = true;
      packages = [ pkgs.terminus_font ];
      font = "ter-v24n";
      colors = [
        "14161a"
        "c45a3c"
        "8fae86"
        "d6b46a"
        "86aedb"
        "b48ead"
        "88c0d0"
        "b9c0ca"
        "555b66"
        "c45a3c"
        "8fae86"
        "d6b46a"
        "86aedb"
        "b48ead"
        "88c0d0"
        "dfe3ea"
      ];
    };
    fonts.packages = [ pkgs.jetbrains-mono ];
    fonts.fontconfig.enable = true;

    # No login on the first console: the installer is there.
    services.getty.autologinUser = lib.mkForce null;
    services.getty.helpLine = lib.mkForce "";
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;

    systemd.services.charpentier-installer = {
      description = "Installation de Charpentier";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-udev-settle.service"
        "systemd-vconsole-setup.service"
      ];
      onFailure = [ "charpentier-installer-plain.service" ];
      serviceConfig = {
        ExecStart = kmscon;
        Restart = "on-failure";
        RestartSec = 0;
      };
      unitConfig.StartLimitBurst = 50;
    };

    systemd.services.charpentier-installer-plain = {
      description = "Installation de Charpentier (console du noyau)";
      environment.CHARPENTIER_PLAIN = "1";
      serviceConfig = {
        ExecStart = lib.getExe installer;
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        Restart = "always";
      };
    };

    environment.systemPackages = [ installer ];
    networking.hostName = "charpentier-installation";
    # The installer formats ext4 only: no ZFS on the key.
    boot.supportedFilesystems.zfs = lib.mkForce false;
    networking.wireless.enable = lib.mkForce false;
    networking.networkmanager.enable = lib.mkForce false;
    documentation.enable = lib.mkForce false;
    system.stateVersion = "26.05";
  };
}
