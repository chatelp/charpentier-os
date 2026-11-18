# The development variant's sleep on battery at 10 % (hosts/x250/dev-low-battery.sh),
# against stand-in power supplies: nix build .#checks.x86_64-linux.dev-low-battery
{ pkgs }:
let
  low = pkgs.writeShellApplication {
    name = "charpentier-dev-low-battery";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../hosts/x250/dev-low-battery.sh;
  };
in
pkgs.runCommand "charpentier-dev-low-battery-test" { } ''
  # case <name> <mains online|none> <BAT0 now full> <BAT1 now full|-> <expected: sleep|awake>
  case_() {
    local name=$1 ac=$2 n0=$3 f0=$4 n1=$5 f1=$6 want=$7 p
    p=$(mktemp -d)
    if [ "$ac" != none ]; then mkdir $p/AC; echo Mains >$p/AC/type; echo $ac >$p/AC/online; fi
    if [ "$n0" != - ]; then mkdir $p/BAT0; echo Battery >$p/BAT0/type; echo $n0 >$p/BAT0/energy_now; echo $f0 >$p/BAT0/energy_full; fi
    if [ "$n1" != - ]; then mkdir $p/BAT1; echo Battery >$p/BAT1/type; echo $n1 >$p/BAT1/energy_now; echo $f1 >$p/BAT1/energy_full; fi
    rm -f slept
    POWER=$p SUSPEND="touch slept" ${pkgs.lib.getExe low}
    got=awake; [ -e slept ] && got=sleep
    [ "$got" = "$want" ] || { echo "✗ $name: $got, $want expected"; exit 1; }
    echo "✓ $name: $got"
  }
  case_ "on mains, empty"           1    100000 20000000 100000 20000000 awake
  case_ "on battery, half"          0  10000000 20000000 10000000 20000000 awake
  case_ "on battery, 11 %"          0   2200000 20000000  2200000 20000000 awake
  case_ "on battery, 10 %"          0   2000000 20000000  2000000 20000000 sleep
  case_ "on battery, 6 % and 5 %"   0   1270000 20650000  1110000 20810000 sleep
  case_ "one full, one empty: 50 %" 0  20000000 20000000        0 20000000 awake
  case_ "one battery, 8 %"          0   1600000 20000000        - -        sleep
  case_ "no battery (a VM)"         0         - -               - -        awake
  touch $out
''
