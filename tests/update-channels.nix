# The update service's two channels (D-42, phase 5.12 bis), in virtual
# machines against a fake server (scripts/update-api.py):
#   nix build .#checks.x86_64-linux.update-channels -L
# A writing system reads /api/updates/latest only and takes writing systems
# only; the development variant reads /api/updates/dev only, takes
# development systems only, and never one published before its newest
# system (the latest wins). The systems offered are stand-ins (a
# switch-to-configuration that only says it was called), signed by a key of
# the test's own; the service itself is the X250's (hosts/x250/update).
{ pkgs, lib }:
let
  # A system the service may take: its keyboard, its variant (none: writing).
  standIn =
    name: variant:
    pkgs.runCommand "nixos-system-${name}" { } ''
      mkdir -p $out/bin $out/etc/charpentier
      echo azerty >$out/etc/charpentier/keyboard
      ${lib.optionalString (variant != null) "echo ${variant} >$out/etc/charpentier/variant"}
      cat >$out/bin/switch-to-configuration <<EOF
      #!${pkgs.runtimeShell}
      echo "$out \$1" >>/tmp/switched
      EOF
      chmod +x $out/bin/switch-to-configuration
    '';
  writing = standIn "x250-essai-ecriture" null;
  dev = standIn "x250-essai-dev" "developpement";
  dev2 = standIn "x250-essai-dev-2" "developpement";
  dev3 = standIn "x250-essai-dev-3" "developpement";
  update = import ../hosts/x250/update/package.nix {
    inherit pkgs;
    inherit (pkgs) nix;
  };
  x250 =
    variant:
    { ... }:
    {
      environment.etc."charpentier/keyboard".text = "azerty";
      environment.etc."charpentier/variant" = lib.mkIf (variant != null) { text = variant; };
      environment.systemPackages = [ update ];
    };
in
pkgs.testers.runNixOSTest {
  name = "charpentier-update-channels";
  nodes = {
    server =
      { ... }:
      {
        # The stand-ins in its store, for `nix copy` into the cache.
        system.extraDependencies = [
          writing
          dev
          dev2
          dev3
        ];
        nix.settings.experimental-features = [ "nix-command" ];
        networking.firewall.allowedTCPPorts = [ 80 ];
        systemd.services.update-api = {
          wantedBy = [ "multi-user.target" ];
          preStart = "mkdir -p /srv/api /srv/cache";
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${../scripts/update-api.py} /srv 80";
        };
      };
    ecriture = x250 null;
    dev = x250 "developpement";
  };
  testScript = ''
    import json

    writing, dev_system, dev_system_2, dev_system_3 = "${writing}", "${dev}", "${dev2}", "${dev3}"

    def point(channel, version, path, published="2026-11-18T12:00:00Z"):
        body = json.dumps({"version": version, "notes": "- essai", "systems": {"azerty": path},
                           "publishedAt": published})
        server.succeed(f"echo '{body}' >/srv/api/{channel}.json")

    def check(machine):
        server.succeed(": >/srv/requests.log")
        machine.succeed(
            "CHARPENTIER_UPDATE_KEY=/etc/test-cache.pub CHARPENTIER_UPDATE_ACCESS=/root/access.json "
            "charpentier-update check"
        )
        asked = server.succeed("grep ' /api/' /srv/requests.log | cut -d' ' -f3").split()
        return json.loads(machine.succeed("cat /run/charpentier/update.json")), asked

    start_all()
    server.wait_for_open_port(80)
    server.succeed(
        "nix-store --generate-binary-cache-key essai-1 /srv/key.sec /srv/key.pub",
        f"nix copy --to 'file:///srv/cache?secret-key=/srv/key.sec' {writing} {dev_system} {dev_system_2} {dev_system_3}",
    )
    key = server.succeed("cat /srv/key.pub").strip()
    for m in (ecriture, dev):
        m.wait_for_unit("multi-user.target")
        m.succeed(
            f"echo '{key}' >/etc/test-cache.pub",
            """echo '{"server": "http://server", "token": "essai"}' >/root/access.json""",
        )

    with subtest("a writing system refuses a development version, by its number or its system"):
        point("latest", "0.2.0-dev.1", writing)
        state, asked = check(ecriture)
        assert asked == ["/api/updates/latest"], asked
        assert state["development"] is False and state["ready"] is None, state
        assert state["failure"]["reason"] == "unreadable", state
        point("latest", "0.2.1", dev_system)
        state, _ = check(ecriture)
        assert state["ready"] is None and state["failure"]["reason"] == "unreadable", state
        ecriture.fail("grep -q ${dev} /tmp/switched")

    with subtest("the development variant refuses a writing version, by its number or its system"):
        point("dev", "0.2.1", dev_system)
        state, asked = check(dev)
        assert asked == ["/api/updates/dev"], asked
        assert state["development"] is True and state["ready"] is None, state
        assert state["failure"]["reason"] == "unreadable", state
        point("dev", "0.2.0-dev.2", writing)
        state, _ = check(dev)
        assert state["ready"] is None and state["failure"]["reason"] == "unreadable", state
        dev.fail("grep -q ${writing} /tmp/switched")

    with subtest("each takes its own channel's version, and never reads the other's"):
        point("latest", "0.2.0", writing)
        point("dev", "0.2.0-dev.3", dev_system, "2000-06-01T00:00:00Z")
        state, asked = check(ecriture)
        assert asked == ["/api/updates/latest"], asked
        assert state["ready"]["version"] == "0.2.0" and state["failure"] is None, state
        ecriture.succeed("grep -qx '${writing} boot' /tmp/switched")
        state, asked = check(dev)
        assert asked == ["/api/updates/dev"], asked
        assert state["ready"]["version"] == "0.2.0-dev.3" and state["failure"] is None, state
        dev.succeed("grep -qx '${dev} boot' /tmp/switched")

    with subtest("the development variant: the latest wins"):
        # Its newest system, 0.2.0-dev.3, came from the pointer: its date is
        # its publication's (June 2000), not the day it was made here.
        before = dev.succeed("cat /tmp/switched")
        point("dev", "0.2.0-dev.4", dev_system_2, "2000-01-01T00:00:00Z")
        state, _ = check(dev)
        assert state["ready"]["version"] == "0.2.0-dev.3" and state["failure"] is None, state
        assert dev.succeed("cat /tmp/switched") == before
        dev.fail("nix-store --check-validity ${dev2}")
        # Published after it, though before it was made here (a publication
        # while the previous one downloaded): newer, taken.
        point("dev", "0.2.0-dev.4", dev_system_2, "2001-01-01T00:00:00Z")
        state, _ = check(dev)
        assert state["ready"]["version"] == "0.2.0-dev.4", state
        dev.succeed("grep -qx '${dev2} boot' /tmp/switched")
        # An update by update-x250.sh: a newer system, not from the pointer;
        # its date is its making's. An older publication is not taken.
        dev.succeed("nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/current-system)")
        point("dev", "0.2.0-dev.5", dev_system_3, "2002-01-01T00:00:00Z")
        state, _ = check(dev)
        assert state["ready"] is None and state["failure"] is None, state
        dev.fail("nix-store --check-validity ${dev3}")
        # One published after it is.
        point("dev", "0.2.0-dev.5", dev_system_3, "2099-01-01T00:00:00Z")
        state, _ = check(dev)
        assert state["ready"]["version"] == "0.2.0-dev.5", state
        dev.succeed("grep -qx '${dev3} boot' /tmp/switched")

    with subtest("nothing on /dev: the development variant finds nothing, and installs nothing"):
        server.succeed("rm /srv/api/dev.json")
        before = dev.succeed("cat /tmp/switched")
        state, asked = check(dev)
        assert asked == ["/api/updates/dev"], asked
        assert dev.succeed("cat /tmp/switched") == before
  '';
}
