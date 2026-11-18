# Sourced by the scripts that build the development variant (update-x250.sh,
# reinstall-x250.sh, publish-dev.sh): its SSH keys, hosts/x250/dev-keys.pub,
# the build machine's own, never committed, given to the flake as its input
# dev-keys (flake.nix), outside its sources. Without the file, devkeys stays
# empty and the development variant does not build (no key, no SSH).
# shellcheck shell=bash
devkeys=()
if grep -qE '^(ssh|ecdsa)-' hosts/x250/dev-keys.pub 2>/dev/null; then
  # shellcheck disable=SC2034 # read by the scripts that source this one
  devkeys=(--override-input dev-keys "path:$PWD/hosts/x250/dev-keys.pub")
fi
