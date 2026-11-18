#!/usr/bin/env bash
# The development variant never sleeps when idle (to stay reachable by SSH):
# on battery, it would run until it dies (seen on the X250, 18 November 2026).
# So, every minute: on battery, at LIMIT % or less (both batteries together,
# by their energy), it goes to sleep, past the inhibitor that keeps it awake.
# On mains, or without a battery (a virtual machine), nothing.
#   POWER: the power supplies (/sys/class/power_supply); LIMIT: 10 by default;
#   SUSPEND: the command (systemctl suspend --ignore-inhibitors).
set -euo pipefail
power=${POWER:-/sys/class/power_supply}
limit=${LIMIT:-10}

mains=0 now=0 full=0
for s in "$power"/*; do
  [ -r "$s/type" ] || continue
  case $(cat "$s/type") in
    Mains) [ "$(cat "$s/online" 2>/dev/null || echo 0)" = 1 ] && mains=1 ;;
    Battery)
      n=$(cat "$s/energy_now" 2>/dev/null || cat "$s/charge_now" 2>/dev/null || echo 0)
      f=$(cat "$s/energy_full" 2>/dev/null || cat "$s/charge_full" 2>/dev/null || echo 0)
      now=$((now + n))
      full=$((full + f))
      ;;
  esac
done
[ "$full" -gt 0 ] || exit 0
[ "$mains" = 0 ] || exit 0
left=$((100 * now / full))
[ "$left" -le "$limit" ] || exit 0

echo "sur batterie, $left % restants (seuil $limit %) : mise en veille"
# shellcheck disable=SC2086 # SUSPEND is a command and its words
exec ${SUSPEND:-systemctl suspend --ignore-inhibitors}
