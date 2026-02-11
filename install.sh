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

for arg in "$@"; do
  case "$arg" in
    --local)
      LOCAL_MODE=true
      ;;
    -h|--help)
      printf "Usage: %s [--local]\n" "$(basename "$0")"
      printf "\n"
      printf "  --local    Install files from your local repo checkout instead of GitHub.\n"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $arg"
      printf "Usage: %s [--local]\n" "$(basename "$0")"
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

if [[ "$LOCAL_MODE" == true ]]; then
  log_info "Install source: local repo at $REPO_DIR"
else
  log_info "Install source: GitHub ($BASE_URL)"
fi

log_info "Preparing config directories..."
mkdir -p "$CONFIG_DIR" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/docs"

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
  install_file "agents/$agent.md" "$CONFIG_DIR/agents/$agent.md"
done

log_info "Installing commands..."
commands=(bootstrap-memory save-memory)
for cmd in "${commands[@]}"; do
  install_file "commands/$cmd.md" "$CONFIG_DIR/commands/$cmd.md"
done

log_info "Installing docs..."
docs=(agents configuration workflows)
for doc in "${docs[@]}"; do
  install_file "docs/$doc.md" "$CONFIG_DIR/docs/$doc.md"
done

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

printf "%b\n" "${GREEN}${BOLD}Install complete.${NC}"
printf "%b\n" "${BOLD}Next steps:${NC}"
printf "  1) Edit %s/opencode.json with your API keys and server URLs.\n" "$CONFIG_DIR"
if [[ "$LOCAL_MODE" == true ]]; then
  printf "  2) Optionally run model configurator: bash %s/configure.sh\n" "$REPO_DIR"
else
  printf "  2) Optionally run model configurator: curl -fsSL %s/configure.sh | bash\n" "$BASE_URL"
fi
printf "  3) Verify MCP server settings (megamemory).\n"
printf "  4) Restart OpenCode.\n"
