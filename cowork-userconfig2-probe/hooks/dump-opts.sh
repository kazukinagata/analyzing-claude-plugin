#!/usr/bin/env bash
# dump-opts.sh — plugin-level SessionStart hook (host side).
#
# Docs (post-2.1.207) say: "All values are exported to hook processes as
# CLAUDE_PLUGIN_OPTION_<KEY> environment variables, where <KEY> is the option
# key uppercased." This is the documented workaround now that SHELL-FORM hook
# commands referencing ${user_config.*} fail instead of running.
#
# So: this script reads the env vars (never ${user_config.*}) and reports, per
# key, whether the var EXISTS and what it holds. Set vs empty vs absent are
# distinguished, because "absent" and "empty" mean different things here:
#   absent -> the runtime never exported the option to the hook process
#   empty  -> exported but unset/blank by the user
# All values in this probe are dummy strings chosen by the runbook, so echoing
# them (including the sensitive ones) is intentional: leaking a real secret is
# the very thing §1.4 is about, and we want to SEE whether it leaks.

echo "UC2-ENV marker=reached host=$(hostname 2>/dev/null || echo unknown) argv0=[$0]"

for key in OPT_PLAIN REQ_PLAIN OPT_SECRET REQ_SECRET DEF_PLAIN NUM_OPT BOOL_OPT MULTI_OPT; do
  var="CLAUDE_PLUGIN_OPTION_${key}"
  if env | grep -q "^${var}="; then
    val="$(eval "printf '%s' \"\${$var}\"")"
    echo "UC2-ENV ${var}=[${val}] len=${#val}"
  else
    echo "UC2-ENV ${var}=<ABSENT from env>"
  fi
done

# Anything else the runtime exported under this prefix that we did not declare.
echo "UC2-ENV all_prefixed_names=[$(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Z0-9_]*\)=.*/\1/p' | sort | tr '\n' ' ')]"
