# The update service's generations (the outside review of 18 November 2026),
# in a virtual machine: nix build .#checks.x86_64-linux.update-generations -L
#   clean: the store loses the generations no one needs; the running one,
#     the previous one, the one ready and the newest stay;
#   watch: a generation's first start whose app never comes up goes back to
#     the previous one, the new one set aside; one whose app comes up, or
#     already started once, is left alone.
# The generations are stand-ins (a switch-to-configuration that only says it
# was called) around the machine's own system, the one that runs; the app is
# a process of the author's carrying --appliance, as the X250's does.
{ pkgs, lib }:
let
  standIn =
    name:
    pkgs.runCommand "nixos-system-${name}" { } ''
      mkdir -p $out/bin
      cat >$out/bin/switch-to-configuration <<EOF
      #!${pkgs.runtimeShell}
      echo "$out \$1" >>/tmp/switched
      EOF
      chmod +x $out/bin/switch-to-configuration
    '';
  previous = standIn "x250-essai-precedente";
  next = standIn "x250-essai-suivante";
  update = import ../hosts/x250/update/package.nix {
    inherit pkgs;
    inherit (pkgs) nix;
  };
in
pkgs.testers.runNixOSTest {
  name = "charpentier-update-generations";
  nodes.x250 =
    { ... }:
    {
      environment.etc."charpentier/keyboard".text = "azerty";
      environment.systemPackages = [
        update
        pkgs.jq
      ];
      system.extraDependencies = [
        previous
        next
      ];
      users.users.auteur.isNormalUser = true;
    };
  testScript = ''
    import json

    profile = "/nix/var/nix/profiles/system"
    env = "CHARPENTIER_UPDATE_KEY=/etc/charpentier/keyboard "

    def run(command, extra=""):
        return x250.succeed(env + extra + "charpentier-update " + command + " 2>&1")

    def gens():
        out = x250.succeed(f"ls -d {profile}-*-link | sed -E 's/.*system-([0-9]+)-link/\\1/' | sort -n")
        return [int(g) for g in out.split()]

    def db():
        return json.loads(x250.succeed("cat /var/lib/charpentier/update/generations.json"))

    def saved():
        return json.loads(x250.succeed("cat /var/lib/charpentier/update/state.json"))

    def edit(file, program):
        x250.succeed(f"jq '{program}' {file} >/tmp/edit && mv /tmp/edit {file}")

    def junk(n):
        x250.succeed(f"mkdir -p /tmp/junk-{n} && echo {n} >/tmp/junk-{n}/n")
        return x250.succeed(f"nix-store --add /tmp/junk-{n}").strip()

    x250.wait_for_unit("multi-user.target")
    # 1, 2: old ones; 3: the previous one; 4: the one that runs; 5: an old
    # one above it; 6: the next start's, ready.
    old = [junk(1), junk(2)]
    for path in old:
        x250.succeed(f"nix-env -p {profile} --set {path}")
    x250.succeed(f"nix-env -p {profile} --set ${previous}")
    x250.succeed(f"nix-env -p {profile} --set $(readlink -f /run/booted-system)")
    old.append(junk(5))
    x250.succeed(f"nix-env -p {profile} --set {old[2]}")
    x250.succeed(f"nix-env -p {profile} --set ${next}")
    assert gens() == [1, 2, 3, 4, 5, 6], gens()
    run("state")

    with subtest("a generation's first start is watched, once"):
        assert db()["4"]["watch"] is True and db()["4"]["installedAt"], db()
        run("state")
        assert db()["4"]["watch"] is True, db()

    with subtest("its app comes up: the start is good, never watched again"):
        # A shell named as the app (sleep, a multi-call program, would not run
        # under another name), kept alive past its sleep.
        x250.succeed("systemd-run --uid=auteur --unit=app -- ${pkgs.bash}/bin/bash -c "
                     "'exec -a \"electron --appliance\" ${pkgs.bash}/bin/bash -c \"${pkgs.coreutils}/bin/sleep 600; :\"'")
        x250.wait_until_succeeds("pgrep -u auteur -f -- ' --appliance'", timeout=10)
        out = run("watch", "CHARPENTIER_WATCH_WAIT=60 CHARPENTIER_WATCH_STEADY=3 CHARPENTIER_REBOOT='touch /tmp/rebooted' ")
        assert "l'app a démarré" in out, out
        x250.fail("test -e /tmp/rebooted")
        assert "watch" not in db()["4"], db()
        run("state")
        assert "watch" not in db()["4"], db()

    with subtest("a generation not watched: nothing, even without its app"):
        x250.succeed("systemctl stop app")
        run("watch", "CHARPENTIER_WATCH_WAIT=10 CHARPENTIER_WATCH_STEADY=3 CHARPENTIER_REBOOT='touch /tmp/rebooted' ")
        x250.fail("test -e /tmp/rebooted")
        assert x250.succeed(f"readlink {profile}").strip() == "system-6-link"

    with subtest("the store, cleaned: the running, previous, ready and newest stay"):
        edit("/var/lib/charpentier/update/generations.json",
             '.["1"] = {version: "0.0.1"} | .["6"] = {version: "0.3.0"}')
        edit("/var/lib/charpentier/update/state.json", ".ready = 6")
        x250.succeed("mkdir -p /boot/loader/entries",
                     "echo 'options init=/essai' >/boot/loader/entries/nixos-generation-6.conf")
        run("clean")
        assert gens() == [3, 4, 6], gens()
        for path in old:
            x250.fail(f"nix-store --check-validity {path}")
        assert "1" not in db() and db()["6"]["version"] == "0.3.0", db()
        x250.succeed("grep -qx '${next} boot' /tmp/switched")
        x250.succeed("grep -q 'charpentier.maj=0.3.0' /boot/loader/entries/nixos-generation-6.conf")
        assert x250.succeed(f"readlink {profile}").strip() == "system-6-link"
        state = json.loads(x250.succeed("cat /run/charpentier/update.json"))
        assert state["ready"]["generation"] == 6 and state["previous"]["generation"] == 3, state

    with subtest("a first start whose app never comes up: back to the previous one"):
        edit("/var/lib/charpentier/update/generations.json", '.["4"].watch = true')
        out = run("watch", "CHARPENTIER_WATCH_WAIT=10 CHARPENTIER_WATCH_STEADY=3 CHARPENTIER_REBOOT='touch /tmp/rebooted' ")
        assert "retour à la génération 3" in out, out
        x250.succeed("test -e /tmp/rebooted")
        x250.succeed("grep -qx '${previous} boot' /tmp/switched")
        assert x250.succeed(f"readlink {profile}").strip() == "system-3-link"
        assert saved()["setAside"] == 4 and saved()["failure"]["reason"] == "start", saved()
        assert "watch" not in db()["4"], db()
  '';
}
