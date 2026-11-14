# The X250, a writing device (docs/PLAN.md phase 5.9, docs/DESIGN.md §4.12):
# it starts in a few seconds on the text, nothing but Charpentier on screen.
# The app drives the system through the tools these services bring (its
# System service, phase 5.4); the author never sees a desktop.
{
  config,
  lib,
  pkgs,
  charpentier,
  ...
}:
let
  cfg = config.charpentier;
  author = "auteur";

  # The keyboard chosen at installation: the console (and so the disk
  # password screen) and Sway use the same layout.
  layouts = {
    azerty = {
      console = "fr";
      xkb = "fr";
      variant = "";
    };
    bepo = {
      console = "fr-bepo";
      xkb = "fr";
      variant = "bepo";
    };
    qwerty = {
      console = "us";
      xkb = "us";
      variant = "";
    };
  };
  layout = layouts.${cfg.keyboard};

  # The app's test mode, in the development variant only (./dev.nix).
  testMode = lib.optionalString (
    cfg.testPort != null
  ) "export CHARPENTIER_TEST_PORT=${toString cfg.testPort}\n";

  # The app, started again if it ever stops; Wayland native.
  session = pkgs.writeShellScript "charpentier-session" ''
    export NIXOS_OZONE_WL=1
    ${testMode}while true; do
      ${lib.getExe charpentier} --appliance
      sleep 1
    done
  '';

  # A minimal Sway: no bar, no border, none of its own shortcuts. Super is the
  # app's system key, the X250's keys of light and sound reach the app.
  # One hidden combination opens a rescue terminal; it never starts with
  # Super, and the « locked » mode (the app's lock, phase 5.6) has none.
  swayConfig = pkgs.writeText "sway-charpentier.conf" ''
    default_border none
    default_floating_border none
    focus_follows_mouse no
    seat * hide_cursor 3000
    output * bg #14161a solid_color

    input type:keyboard {
      xkb_layout ${layout.xkb}
      ${lib.optionalString (layout.variant != "") "xkb_variant ${layout.variant}"}
    }
    input type:touchpad {
      tap enabled
      dwt enabled
    }

    for_window [app_id=".*"] fullscreen enable
    bindsym --to-code Ctrl+Alt+Shift+Return exec ${lib.getExe pkgs.foot}
    mode "locked" {
      bindsym --to-code Ctrl+Alt+Shift+Return nop
    }

    exec ${session}
  '';

  # Straight into Sway as the author, at start and whenever it ends.
  start = {
    user = author;
    command = "${lib.getExe pkgs.sway} --config ${swayConfig}";
  };
in
{
  # The disk's password screen.
  imports = [ ./plymouth ];

  options.charpentier.keyboard = lib.mkOption {
    type = lib.types.enum [
      "azerty"
      "bepo"
      "qwerty"
    ];
    default = "azerty";
    description = "The keyboard chosen at installation (docs/DESIGN.md §4.12 « Installation »).";
  };
  # The app's test mode (phase 5.10 bis): Chromium's debugging port, on
  # 127.0.0.1 only. Set by the development variant (./dev.nix), never by the
  # writing one.
  options.charpentier.testPort = lib.mkOption {
    type = lib.types.nullOr lib.types.port;
    default = null;
    description = "CHARPENTIER_TEST_PORT given to the app; null in the writing variant.";
  };

  config = {
    system.stateVersion = "26.05";
    networking.hostName = "x250";
    time.timeZone = lib.mkDefault "Europe/Paris";
    i18n.defaultLocale = "fr_FR.UTF-8";

    # ─── Starting: no menu, no text, the disk's password on a sober screen ───
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = 5;
    boot.loader.systemd-boot.editor = false;
    # No menu; the previous versions stay one key away (hold Space at start).
    boot.loader.timeout = 0;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.initrd.systemd.enable = true;
    boot.initrd.verbose = false;
    boot.consoleLogLevel = 0;
    boot.kernelParams = [
      "quiet"
      "loglevel=3"
      "rd.udev.log_level=3"
      "rd.systemd.show_status=false"
      "systemd.show_status=false"
      "vt.global_cursor_default=0"
    ];
    # The console, behind Plymouth (./plymouth draws the disk's password, D-25):
    # its keyboard is the one the password is typed on; its colours and font
    # are what is left if Plymouth ever fails, on #14161a, in fixed pitch.
    console = {
      earlySetup = true;
      keyMap = layout.console;
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

    # The disk, encrypted (D-25), found by the names the installer gives it.
    boot.initrd.luks.devices.racine = {
      device = "/dev/disk/by-partlabel/charpentier";
      allowDiscards = true;
    };
    fileSystems."/" = {
      device = "/dev/mapper/racine";
      fsType = "ext4";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/demarrage";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
    zramSwap.enable = true;

    # ─── The session: straight into Sway and the app ───
    users.users.${author} = {
      isNormalUser = true;
      description = "Auteur";
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "audio"
        "input"
        "lp"
      ];
    };
    # The rescue terminal may repair; the disk's encryption guards the device.
    security.sudo.wheelNeedsPassword = false;
    services.greetd = {
      enable = true;
      settings = {
        initial_session = start;
        default_session = start;
      };
    };
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = false;
      extraPackages = [ ];
    };
    security.polkit.enable = true;
    xdg.portal.enable = lib.mkForce false;

    # ─── What the app's System service drives (phase 5.4 to 5.7) ───
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    security.rtkit.enable = true;
    services.upower.enable = true;
    services.udisks2.enable = true;
    services.printing.enable = true;
    # Network printers without a driver (IPP Everywhere), found on the network.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };
    services.udev.packages = [ pkgs.brightnessctl ];
    environment.systemPackages = with pkgs; [
      brightnessctl
      wireplumber
      bluez
      cups
      pciutils
      util-linux
      swayidle
      wlsunset
      foot
      # Whether the Wi-Fi card can be an access point (5.13): `iw list`.
      iw
      charpentier
    ];
    # Without a password, for the author's session: the clock and the keys.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (subject.user == "${author}" && subject.local && subject.active &&
            (action.id.indexOf("org.freedesktop.timedate1.") == 0 ||
             action.id.indexOf("org.freedesktop.udisks2.") == 0 ||
             action.id.indexOf("org.freedesktop.login1.") == 0 ||
             action.id.indexOf("org.freedesktop.NetworkManager.") == 0)) {
          return polkit.Result.YES;
        }
      });
    '';

    # The first start from the phone (phase 5.13): the app opens a temporary
    # Wi-Fi (`nmcli device wifi hotspot`, NetworkManager's shared mode, its
    # dnsmasq on 10.42.0.0/24) and serves its page on 10.42.0.1:8080. Open on
    # the Wi-Fi only, to that network only: DHCP (whose first request comes
    # from 0.0.0.0), DNS, and the page. Nothing listens there afterwards.
    networking.firewall.extraCommands = ''
      iptables -A nixos-fw -i wl+ -p udp --dport 67 -j nixos-fw-accept
      iptables -A nixos-fw -i wl+ -s 10.42.0.0/24 -p udp --dport 53 -j nixos-fw-accept
      iptables -A nixos-fw -i wl+ -s 10.42.0.0/24 -p tcp --dport 53 -j nixos-fw-accept
      iptables -A nixos-fw -i wl+ -s 10.42.0.0/24 -p tcp --dport 8080 -j nixos-fw-accept
    '';

    # The batteries and the lid: TLP, sleep when the lid closes.
    services.tlp.enable = true;
    services.power-profiles-daemon.enable = false;
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandlePowerKey = "suspend";
    };

    # The keyboard chosen at installation, the app's default (its Clavier setting).
    environment.etc."charpentier/keyboard".text = cfg.keyboard;

    # ─── Nothing else ───
    documentation.enable = false;
    documentation.man.enable = false;
    services.xserver.enable = false;
    # NixOS brings speech-dispatcher and its voices (700 Mo); the app never speaks.
    services.speechd.enable = false;
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
