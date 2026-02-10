#!/usr/bin/env bash
set -euo pipefail

trap 'printf "\nAborted. No changes made.\n"; exit 1' INT TERM

# Ensure reads come from terminal, not pipe (for curl | bash usage)
exec 3</dev/tty 2>/dev/null || exec 3<&0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CONFIG_DIR="$HOME/.config/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"

AGENTS=(orchestrator plan build debug devops explore review)
REASONING_AGENTS=(orchestrator plan debug review)
EXECUTION_AGENTS=(devops explore)
CODING_AGENTS=(build)

if [[ "$(uname)" == "Darwin" ]]; then
    sed_inplace() { sed -i '' "$@"; }
else
    sed_inplace() { sed -i "$@"; }
fi

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

in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

get_current_model() {
  local agent_name="$1"
  local agent_file="$AGENTS_DIR/$agent_name.md"
  grep -m1 '^model:[[:space:]]*' "$agent_file" | sed 's/^model:[[:space:]]*//' | xargs
}

set_model() {
  local agent_name="$1"
  local model_string="$2"
  local agent_file="$AGENTS_DIR/$agent_name.md"
  sed_inplace "s|^model:[[:space:]]*.*$|model: $model_string|" "$agent_file"
}

prompt_choice() {
  local prompt_text="$1"
  shift
  local options=("$@")
  local input
  local idx

  while true; do
    printf "\n%b\n" "${BOLD}$prompt_text${NC}"
    idx=1
    for option in "${options[@]}"; do
      printf "  %d) %s\n" "$idx" "$option"
      idx=$((idx + 1))
    done
    printf "\nSelect an option [1-%d]: " "${#options[@]}"
    read -r input <&3

    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#options[@]} )); then
      CHOICE="$input"
      return 0
    fi

    log_warn "Invalid selection. Please enter a number between 1 and ${#options[@]}."
  done
}

prompt_custom_model() {
  local context="$1"
  local model_string

  while true; do
    printf "Enter custom model for %s (format provider/model): " "$context"
    read -r model_string <&3
    model_string="$(trim_whitespace "$model_string")"

    if [[ -z "$model_string" ]]; then
      log_warn "Model cannot be empty."
      continue
    fi

    if [[ "$model_string" != */* ]]; then
      log_warn "Model must include '/'. Example: provider/model-name"
      continue
    fi

    CHOICE="$model_string"
    return 0
  done
}

pick_from_model_list() {
  local context="$1"
  local custom_index="$2"
  shift 2
  local models=("$@")
  local choice_index

  prompt_choice "$context" "${models[@]}"
  choice_index="$CHOICE"

  if (( choice_index == custom_index )); then
    prompt_custom_model "$context"
  else
    CHOICE="${models[$((choice_index - 1))]}"
  fi
}

show_banner() {
  printf "%b\n" "${BOLD}${MAGENTA}============================================================${NC}"
  printf "%b\n" "${BOLD}${CYAN}            OpenCode Orchestrator Configurator             ${NC}"
  printf "%b\n" "${BOLD}${MAGENTA}============================================================${NC}"
}

verify_preflight() {
  local agent

  if [[ ! -d "$AGENTS_DIR" ]]; then
    log_error "Expected agent directory not found: $AGENTS_DIR"
    log_info "Run install first: curl -fsSL https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchastrator/main/install.sh | bash"
    exit 1
  fi

  for agent in "${AGENTS[@]}"; do
    if [[ ! -f "$AGENTS_DIR/$agent.md" ]]; then
      log_error "Missing agent file: $AGENTS_DIR/$agent.md"
      log_info "Re-run install to restore missing files."
      exit 1
    fi
  done
}

show_current_config() {
  local i

  printf "\n%b\n" "${BOLD}Current Model Configuration${NC}"
  printf "%b\n\n" "${DIM}================================================================${NC}"

  printf "  %b\n" "${BOLD}Reasoning Tier${NC}"
  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${REASONING_AGENTS[@]}"; then
      printf "    %-12s  ·  %s\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    fi
  done

  printf "\n  %b\n" "${BOLD}Execution Tier${NC}"
  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${EXECUTION_AGENTS[@]}"; then
      printf "    %-12s  ·  %s\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    fi
  done

  printf "\n  %b\n" "${BOLD}Coding Tier${NC}"
  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${CODING_AGENTS[@]}"; then
      printf "    %-12s  ·  %s\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    fi
  done

  printf "%b\n" "${DIM}================================================================${NC}"
}

select_profile() {
  local profile

  printf "\n%b\n" "${BOLD}Model Profiles${NC}"
  printf "  1) Recommended  - Opus + Sonnet + Codex (current defaults)\n"
  printf "     Reasoning: anthropic/claude-opus-4-6\n"
  printf "     Execution: anthropic/claude-sonnet-4-20250514\n"
  printf "     Coding:    openai/gpt-5.3-codex\n\n"
  printf "  2) All Claude   - Opus reasoning, Sonnet everything else\n"
  printf "     Reasoning: anthropic/claude-opus-4-6\n"
  printf "     Execution: anthropic/claude-sonnet-4-20250514\n"
  printf "     Coding:    anthropic/claude-sonnet-4-20250514\n\n"
  printf "  3) All OpenAI   - o3 reasoning, GPT-4.1 execution, Codex coding\n"
  printf "     Reasoning: openai/o3\n"
  printf "     Execution: openai/gpt-4.1\n"
  printf "     Coding:    openai/gpt-5.3-codex\n\n"
  printf "  4) All Google   - Gemini Pro + Flash\n"
  printf "     Reasoning: google/gemini-2.5-pro\n"
  printf "     Execution: google/gemini-2.5-flash\n"
  printf "     Coding:    google/gemini-2.5-pro\n\n"
  printf "  5) Budget       - Sonnet everywhere\n"
  printf "     Reasoning: anthropic/claude-sonnet-4-20250514\n"
  printf "     Execution: anthropic/claude-sonnet-4-20250514\n"
  printf "     Coding:    anthropic/claude-sonnet-4-20250514\n\n"
  printf "  6) Custom       - Choose per-tier or per-agent\n"

  prompt_choice "Choose a model profile" \
    "Recommended" \
    "All Claude" \
    "All OpenAI" \
    "All Google" \
    "Budget" \
    "Custom"
  profile="$CHOICE"

  case "$profile" in
    1)
      REASONING_MODEL="anthropic/claude-opus-4-6"
      EXECUTION_MODEL="anthropic/claude-sonnet-4-20250514"
      CODING_MODEL="openai/gpt-5.3-codex"
      apply_tier_models
      ;;
    2)
      REASONING_MODEL="anthropic/claude-opus-4-6"
      EXECUTION_MODEL="anthropic/claude-sonnet-4-20250514"
      CODING_MODEL="anthropic/claude-sonnet-4-20250514"
      apply_tier_models
      ;;
    3)
      REASONING_MODEL="openai/o3"
      EXECUTION_MODEL="openai/gpt-4.1"
      CODING_MODEL="openai/gpt-5.3-codex"
      apply_tier_models
      ;;
    4)
      REASONING_MODEL="google/gemini-2.5-pro"
      EXECUTION_MODEL="google/gemini-2.5-flash"
      CODING_MODEL="google/gemini-2.5-pro"
      apply_tier_models
      ;;
    5)
      REASONING_MODEL="anthropic/claude-sonnet-4-20250514"
      EXECUTION_MODEL="anthropic/claude-sonnet-4-20250514"
      CODING_MODEL="anthropic/claude-sonnet-4-20250514"
      apply_tier_models
      ;;
    6)
      custom_mode
      ;;
  esac
}

apply_tier_models() {
  local i

  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${REASONING_AGENTS[@]}"; then
      PROPOSED_MODELS[$i]="$REASONING_MODEL"
    elif in_array "${AGENTS[$i]}" "${EXECUTION_AGENTS[@]}"; then
      PROPOSED_MODELS[$i]="$EXECUTION_MODEL"
    else
      PROPOSED_MODELS[$i]="$CODING_MODEL"
    fi
  done
}

custom_mode() {
  local mode

  prompt_choice "Custom mode" \
    "Per-tier (pick 3 models)" \
    "Per-agent (pick all 7 individually)"
  mode="$CHOICE"

  if (( mode == 1 )); then
    choose_custom_tier_models
    apply_tier_models
  else
    choose_custom_agent_models
  fi
}

choose_custom_tier_models() {
  local model_options

  model_options=(
    "anthropic/claude-opus-4-6 (Recommended)"
    "anthropic/claude-sonnet-4-20250514"
    "openai/o3"
    "openai/o4-mini"
    "google/gemini-2.5-pro"
    "deepseek/deepseek-r1"
    "xai/grok-3"
    "mistral/mistral-large-latest"
    "meta/llama-4-maverick"
    "Enter custom model"
  )
  pick_from_model_list "Reasoning tier model" 10 "${model_options[@]}"
  REASONING_MODEL="${CHOICE%% (Recommended)}"

  model_options=(
    "anthropic/claude-sonnet-4-20250514 (Recommended)"
    "anthropic/claude-haiku-3-5-20241022"
    "openai/gpt-4.1"
    "openai/gpt-4.1-mini"
    "google/gemini-2.5-flash"
    "google/gemini-2.5-flash-lite"
    "deepseek/deepseek-chat"
    "xai/grok-3-mini"
    "mistral/mistral-small-latest"
    "meta/llama-4-scout"
    "Enter custom model"
  )
  pick_from_model_list "Execution tier model" 11 "${model_options[@]}"
  EXECUTION_MODEL="${CHOICE%% (Recommended)}"

  model_options=(
    "openai/gpt-5.3-codex (Recommended)"
    "anthropic/claude-sonnet-4-20250514"
    "anthropic/claude-opus-4-6"
    "openai/gpt-4.1"
    "google/gemini-2.5-pro"
    "deepseek/deepseek-chat"
    "mistral/codestral-latest"
    "qwen/qwen-3-coder"
    "Enter custom model"
  )
  pick_from_model_list "Coding tier model" 9 "${model_options[@]}"
  CODING_MODEL="${CHOICE%% (Recommended)}"
}

choose_custom_agent_models() {
  local all_models
  local i
  local agent
  local current
  local options=()
  local option

  all_models=(
    "anthropic/claude-opus-4-6"
    "anthropic/claude-sonnet-4-20250514"
    "anthropic/claude-haiku-3-5-20241022"
    "openai/o3"
    "openai/o4-mini"
    "openai/gpt-4.1"
    "openai/gpt-4.1-mini"
    "openai/gpt-5.3-codex"
    "google/gemini-2.5-pro"
    "google/gemini-2.5-flash"
    "google/gemini-2.5-flash-lite"
    "deepseek/deepseek-r1"
    "deepseek/deepseek-chat"
    "xai/grok-3"
    "xai/grok-3-mini"
    "mistral/mistral-large-latest"
    "mistral/mistral-small-latest"
    "mistral/codestral-latest"
    "meta/llama-4-maverick"
    "meta/llama-4-scout"
    "qwen/qwen-3-coder"
  )

  for i in "${!AGENTS[@]}"; do
    agent="${AGENTS[$i]}"
    current="${CURRENT_MODELS[$i]}"
    options=()

    printf "\n%b\n" "${BOLD}${agent}${NC} ${DIM}(current: ${current})${NC}"
    for option in "${all_models[@]}"; do
      if [[ "$option" == "$current" ]]; then
        options+=("$option (current)")
      else
        options+=("$option")
      fi
    done
    options+=("Enter custom model")

    prompt_choice "Select model for ${agent}" "${options[@]}"

    if (( CHOICE == ${#options[@]} )); then
      prompt_custom_model "$agent"
      PROPOSED_MODELS[$i]="$CHOICE"
    else
      option="${all_models[$((CHOICE - 1))]}"
      PROPOSED_MODELS[$i]="$option"
    fi
  done
}

show_confirmation() {
  local i
  local changes=0

  printf "\n%b\n" "${BOLD}Proposed Changes${NC}"
  printf "%b\n" "${DIM}================================================================${NC}"

  for i in "${!AGENTS[@]}"; do
    if [[ "${CURRENT_MODELS[$i]}" == "${PROPOSED_MODELS[$i]}" ]]; then
      printf "  %-12s  %s %b->%b %s\n" \
        "${AGENTS[$i]}" \
        "${CURRENT_MODELS[$i]}" \
        "${DIM}" \
        "${NC}" \
        "${PROPOSED_MODELS[$i]}"
    else
      changes=$((changes + 1))
      printf "  %-12s  %b%s%b %b->%b %b%s%b\n" \
        "${AGENTS[$i]}" \
        "${DIM}" \
        "${CURRENT_MODELS[$i]}" \
        "${NC}" \
        "${YELLOW}" \
        "${NC}" \
        "${GREEN}" \
        "${PROPOSED_MODELS[$i]}" \
        "${NC}"
    fi
  done

  printf "%b\n" "${DIM}================================================================${NC}"

  if (( changes == 0 )); then
    log_warn "No model changes selected."
    exit 0
  fi
}

backup_agents() {
  local backup_path
  backup_path="$AGENTS_DIR/.backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_path"
  cp "$AGENTS_DIR"/*.md "$backup_path/"
  BACKUP_PATH="$backup_path"
  log_success "Backup created: $BACKUP_PATH"
}

apply_changes() {
  local i
  local changed=0

  for i in "${!AGENTS[@]}"; do
    if [[ "${CURRENT_MODELS[$i]}" != "${PROPOSED_MODELS[$i]}" ]]; then
      set_model "${AGENTS[$i]}" "${PROPOSED_MODELS[$i]}"
      log_success "Updated ${AGENTS[$i]}: ${CURRENT_MODELS[$i]} -> ${PROPOSED_MODELS[$i]}"
      changed=$((changed + 1))
    fi
  done

  if (( changed == 0 )); then
    log_warn "No files were changed."
  fi
}

main() {
  local i
  local proceed
  local confirm

  show_banner
  verify_preflight

  CURRENT_MODELS=()
  PROPOSED_MODELS=()
  for i in "${!AGENTS[@]}"; do
    CURRENT_MODELS[$i]="$(get_current_model "${AGENTS[$i]}")"
    PROPOSED_MODELS[$i]="${CURRENT_MODELS[$i]}"
  done

  show_current_config

  printf "\nConfigure models? [Y/n] "
  read -r proceed <&3
  proceed="$(trim_whitespace "$proceed")"
  if [[ "$proceed" =~ ^[Nn]$ ]]; then
    printf "No changes made.\n"
    exit 0
  fi

  select_profile
  show_confirmation

  printf "\nApply these changes? [Y/n] "
  read -r confirm <&3
  confirm="$(trim_whitespace "$confirm")"
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    printf "No changes made.\n"
    exit 0
  fi

  backup_agents
  apply_changes

  printf "\n%b\n" "${GREEN}${BOLD}Done.${NC} Restart OpenCode to apply. Backup at: ${BACKUP_PATH}. To reconfigure, run this script again."
}

main "$@"
