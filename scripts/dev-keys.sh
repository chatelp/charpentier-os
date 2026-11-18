# Sourced by the scripts that build the development variant (update-x250.sh,
# reinstall-x250.sh, publish-dev.sh): its SSH keys, hosts/x250/dev-keys.pub
# (or the file CHARPENTIER_DEV_KEYS names, a virtual machine's key, say), the
# build machine's own, never committed, given to the flake as its input
# dev-keys (flake.nix), outside its sources. Without the file, devkeys stays
# empty and the development variant does not build (no key, no SSH).
# shellcheck shell=bash
devkeys=()
dev_keys_file=${CHARPENTIER_DEV_KEYS:-hosts/x250/dev-keys.pub}
if grep -qE '^(ssh|ecdsa)-' "$dev_keys_file" 2>/dev/null; then
  # shellcheck disable=SC2034 # read by the scripts that source this one
  devkeys=(--override-input dev-keys "path:$(realpath "$dev_keys_file")")
fi
