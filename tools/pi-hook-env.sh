# pi-hook-env.sh — source before committing or pushing on the Pi:
#   . /config/tools/pi-hook-env.sh
#
# The Terminal & SSH add-on keeps only /config across an update, and an SSH
# command loads no shell profile, so the repository's hooks get their settings
# here: pre-commit's environments and the gitleaks binary under /config/.tools,
# and the operator's scan inputs, which the review host's merged-main apply keeps
# current, under /config/.tools/operator-config. Without this the scans fail
# closed: they refuse the commit rather than skip a check.
# shellcheck shell=sh

export PI_TOOLS=/config/.tools
export PRE_COMMIT_HOME="$PI_TOOLS/pre-commit"
export XDG_CONFIG_HOME="$PI_TOOLS/operator-config"
case ":$PATH:" in
*:"$PI_TOOLS":*) ;;
*) export PATH="$PI_TOOLS:$PATH" ;;
esac

# These select trusted CI scan modes. An inherited shell must never weaken or
# redirect the scan on the Pi.
unset GL_NO_OVERLAY GL_OVERLAY_ONLY GL_CONFIG_PATH GL_IGNORE_PATH GL_BASE_REF GL_DECLARED_JSON
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
