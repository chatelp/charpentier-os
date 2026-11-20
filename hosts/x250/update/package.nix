# The update service's script (./update.sh), with what it calls: for the
# X250 (./default.nix) and for its test in virtual machines
# (tests/update-channels.nix).
{ pkgs, nix }:
pkgs.writeShellApplication {
  name = "charpentier-update";
  runtimeInputs = with pkgs; [
    coreutils
    curl
    gnused
    gnugrep
    jq
    util-linux # flock
    procps # pgrep, ps: the app's process, at a first start
    nix
  ];
  text = builtins.readFile ./update.sh;
  # shellcheck runs in the build; jq's programs are in single quotes on purpose.
  excludeShellChecks = [ "SC2016" ];
}
