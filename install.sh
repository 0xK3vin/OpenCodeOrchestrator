#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_DIR="$HOME/.config/opencode"
BASE_URL="https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchestrator/main"
LOCAL_MODE=false
REPO_DIR=""
FORCE_MODE=false
IS_UPDATE=false
HAS_TTY=false
BACKUP_DIR=""

# anonymous install counter
curl -fsSL "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fgithub.com%2F0xK3vin%2FOpenCodeOrchestrator%2Finstall&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=installs&edge_flat=false" > /dev/null 2>&1 &

log_info() {
  printf "%b\n" "${BLUE}[info]${NC} $1"
}

log_warn() {
  printf "%b\n" "${YELLOW}[warn]${NC} $1"
}

log_success() {
  printf "%b\n" "${GREEN}[ok]${NC} $1"
}

log_error() {
  printf "%b\n" "${RED}[error]${NC} $1"
}

if [[ "$(uname)" == "Darwin" ]]; then
  sed_inplace() { sed -i '' "$@"; }
else
  sed_inplace() { sed -i "$@"; }
fi

install_file() {
  local src="$1"
  local dest="$2"

  if [[ "$LOCAL_MODE" == true ]]; then
    local local_src="$REPO_DIR/$src"
    if [[ ! -f "$local_src" ]]; then
      log_error "Local file not found: $local_src"
      exit 1
    fi
    if ! cp "$local_src" "$dest"; then
      log_error "Failed to copy local file: $local_src"
      exit 1
    fi
  else
    local remote_src="$BASE_URL/$src"
    if ! curl -fsSL "$remote_src" -o "$dest"; then
      log_error "Failed to download: $remote_src"
      exit 1
    fi
  fi
}

extract_frontmatter_value() {
  local key="$1"
  local file="$2"
  sed -n '1{/^---$/!q}; 1,/^---$/p' "$file" | grep -m1 "^${key}:" | sed "s/^${key}:[[:space:]]*//" || true
}

extract_body() {
  local file="$1"
  local end_line
  end_line=$(awk '/^---$/{c++; if(c==2){print NR; exit}}' "$file")
  if [[ -n "$end_line" ]]; then
    tail -n +"$((end_line + 1))" "$file"
  fi
}

restore_model_value() {
  local model_value="$1"
  local dest="$2"

  if [[ -n "$model_value" ]]; then
    sed_inplace "s|^model:[[:space:]]*.*$|model: $model_value|" "$dest"
  fi
}

prompt_agent_conflict() {
  local dest="$1"
  local new_file="$2"
  local model_value="$3"
  local choice=""
  local upstream_file="${dest}.upstream"

  while true; do
    printf "\n%b\n" "${YELLOW}Agent prompt differs from upstream:${NC} $dest"
    printf "  1) Overwrite with upstream (preserve model)\n"
    printf "  2) Skip (keep current file, save upstream as %s)\n" "$upstream_file"
    printf "  3) Show diff\n"
    printf "Choose [1-3] (default: 2): "

    if ! read -r choice < /dev/tty 2>/dev/null; then
      if ! read -r choice; then
        choice="2"
      fi
    fi

    case "${choice:-2}" in
      1)
        mv "$new_file" "$dest"
        restore_model_value "$model_value" "$dest"
        log_warn "Overwrote $dest with upstream content (model preserved)."
        return 0
        ;;
      2)
        mv "$new_file" "$upstream_file"
        log_warn "Kept current file. Saved upstream version to: $upstream_file"
        return 0
        ;;
      3)
        diff --color=auto "$dest" "$new_file" || true
        ;;
      *)
        log_warn "Invalid selection. Enter 1, 2, or 3."
        ;;
    esac
  done
}

update_agent_file() {
  local src="$1"
  local dest="$2"
  local new_file="${dest}.new"
  local current_model=""
  local bodies_match=false

  install_file "$src" "$new_file"

  current_model="$(extract_frontmatter_value "model" "$dest")"

  if diff -q <(extract_body "$dest") <(extract_body "$new_file") >/dev/null 2>&1; then
    bodies_match=true
  fi

  if [[ "$bodies_match" == true ]]; then
    mv "$new_file" "$dest"
    restore_model_value "$current_model" "$dest"
    return 0
  fi

  if [[ "$HAS_TTY" == true ]]; then
    prompt_agent_conflict "$dest" "$new_file" "$current_model"
    return 0
  fi

  if [[ -n "$BACKUP_DIR" ]]; then
    cp "$dest" "$BACKUP_DIR/$(basename "$dest")" 2>/dev/null || true
  fi

  mv "$new_file" "$dest"
  restore_model_value "$current_model" "$dest"
  log_warn "No TTY detected; replaced $dest with upstream and preserved model."
  log_warn "Review custom changes via backup at: ${BACKUP_DIR:-<not-created>}"
}

install_file_update_safe() {
  local src="$1"
  local dest="$2"
  local file_type="$3"

  if [[ ! -f "$dest" ]]; then
    install_file "$src" "$dest"
    return 0
  fi

  if [[ "$file_type" == "agent" ]]; then
    update_agent_file "$src" "$dest"
  else
    install_file "$src" "$dest"
  fi
}

for arg in "$@"; do
  case "$arg" in
    --local)
      LOCAL_MODE=true
      ;;
    --force)
      FORCE_MODE=true
      ;;
    -h|--help)
      printf "Usage: %s [--local] [--force]\n" "$(basename "$0")"
      printf "\n"
      printf "  --local    Install files from your local repo checkout instead of GitHub.\n"
      printf "  --force    Overwrite all installed files without update-safe prompts.\n"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $arg"
      printf "Usage: %s [--local] [--force]\n" "$(basename "$0")"
      exit 1
      ;;
  esac
done

if [[ "$LOCAL_MODE" == true ]]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ ! -d "$REPO_DIR/agents" || ! -d "$REPO_DIR/config" || ! -d "$REPO_DIR/commands" || ! -d "$REPO_DIR/docs" ]]; then
    log_error "Local repo structure not found at $REPO_DIR. Expected agents/, config/, commands/, and docs/."
    exit 1
  fi
fi

printf "%b\n" "${BOLD}${BLUE}"
printf "============================================================\n"
printf "                  OpenCode Orchestrator Installer           \n"
printf "============================================================\n"
printf "%b\n" "${NC}"

if [[ -d "$CONFIG_DIR" ]] || command -v opencode >/dev/null 2>&1; then
  log_success "OpenCode environment detected."
else
  log_warn "OpenCode not detected yet (no ~/.config/opencode and no opencode command)."
  log_warn "Continuing setup anyway so files are ready when OpenCode is installed."
fi

IS_UPDATE=false
if [[ -d "$CONFIG_DIR/agents" ]]; then
  IS_UPDATE=true
  log_info "Existing installation detected. Running in update mode."
fi

if [[ -t 1 ]] || [[ -e /dev/tty ]]; then
  HAS_TTY=true
fi

if [[ "$LOCAL_MODE" == true ]]; then
  log_info "Install source: local repo at $REPO_DIR"
else
  log_info "Install source: GitHub ($BASE_URL)"
fi

log_info "Preparing config directories..."
mkdir -p "$CONFIG_DIR" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/docs"

if [[ "$IS_UPDATE" == true ]] && [[ "$FORCE_MODE" == false ]]; then
  BACKUP_DIR="$CONFIG_DIR/backups/.backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  cp "$CONFIG_DIR/agents/"*.md "$BACKUP_DIR/" 2>/dev/null || true
  log_info "Created agent backup at: $BACKUP_DIR"
fi

log_info "Installing core config files..."
install_file "config/AGENTS.md" "$CONFIG_DIR/AGENTS.md"
install_file "config/package.json" "$CONFIG_DIR/package.json"

if [[ -f "$CONFIG_DIR/opencode.json" ]]; then
  log_warn "Existing opencode.json found. Keeping your current config."
  install_file "config/opencode.json" "$CONFIG_DIR/opencode.json.example"
  log_warn "Installed template to: $CONFIG_DIR/opencode.json.example"
else
  install_file "config/opencode.json" "$CONFIG_DIR/opencode.json"
  log_success "Installed opencode.json template."
fi

log_info "Installing agent prompts..."
agents=(orchestrator build plan debug devops explore review)
for agent in "${agents[@]}"; do
  if [[ "$IS_UPDATE" == true ]] && [[ "$FORCE_MODE" == false ]]; then
    install_file_update_safe "agents/$agent.md" "$CONFIG_DIR/agents/$agent.md" "agent"
  else
    install_file "agents/$agent.md" "$CONFIG_DIR/agents/$agent.md"
  fi
done

log_info "Installing commands..."
commands=(bootstrap-memory save-memory)
for cmd in "${commands[@]}"; do
  if [[ "$IS_UPDATE" == true ]] && [[ "$FORCE_MODE" == false ]]; then
    install_file_update_safe "commands/$cmd.md" "$CONFIG_DIR/commands/$cmd.md" "command"
  else
    install_file "commands/$cmd.md" "$CONFIG_DIR/commands/$cmd.md"
  fi
done

log_info "Installing docs..."
docs=(agents configuration workflows)
for doc in "${docs[@]}"; do
  if [[ "$IS_UPDATE" == true ]] && [[ "$FORCE_MODE" == false ]]; then
    install_file_update_safe "docs/$doc.md" "$CONFIG_DIR/docs/$doc.md" "doc"
  else
    install_file "docs/$doc.md" "$CONFIG_DIR/docs/$doc.md"
  fi
done

if [[ "$FORCE_MODE" == true ]] || [[ "$IS_UPDATE" == false ]]; then
  rm -f "$CONFIG_DIR/agents/"*.upstream "$CONFIG_DIR/agents/"*.new 2>/dev/null || true
fi

if [[ -f "$CONFIG_DIR/package.json" ]]; then
  if command -v npm >/dev/null 2>&1; then
    log_info "Installing npm dependencies in $CONFIG_DIR ..."
    npm install --prefix "$CONFIG_DIR"
    log_success "Dependencies installed."
  else
    log_warn "npm is not installed; skipped dependency installation."
    log_warn "Run this later: npm install --prefix $CONFIG_DIR"
  fi
fi

if [[ "$IS_UPDATE" == true ]] && [[ "$FORCE_MODE" == false ]]; then
  if [[ "$LOCAL_MODE" == true ]]; then
    log_info "Run model configurator later if needed: bash $REPO_DIR/configure.sh"
  else
    log_info "Run model configurator later if needed: curl -fsSL $BASE_URL/configure.sh | bash"
  fi
else
  printf "\nWould you like to configure agent models now? [y/N] "
  configure_now=""
  if [[ -t 1 ]]; then
    read -r configure_now < /dev/tty || true
  fi
  if [[ "${configure_now:-}" =~ ^[Yy]$ ]]; then
    log_info "Running model configurator..."
    if [[ "$LOCAL_MODE" == true ]]; then
      if [[ -f "$REPO_DIR/configure.sh" ]]; then
        if ! bash "$REPO_DIR/configure.sh"; then
          log_warn "Model configurator failed. You can run it later from the command below."
        fi
      else
        log_warn "Local configure.sh not found at: $REPO_DIR/configure.sh"
      fi
    elif ! curl -fsSL "$BASE_URL/configure.sh" | bash; then
      log_warn "Model configurator failed. You can run it later from the command below."
    fi
  fi
fi

if [[ "$IS_UPDATE" == true ]] && [[ "$FORCE_MODE" == false ]]; then
  printf "%b\n" "${GREEN}${BOLD}Update complete.${NC}"
  printf "  - Agent model configurations preserved.\n"
  upstream_files=("$CONFIG_DIR/agents/"*.upstream)
  if compgen -G "$CONFIG_DIR/agents/*.upstream" > /dev/null; then
    printf "  - Upstream files pending review:\n"
    for upstream in "${upstream_files[@]}"; do
      printf "    * %s\n" "$(basename "$upstream")"
    done
  else
    printf "  - No agent prompt conflicts detected.\n"
  fi
  if [[ -n "$BACKUP_DIR" ]]; then
    printf "  - Backup location: %s\n" "$BACKUP_DIR"
  fi
  printf "\n%b\n" "${BOLD}Next steps:${NC}"
  printf "  1) Review any *.upstream files in %s/agents (if listed above).\n" "$CONFIG_DIR"
  printf "  2) Verify MCP server settings (megamemory, exa, grep_app are pre-configured).\n"
  printf "  3) Restart OpenCode.\n"
else
  printf "%b\n" "${GREEN}${BOLD}Install complete.${NC}"
  printf "%b\n" "${BOLD}Next steps:${NC}"
  printf "  1) Edit %s/opencode.json with your API keys and server URLs.\n" "$CONFIG_DIR"
  if [[ "$LOCAL_MODE" == true ]]; then
    printf "  2) Optionally run model configurator: bash %s/configure.sh\n" "$REPO_DIR"
  else
    printf "  2) Optionally run model configurator: curl -fsSL %s/configure.sh | bash\n" "$BASE_URL"
  fi
  printf "  3) Verify MCP server settings (megamemory, exa, grep_app are pre-configured).\n"
  printf "  4) Restart OpenCode.\n"
fi
