# The update service's two channels (D-42, phase 5.12 bis), in virtual
# machines against a fake server (scripts/update-api.py):
#   nix build .#checks.x86_64-linux.update-channels -L
# A writing system reads /api/updates/latest only and takes writing systems
# only; the development variant reads /api/updates/dev only and takes
# development systems only. The systems offered are stand-ins (a
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

    writing, dev_system = "${writing}", "${dev}"

    def point(channel, version, path):
        body = json.dumps({"version": version, "notes": "- essai", "systems": {"azerty": path},
                           "publishedAt": "2026-11-18T12:00:00Z"})
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
        f"nix copy --to 'file:///srv/cache?secret-key=/srv/key.sec' {writing} {dev_system}",
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
        point("dev", "0.2.0-dev.3", dev_system)
        state, asked = check(ecriture)
        assert asked == ["/api/updates/latest"], asked
        assert state["ready"]["version"] == "0.2.0" and state["failure"] is None, state
        ecriture.succeed("grep -qx '${writing} boot' /tmp/switched")
        state, asked = check(dev)
        assert asked == ["/api/updates/dev"], asked
        assert state["ready"]["version"] == "0.2.0-dev.3" and state["failure"] is None, state
        dev.succeed("grep -qx '${dev} boot' /tmp/switched")

    with subtest("nothing on /dev: the development variant finds nothing, and installs nothing"):
        server.succeed("rm /srv/api/dev.json")
        before = dev.succeed("cat /tmp/switched")
        state, asked = check(dev)
        assert asked == ["/api/updates/dev"], asked
        assert dev.succeed("cat /tmp/switched") == before
  '';
}
