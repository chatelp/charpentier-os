# The X250's updates (docs/PLAN.md phase 5.12): every hour, network present,
# the version published on the sync server (the writing system's releases on
# /api/updates/latest; the development variant's own channel, /api/updates/dev,
# D-42, phase 5.12 bis), downloaded from its cache only,
# signed by the key laid here at installation (../cache-key.pub), installed
# as the next start's generation; never a restart. The app reads
# /run/charpentier/update.json and may ask only three things (polkit below).
# The contract: README, « Mises à jour ». The script: ./update.sh.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  update = import ./package.nix {
    inherit pkgs;
    nix = config.nix.package;
  };
  key = ../cache-key.pub;
  env = {
    CHARPENTIER_UPDATE_KEY = "${key}";
  };
  plymouth = config.boot.plymouth.package;
  # In the initrd: a generation's first start after an update carries
  # charpentier.maj=X.Y.Z on its kernel line; Plymouth shows it above the
  # disk's password (./../plymouth/charpentier.script). Plymouth drops a
  # status sent before its screen exists (which may be as late as the
  # password's question): sent again every half second, for 30 s.
  majToPlymouth = pkgs.writeShellScript "charpentier-maj" ''
    read -r line </proc/cmdline
    for word in $line; do
      case "$word" in
        charpentier.maj=*)
          for _ in $(${pkgs.coreutils}/bin/seq 60); do
            ${plymouth}/bin/plymouth update --status="maj:''${word#charpentier.maj=}" || true
            ${pkgs.coreutils}/bin/sleep 0.5
          done
          ;;
      esac
    done
  '';
in
{
  # The cache's key, also for Nix itself.
  nix.settings.trusted-public-keys = [ (lib.fileContents key) ];

  systemd.services.charpentier-update-state = {
    description = "Charpentier : la version qui a démarré";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    environment = env;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe update} state";
    };
  };

  systemd.services.charpentier-update-check = {
    description = "Charpentier : vérifier les mises à jour";
    after = [
      "network-online.target"
      "charpentier-update-state.service"
    ];
    wants = [ "network-online.target" ];
    environment = env;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe update} check";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.charpentier-update-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      RandomizedDelaySec = "5min";
    };
  };

  # A generation's first start: if the app never comes up (Sway does not
  # start…), back to the previous one (./update.sh watch). In the
  # background: the start is never held back by it.
  systemd.services.charpentier-update-watch = {
    description = "Charpentier : premier démarrage d'une version, retour à la précédente si l'écran reste noir";
    wantedBy = [ "multi-user.target" ];
    after = [ "charpentier-update-state.service" ];
    requires = [ "charpentier-update-state.service" ];
    environment = env;
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe update} watch";
    };
  };

  # The store, cleaned every day: the generations no one needs any more go
  # (./update.sh clean), the one running and the previous one stay.
  systemd.services.charpentier-update-clean = {
    description = "Charpentier : les anciennes versions retirées du disque";
    after = [ "charpentier-update-state.service" ];
    environment = env;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe update} clean";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  # By the calendar, not from the start: a timer started by a switch (an
  # update by update-x250.sh) whose OnBootSec had passed fired at once, in
  # the middle of that switch (the X250, 20 November 2026). Missed while the
  # X250 was off or asleep: at the next start, or on waking.
  systemd.timers.charpentier-update-clean = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  systemd.services."charpentier-update-boot@" = {
    description = "Charpentier : démarrer la prochaine fois sur la génération %i";
    after = [ "charpentier-update-state.service" ];
    environment = env;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe update} boot %i";
    };
  };

  # The app's three gestures, for the author's session only: check now, and
  # the next start on the previous (or set aside) generation. The reboot is
  # logind's, already allowed.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "auteur" && subject.local && subject.active &&
          action.lookup("verb") == "start") {
        var unit = action.lookup("unit");
        if (unit == "charpentier-update-check.service" ||
            /^charpentier-update-boot@[0-9]+\.service$/.test(unit)) {
          return polkit.Result.YES;
        }
      }
    });
  '';

  boot.initrd.systemd.services.charpentier-maj = {
    description = "Charpentier : la mise à jour, sur l'écran du disque";
    wantedBy = [ "cryptsetup.target" ];
    # Plymouth first, in the same transaction (After= alone let it run before);
    # in the background, never holding the password back; gone at switch-root.
    wants = [ "plymouth-start.service" ];
    after = [ "plymouth-start.service" ];
    conflicts = [ "initrd-switch-root.target" ];
    before = [ "initrd-switch-root.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "simple";
      ExecStart = "${majToPlymouth}";
    };
  };
  boot.initrd.systemd.storePaths = [ majToPlymouth ];
}
