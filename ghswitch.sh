#!/usr/bin/env bash
# ============================================================
#  ghswitch — GitHub Account Switcher
#  Compatible: bash 3.2+ (macOS default), Linux, Windows Git Bash/WSL
#  Manages: git config, SSH keys, GPG signing, gh CLI
# ============================================================

# NO set -e / set -u — breaks bash 3.2 and subshell return codes

# ── Colors ───────────────────────────────────────────────────
_init_colors() {
  if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    BOLD='\033[1m';  DIM='\033[2m';    RESET='\033[0m'
    GREEN='\033[38;5;82m'; CYAN='\033[38;5;117m'
    YELLOW='\033[38;5;220m'; RED='\033[38;5;203m'
    MAGENTA='\033[38;5;183m'; WHITE='\033[97m'
    BG_SEL='\033[48;5;235m'
  else
    BOLD=''; DIM=''; RESET=''; GREEN=''; CYAN=''
    YELLOW=''; RED=''; MAGENTA=''; WHITE=''; BG_SEL=''
  fi
}
_init_colors

# ── Paths ────────────────────────────────────────────────────
CONFIG_DIR="${HOME}/.config/ghswitch"
CONFIG_FILE="${CONFIG_DIR}/profiles.conf"
ACTIVE_FILE="${CONFIG_DIR}/active"

# ── OS detection ─────────────────────────────────────────────
case "$(uname -s 2>/dev/null)" in
  Darwin)             OS=macos   ;;
  Linux)              OS=linux   ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *)                  OS=unknown ;;
esac

# ── Capability flags ─────────────────────────────────────────
HAS_GH=false; HAS_GPG=false; HAS_AGENT=false
command -v gh        >/dev/null 2>&1 && HAS_GH=true
command -v gpg       >/dev/null 2>&1 && HAS_GPG=true
command -v ssh-agent >/dev/null 2>&1 && HAS_AGENT=true

# ── UI helpers ───────────────────────────────────────────────
header() {
  printf '\n'
  printf "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${WHITE}${BOLD}◉ ghswitch${RESET}  ${DIM}GitHub Account Switcher${RESET}   ${BOLD}${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}\n\n"
}
section() { printf "\n${BOLD}${MAGENTA}▸ %s${RESET}\n" "$1"; }
ok()      { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
info()    { printf "  ${CYAN}ℹ${RESET} %s\n" "$1"; }
warn()    { printf "  ${YELLOW}⚠${RESET} %s\n" "$1"; }
err()     { printf "  ${RED}✗${RESET} %s\n" "$1"; }
ask()     { printf "  ${BOLD}%s${RESET} " "$1"; }

# ── Config init ──────────────────────────────────────────────
init_config() {
  mkdir -p "${CONFIG_DIR}"
  [ -f "${CONFIG_FILE}" ] || touch "${CONFIG_FILE}"
  [ -f "${ACTIVE_FILE}" ] || printf '' > "${ACTIVE_FILE}"
}

# ── Profile helpers ──────────────────────────────────────────
get_profiles() {
  grep '^\[' "${CONFIG_FILE}" 2>/dev/null | sed 's/^\[//;s/\]$//' || true
}

get_field() {
  awk -v prof="[$1]" -v fld="$2" '
    $0 == prof        { found=1; next }
    found && /^\[/    { exit }
    found             { if (index($0, fld "=") == 1) { sub(/^[^=]+=/, ""); print; exit } }
  ' "${CONFIG_FILE}"
}

profile_exists() {
  grep -q "^\[$1\]" "${CONFIG_FILE}" 2>/dev/null
}

get_active() {
  tr -d '[:space:]' < "${ACTIVE_FILE}" 2>/dev/null || true
}

# ── Arrow-key menu ───────────────────────────────────────────
# Usage: chosen=$(arrow_menu item1 item2 ...)
arrow_menu() {
  local count=$# selected=0 active i label suffix key rest cur

  active=$(get_active)

  # Store items in indexed vars (bash 3.2 safe, no mapfile)
  i=0
  for item in "$@"; do
    eval "MENU_ITEM_${i}=\"\$item\""
    i=$((i + 1))
  done

  # Pre-select active profile
  for i in $(seq 0 $((count - 1))); do
    eval "cur=\$MENU_ITEM_${i}"
    if [ "$cur" = "$active" ]; then selected=$i; break; fi
  done

  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' EXIT INT TERM HUP

  while true; do
    for i in $(seq 0 $((count - 1))); do
      eval "label=\$MENU_ITEM_${i}"
      suffix=''
      [ "$label" = "$active" ] && suffix="  ${GREEN}${BOLD}● active${RESET}"
      if [ "$i" -eq "$selected" ]; then
        printf "  ${BG_SEL}${CYAN}${BOLD}  › %-20s${RESET}" "$label"
        printf "%b\n" "$suffix"
      else
        printf "    ${DIM}%-22s${RESET}" "$label"
        printf "%b\n" "$suffix"
      fi
    done

    IFS= read -r -s -n1 key
    case "$key" in
      $'\x1b')
        IFS= read -r -s -n2 -t 0.1 rest 2>/dev/null || rest=''
        key="${key}${rest}"
        ;;
    esac

    case "$key" in
      $'\x1b[A'|k)
        [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
      $'\x1b[B'|j)
        [ "$selected" -lt $((count - 1)) ] && selected=$((selected + 1)) ;;
      '')
        tput cnorm 2>/dev/null || true
        eval "printf '%s\n' \"\$MENU_ITEM_${selected}\""
        return 0 ;;
      q|$'\x03')
        tput cnorm 2>/dev/null || true
        return 1 ;;
    esac

    tput cuu "$count" 2>/dev/null || printf '\033[%dA' "$count"
  done
}

# ── Apply profile ────────────────────────────────────────────
apply_profile() {
  local profile="$1" scope="${2:-global}"
  local name email ssh_key gpg_key gh_host expanded_key

  if ! profile_exists "$profile"; then
    err "Profile '$profile' not found."
    return 1
  fi

  name=$(get_field "$profile" "name")
  email=$(get_field "$profile" "email")
  ssh_key=$(get_field "$profile" "ssh_key")
  gpg_key=$(get_field "$profile" "gpg_key")
  gh_host=$(get_field "$profile" "gh_host")
  gh_host="${gh_host:-github.com}"

  section "Applying profile: ${BOLD}${profile}${RESET} (${scope})"

  if [ -n "$name" ]; then
    git config --"$scope" user.name "$name"
    ok "user.name  = $name"
  fi
  if [ -n "$email" ]; then
    git config --"$scope" user.email "$email"
    ok "user.email = $email"
  fi

  if [ -n "$ssh_key" ]; then
    expanded_key=$(eval echo "$ssh_key")
    if [ -f "$expanded_key" ]; then
      git config --"$scope" core.sshCommand "ssh -i $expanded_key -o IdentitiesOnly=yes"
      ok "SSH key   = $expanded_key"
      if $HAS_AGENT && [ -n "${SSH_AUTH_SOCK:-}" ]; then
        ssh-add "$expanded_key" 2>/dev/null && ok "SSH key added to agent" || true
      fi
    else
      warn "SSH key file not found: $expanded_key"
    fi
  fi

  if [ -n "$gpg_key" ]; then
    if $HAS_GPG && gpg --list-secret-keys "$gpg_key" >/dev/null 2>&1; then
      git config --"$scope" user.signingKey "$gpg_key"
      git config --"$scope" commit.gpgSign true
      ok "GPG key   = $gpg_key"
    else
      warn "GPG key not in keyring: $gpg_key"
    fi
  fi

  if $HAS_GH; then
    if gh auth status --hostname "$gh_host" >/dev/null 2>&1; then
      ok "gh CLI    = authenticated on $gh_host"
    else
      warn "gh CLI not authed for $gh_host — run: gh auth login --hostname $gh_host"
    fi
  fi

  if [ "$scope" = "global" ]; then
    printf '%s' "$profile" > "${ACTIVE_FILE}"
    ok "Active profile → $profile"
  fi

  printf "\n  ${GREEN}${BOLD}✓ Done!${RESET}\n"
}

# ── Add profile ──────────────────────────────────────────────
add_profile() {
  local pname pname_full pemail pssh pgpg phost apply_now

  section "Add new profile"

  ask "Profile name (e.g. work, personal):"; read -r pname
  pname=$(printf '%s' "$pname" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

  if [ -z "$pname" ]; then err "Name cannot be empty."; return 1; fi

  if profile_exists "$pname"; then
    warn "Profile '$pname' already exists. Use 'ghswitch edit' to modify."
    return 1
  fi

  ask "Github Username:";                                            read -r pname_full
  ask "Email:";                                                      read -r pemail
  ask "SSH key path (blank to skip, e.g. ~/.ssh/id_ed25519_work):";  read -r pssh
  ask "GPG key ID (blank to skip):";                                 read -r pgpg
  ask "GitHub host (Enter = github.com):";                           read -r phost
  phost="${phost:-github.com}"

  printf '\n[%s]\nname=%s\nemail=%s\n' "$pname" "$pname_full" "$pemail" >> "${CONFIG_FILE}"
  [ -n "$pssh" ] && printf 'ssh_key=%s\n' "$pssh" >> "${CONFIG_FILE}"
  [ -n "$pgpg" ] && printf 'gpg_key=%s\n' "$pgpg" >> "${CONFIG_FILE}"
  printf 'gh_host=%s\n' "$phost" >> "${CONFIG_FILE}"

  ok "Profile '$pname' saved."

  ask "Apply this profile globally now? (y/N):"; read -r apply_now
  case "$apply_now" in [Yy]) apply_profile "$pname" "global" ;; esac
}

# ── List profiles ─────────────────────────────────────────────
list_profiles() {
  local active profiles p n e s g h mark

  active=$(get_active)
  profiles=$(get_profiles)

  section "Configured profiles"

  if [ -z "$profiles" ]; then
    warn "No profiles yet. Run: ghswitch add"
    return
  fi

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    n=$(get_field "$p" "name");    e=$(get_field "$p" "email")
    s=$(get_field "$p" "ssh_key"); g=$(get_field "$p" "gpg_key")
    h=$(get_field "$p" "gh_host"); mark=''
    [ "$p" = "$active" ] && mark="  ${GREEN}${BOLD}← active${RESET}"

    printf "\n  ${BOLD}${CYAN}[%s]${RESET}" "$p"; printf "%b\n" "$mark"
    printf "    ${DIM}name  :${RESET} %s\n" "$n"
    printf "    ${DIM}email :${RESET} %s\n" "$e"
    [ -n "$s" ] && printf "    ${DIM}ssh   :${RESET} %s\n" "$s"
    [ -n "$g" ] && printf "    ${DIM}gpg   :${RESET} %s\n" "$g"
    [ -n "$h" ] && printf "    ${DIM}host  :${RESET} %s\n" "$h"
  done <<PROFILES
$profiles
PROFILES
  printf '\n'
}

# ── Status ───────────────────────────────────────────────────
show_status() {
  local gname gemail ggpg gssh active

  section "Current git identity (global)"
  gname=$(git config --global user.name       2>/dev/null || printf '(not set)')
  gemail=$(git config --global user.email     2>/dev/null || printf '(not set)')
  ggpg=$(git config --global user.signingKey  2>/dev/null || printf '(not set)')
  gssh=$(git config --global core.sshCommand  2>/dev/null || printf '(default)')
  active=$(get_active)

  printf "  ${DIM}Name     :${RESET} ${BOLD}%s${RESET}\n" "$gname"
  printf "  ${DIM}Email    :${RESET} ${BOLD}%s${RESET}\n" "$gemail"
  printf "  ${DIM}GPG Key  :${RESET} %s\n" "$ggpg"
  printf "  ${DIM}SSH Cmd  :${RESET} ${DIM}%s${RESET}\n" "$gssh"
  [ -n "$active" ] && printf "  ${DIM}ghswitch :${RESET} ${GREEN}${BOLD}%s${RESET} (active)\n" "$active"

  if $HAS_GH; then
    section "gh CLI status"
    gh auth status 2>&1 | sed 's/^/  /' || true
  fi
  printf '\n'
}

# ── Build args array from newline string (bash 3.2 safe) ─────
_profiles_to_args() {
  # populates global MENU_ARGS and MENU_COUNT
  MENU_COUNT=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    eval "MENU_ARGS_${MENU_COUNT}=\"\$line\""
    MENU_COUNT=$((MENU_COUNT + 1))
  done <<PEOF
$1
PEOF
}

_call_menu_from_args() {
  local i args_str=''
  local tmp_args=()
  for i in $(seq 0 $((MENU_COUNT - 1))); do
    eval "tmp_args[\$i]=\$MENU_ARGS_${i}"
  done
  arrow_menu "${tmp_args[@]}"
}

# ── Interactive switcher ──────────────────────────────────────
interactive_switch() {
  local profiles chosen

  profiles=$(get_profiles)
  if [ -z "$profiles" ]; then
    warn "No profiles yet."
    info "Run: ghswitch add"
    return
  fi

  section "Switch global profile"
  printf "  ${DIM}↑↓ / j k to navigate · Enter to select · q to quit${RESET}\n\n"

  _profiles_to_args "$profiles"
  chosen=$(_call_menu_from_args) || { printf '\n'; info "Cancelled."; return; }
  printf '\n'
  apply_profile "$chosen" "global"
}

# ── Local (per-repo) ─────────────────────────────────────────
apply_local() {
  local profiles chosen repo_root

  profiles=$(get_profiles)
  if [ -z "$profiles" ]; then
    warn "No profiles yet. Run: ghswitch add"
    return
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    err "Not inside a git repository."
    return 1
  fi

  repo_root=$(git rev-parse --show-toplevel)
  section "Apply profile to this repo only"
  info "Repo: $repo_root"
  printf "  ${DIM}↑↓ / j k · Enter · q${RESET}\n\n"

  _profiles_to_args "$profiles"
  chosen=$(_call_menu_from_args) || { printf '\n'; info "Cancelled."; return; }
  printf '\n'
  apply_profile "$chosen" "local"
}

# ── Delete profile ────────────────────────────────────────────
delete_profile() {
  local profiles chosen tmp active confirm

  profiles=$(get_profiles)
  if [ -z "$profiles" ]; then
    warn "No profiles found."
    return
  fi

  section "Delete a profile"
  printf "  ${DIM}↑↓ / j k · Enter · q to cancel${RESET}\n\n"

  _profiles_to_args "$profiles"
  chosen=$(_call_menu_from_args) || { printf '\n'; info "Cancelled."; return; }
  printf '\n'

  ask "Delete '$chosen'? This cannot be undone. (y/N):"; read -r confirm
  case "$confirm" in
    [Yy])
      tmp=$(mktemp)
      awk -v prof="[$chosen]" '
        $0 == prof     { skip=1; next }
        skip && /^\[/  { skip=0 }
        !skip          { print }
      ' "${CONFIG_FILE}" > "$tmp"
      mv "$tmp" "${CONFIG_FILE}"
      ok "Profile '$chosen' deleted."
      active=$(get_active)
      [ "$active" = "$chosen" ] && printf '' > "${ACTIVE_FILE}"
      ;;
    *) info "Cancelled." ;;
  esac
}

# ── Unset global identity ─────────────────────────────────────
unset_global() {
  local confirm
  section "Clear global git identity"
  ask "Remove global user.name, email, SSH command, GPG config? (y/N):"; read -r confirm
  case "$confirm" in
    [Yy])
      git config --global --unset user.name       2>/dev/null && ok "Cleared user.name"       || true
      git config --global --unset user.email      2>/dev/null && ok "Cleared user.email"      || true
      git config --global --unset core.sshCommand 2>/dev/null && ok "Cleared core.sshCommand" || true
      git config --global --unset user.signingKey 2>/dev/null && ok "Cleared user.signingKey" || true
      git config --global --unset commit.gpgSign  2>/dev/null && ok "Cleared commit.gpgSign"  || true
      printf '' > "${ACTIVE_FILE}"
      ok "Global identity cleared."
      ;;
    *) info "Cancelled." ;;
  esac
}

# ── Edit config file ──────────────────────────────────────────
edit_config() {
  local ed="${EDITOR:-${VISUAL:-vi}}"
  info "Opening ${CONFIG_FILE} in ${ed}"
  "$ed" "${CONFIG_FILE}"
}

# ── Usage ────────────────────────────────────────────────────
usage() {
  printf "${BOLD}Usage:${RESET}  ghswitch ${CYAN}[command | profile-name]${RESET}\n\n"
  printf "${BOLD}Commands:${RESET}\n"
  printf "  ${CYAN}%-10s${RESET}  %s\n" \
    "(none)"  "Interactive arrow-key profile switcher" \
    "add"     "Add a new profile" \
    "list"    "Show all profiles" \
    "local"   "Apply profile to current repo only (--local)" \
    "status"  "Show current git identity" \
    "unset"   "Clear global git identity" \
    "edit"    "Open config in \$EDITOR" \
    "delete"  "Remove a profile" \
    "help"    "This help text"
  printf "\n${BOLD}Direct switch:${RESET}  ghswitch work\n"
  printf "\n${BOLD}Config file:${RESET}  %s\n\n" "${CONFIG_FILE}"
  printf "${DIM}Example:\n\n  [work]\n  name=Jane Doe\n  email=jane@company.com\n"
  printf "  ssh_key=~/.ssh/id_ed25519_work\n  gpg_key=ABCD1234\n  gh_host=github.com${RESET}\n\n"
}

# ── Main ─────────────────────────────────────────────────────
main() {
  if ! command -v git >/dev/null 2>&1; then
    err "git is not installed or not in PATH."; exit 1
  fi

  init_config
  header

  local cmd="${1:-}"

  case "$cmd" in
    "")             interactive_switch ;;
    add)            add_profile        ;;
    list|ls)        list_profiles      ;;
    local)          apply_local        ;;
    status|whoami)  show_status        ;;
    unset|reset)    unset_global       ;;
    edit)           edit_config        ;;
    delete|rm)      delete_profile     ;;
    help|--help|-h) usage              ;;
    *)
      if profile_exists "$cmd"; then
        apply_profile "$cmd" "global"
      else
        err "Unknown command or profile: '$cmd'"
        printf '\n'; usage; exit 1
      fi
      ;;
  esac
}

main "$@"