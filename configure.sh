#!/usr/bin/env bash
set -euo pipefail

cleanup_term() {
  printf '\e[?25h' >&2
}
trap 'cleanup_term; printf "\n  \033[0;31mAborted. No changes made.\033[0m\n"; exit 1' INT TERM
trap 'cleanup_term' EXIT

{ exec 3</dev/tty; } 2>/dev/null || exec 3<&0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
BOLD_CYAN='\033[1;36m'
BOLD_GREEN='\033[1;32m'
BOLD_MAGENTA='\033[1;35m'
BOLD_YELLOW='\033[1;33m'
BOLD_WHITE='\033[1;37m'
GRAY='\033[38;5;245m'
DARK_GRAY='\033[38;5;240m'
WHITE='\033[0;37m'

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

log_info()    { printf "  %b\n" "${BLUE}ℹ${NC} $1" >&2; }
log_warn()    { printf "  %b\n" "${BOLD_YELLOW}⚠${NC} $1" >&2; }
log_success() { printf "  %b\n" "${BOLD_GREEN}✓${NC} $1" >&2; }
log_error()   { printf "  %b\n" "${RED}✗${NC} $1" >&2; }

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

arrow_select() {
  local title="$1"
  shift
  local options=("$@")
  local count=${#options[@]}
  local current=0
  local key
  local i

  printf "\n%b\n\n" "${BOLD_CYAN}  ${title}${NC}" >&2
  printf '\e[?25l' >&2

  for i in "${!options[@]}"; do
    if (( i == current )); then
      printf "%b\n" "  ${BOLD_CYAN}▸ ${options[$i]}${NC}" >&2
    else
      printf "%b\n" "  ${GRAY}  ${options[$i]}${NC}" >&2
    fi
  done

  while true; do
    IFS= read -rsn1 key <&3
    if [[ "$key" == $'\e' ]]; then
      IFS= read -rsn2 -t 1 key <&3 || true
      case "$key" in
        '[A'|'OA') { (( current > 0 )) && (( current-- )); } || true ;;
        '[B'|'OB') { (( current < count - 1 )) && (( current++ )); } || true ;;
      esac
    elif [[ "$key" == "" ]]; then
      break
    elif [[ "$key" == "k" ]]; then
      { (( current > 0 )) && (( current-- )); } || true
    elif [[ "$key" == "j" ]]; then
      { (( current < count - 1 )) && (( current++ )); } || true
    fi

    printf "\e[%dA" "$count" >&2
    for i in "${!options[@]}"; do
      printf '\e[2K' >&2
      if (( i == current )); then
        printf "%b\n" "  ${BOLD_CYAN}▸ ${options[$i]}${NC}" >&2
      else
        printf "%b\n" "  ${GRAY}  ${options[$i]}${NC}" >&2
      fi
    done
  done

  printf '\e[?25h' >&2
  CHOICE=$(( current + 1 ))
}

arrow_select_described() {
  local title="$1"
  shift
  local names=()
  local descs=()
  while (( $# >= 2 )); do
    names+=("$1")
    descs+=("$2")
    shift 2
  done
  local count=${#names[@]}
  local current=0
  local key
  local i
  local total_lines=$(( count * 2 ))

  printf "\n%b\n\n" "${BOLD_CYAN}  ${title}${NC}" >&2
  printf '\e[?25l' >&2

  for i in "${!names[@]}"; do
    if (( i == current )); then
      printf "%b\n" "  ${BOLD_CYAN}▸ ${names[$i]}${NC}" >&2
      printf "%b\n" "    ${CYAN}${descs[$i]}${NC}" >&2
    else
      printf "%b\n" "  ${GRAY}  ${names[$i]}${NC}" >&2
      printf "%b\n" "    ${DARK_GRAY}${descs[$i]}${NC}" >&2
    fi
  done

  while true; do
    IFS= read -rsn1 key <&3
    if [[ "$key" == $'\e' ]]; then
      IFS= read -rsn2 -t 1 key <&3 || true
      case "$key" in
        '[A'|'OA') { (( current > 0 )) && (( current-- )); } || true ;;
        '[B'|'OB') { (( current < count - 1 )) && (( current++ )); } || true ;;
      esac
    elif [[ "$key" == "" ]]; then
      break
    elif [[ "$key" == "k" ]]; then
      { (( current > 0 )) && (( current-- )); } || true
    elif [[ "$key" == "j" ]]; then
      { (( current < count - 1 )) && (( current++ )); } || true
    fi

    printf "\e[%dA" "$total_lines" >&2
    for i in "${!names[@]}"; do
      printf '\e[2K' >&2
      if (( i == current )); then
        printf "%b\n" "  ${BOLD_CYAN}▸ ${names[$i]}${NC}" >&2
      else
        printf "%b\n" "  ${GRAY}  ${names[$i]}${NC}" >&2
      fi
      printf '\e[2K' >&2
      if (( i == current )); then
        printf "%b\n" "    ${CYAN}${descs[$i]}${NC}" >&2
      else
        printf "%b\n" "    ${DARK_GRAY}${descs[$i]}${NC}" >&2
      fi
    done
  done

  printf '\e[?25h' >&2
  CHOICE=$(( current + 1 ))
}

styled_confirm() {
  local prompt_text="$1"
  local answer
  printf "\n%b %b " "  ${BOLD_CYAN}▸${NC} ${BOLD}${prompt_text}${NC}" "${DIM}[Y/n]${NC}" >&2
  read -r answer <&3
  answer="$(trim_whitespace "$answer")"
  [[ ! "$answer" =~ ^[Nn]$ ]]
}

prompt_custom_model() {
  local context="$1"
  local model_string
  while true; do
    printf "\n%b " "  ${BOLD_CYAN}▸${NC} ${BOLD}Enter custom model for ${context}${NC} ${DIM}(provider/model):${NC}" >&2
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

show_banner() {
  local title="OpenCode Orchestrator Configurator"
  local width=52
  local pad_total=$(( width - ${#title} - 2 ))
  local pad_left=$(( pad_total / 2 ))
  local pad_right=$(( pad_total - pad_left ))
  printf "\n"
  printf "  %b" "${BOLD_MAGENTA}╭"
  printf '─%.0s' $(seq 1 "$width")
  printf "╮${NC}\n"
  printf "  %b" "${BOLD_MAGENTA}│${NC}"
  printf "%*s" "$pad_left" ""
  printf " %b " "${BOLD_CYAN}${title}${NC}"
  printf "%*s" "$pad_right" ""
  printf "%b\n" "${BOLD_MAGENTA}│${NC}"
  printf "  %b" "${BOLD_MAGENTA}╰"
  printf '─%.0s' $(seq 1 "$width")
  printf "╯${NC}\n"
}

verify_preflight() {
  local agent

  if [[ ! -d "$AGENTS_DIR" ]]; then
    log_error "Expected agent directory not found: $AGENTS_DIR"
    log_info "Run install first: curl -fsSL https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchestrator/main/install.sh | bash"
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
  printf "\n%b\n" "  ${BOLD_WHITE}Current Model Configuration${NC}"
  printf "%b\n\n" "  ${DARK_GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"

  printf "  %b\n" "${BOLD_CYAN}Reasoning Tier${NC}"
  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${REASONING_AGENTS[@]}"; then
      printf "  ${GRAY}  %-12s${NC}  ${WHITE}%s${NC}\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    fi
  done

  printf "\n  %b\n" "${BOLD_CYAN}Execution Tier${NC}"
  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${EXECUTION_AGENTS[@]}"; then
      printf "  ${GRAY}  %-12s${NC}  ${WHITE}%s${NC}\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    fi
  done

  printf "\n  %b\n" "${BOLD_CYAN}Coding Tier${NC}"
  for i in "${!AGENTS[@]}"; do
    if in_array "${AGENTS[$i]}" "${CODING_AGENTS[@]}"; then
      printf "  ${GRAY}  %-12s${NC}  ${WHITE}%s${NC}\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    fi
  done

  printf "\n%b\n" "  ${DARK_GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
}

select_profile() {
  local profile
  arrow_select_described "Select a Model Profile" \
    "Recommended" "Opus reasoning · Sonnet execution · Codex coding" \
    "All Claude" "Opus reasoning · Sonnet execution · Sonnet coding" \
    "All OpenAI" "o3 reasoning · GPT-4.1 execution · Codex coding" \
    "All Google" "Gemini Pro reasoning · Flash execution · Pro coding" \
    "Budget" "Sonnet everywhere" \
    "Custom" "Choose per-tier or per-agent"
  profile="$CHOICE"
  case "$profile" in
    1)
      REASONING_MODEL="anthropic/claude-opus-4-6"
      EXECUTION_MODEL="anthropic/claude-sonnet-4-20250514"
      CODING_MODEL="openai/gpt-5.3-codex"
      apply_tier_models ;;
    2)
      REASONING_MODEL="anthropic/claude-opus-4-6"
      EXECUTION_MODEL="anthropic/claude-sonnet-4-20250514"
      CODING_MODEL="anthropic/claude-sonnet-4-20250514"
      apply_tier_models ;;
    3)
      REASONING_MODEL="openai/o3"
      EXECUTION_MODEL="openai/gpt-4.1"
      CODING_MODEL="openai/gpt-5.3-codex"
      apply_tier_models ;;
    4)
      REASONING_MODEL="google/gemini-2.5-pro"
      EXECUTION_MODEL="google/gemini-2.5-flash"
      CODING_MODEL="google/gemini-2.5-pro"
      apply_tier_models ;;
    5)
      REASONING_MODEL="anthropic/claude-sonnet-4-20250514"
      EXECUTION_MODEL="anthropic/claude-sonnet-4-20250514"
      CODING_MODEL="anthropic/claude-sonnet-4-20250514"
      apply_tier_models ;;
    6)
      custom_mode ;;
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
  arrow_select "Custom Configuration Mode" \
    "Per-tier  ─  Pick 3 models (reasoning, execution, coding)" \
    "Per-agent ─  Pick all 7 individually"
  mode="$CHOICE"
  if (( mode == 1 )); then
    choose_custom_tier_models
    apply_tier_models
  else
    choose_custom_agent_models
  fi
}

choose_custom_tier_models() {
  local model_options selected

  model_options=(
    "anthropic/claude-opus-4-6           (Recommended)"
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
  arrow_select "Reasoning Tier Model" "${model_options[@]}"
  selected="$CHOICE"
  if (( selected == ${#model_options[@]} )); then
    prompt_custom_model "reasoning tier"
    REASONING_MODEL="$CHOICE"
  else
    REASONING_MODEL="${model_options[$((selected - 1))]}"
    REASONING_MODEL="${REASONING_MODEL%% (*}"
    REASONING_MODEL="$(trim_whitespace "$REASONING_MODEL")"
  fi

  model_options=(
    "anthropic/claude-sonnet-4-20250514  (Recommended)"
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
  arrow_select "Execution Tier Model" "${model_options[@]}"
  selected="$CHOICE"
  if (( selected == ${#model_options[@]} )); then
    prompt_custom_model "execution tier"
    EXECUTION_MODEL="$CHOICE"
  else
    EXECUTION_MODEL="${model_options[$((selected - 1))]}"
    EXECUTION_MODEL="${EXECUTION_MODEL%% (*}"
    EXECUTION_MODEL="$(trim_whitespace "$EXECUTION_MODEL")"
  fi

  model_options=(
    "openai/gpt-5.3-codex                (Recommended)"
    "anthropic/claude-sonnet-4-20250514"
    "anthropic/claude-opus-4-6"
    "openai/gpt-4.1"
    "google/gemini-2.5-pro"
    "deepseek/deepseek-chat"
    "mistral/codestral-latest"
    "qwen/qwen-3-coder"
    "Enter custom model"
  )
  arrow_select "Coding Tier Model" "${model_options[@]}"
  selected="$CHOICE"
  if (( selected == ${#model_options[@]} )); then
    prompt_custom_model "coding tier"
    CODING_MODEL="$CHOICE"
  else
    CODING_MODEL="${model_options[$((selected - 1))]}"
    CODING_MODEL="${CODING_MODEL%% (*}"
    CODING_MODEL="$(trim_whitespace "$CODING_MODEL")"
  fi
}

choose_custom_agent_models() {
  local all_models i agent current options option selected

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

    for option in "${all_models[@]}"; do
      if [[ "$option" == "$current" ]]; then
        options+=("$option  (current)")
      else
        options+=("$option")
      fi
    done
    options+=("Enter custom model")

    arrow_select "${agent}  ${DIM}(current: ${current})${NC}" "${options[@]}"
    selected="$CHOICE"

    if (( selected == ${#options[@]} )); then
      prompt_custom_model "$agent"
      PROPOSED_MODELS[$i]="$CHOICE"
    else
      option="${all_models[$((selected - 1))]}"
      PROPOSED_MODELS[$i]="$option"
    fi
  done
}

show_confirmation() {
  local i changes=0

  printf "\n%b\n" "  ${BOLD_WHITE}Proposed Changes${NC}"
  printf "%b\n\n" "  ${DARK_GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"

  for i in "${!AGENTS[@]}"; do
    if [[ "${CURRENT_MODELS[$i]}" == "${PROPOSED_MODELS[$i]}" ]]; then
      printf "  ${GRAY}  %-12s  %s${NC}\n" "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}"
    else
      changes=$((changes + 1))
      printf "  ${WHITE}  %-12s${NC}  ${DIM}%s${NC} ${BOLD_YELLOW}→${NC} ${BOLD_GREEN}%s${NC}\n" \
        "${AGENTS[$i]}" "${CURRENT_MODELS[$i]}" "${PROPOSED_MODELS[$i]}"
    fi
  done

  printf "\n%b\n" "  ${DARK_GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"

  if (( changes == 0 )); then
    log_warn "No model changes selected."
    exit 0
  fi

  printf "\n  %b\n" "${DIM}${changes} agent(s) will be updated${NC}"
}

backup_agents() {
  local backup_path
  backup_path="$CONFIG_DIR/backups/.backup-$(date +%Y%m%d-%H%M%S)"
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
  show_banner
  verify_preflight

  CURRENT_MODELS=()
  PROPOSED_MODELS=()
  for i in "${!AGENTS[@]}"; do
    CURRENT_MODELS[$i]="$(get_current_model "${AGENTS[$i]}")"
    PROPOSED_MODELS[$i]="${CURRENT_MODELS[$i]}"
  done

  show_current_config

  if ! styled_confirm "Configure models?"; then
    printf "\n  No changes made.\n"
    exit 0
  fi

  select_profile
  show_confirmation

  if ! styled_confirm "Apply these changes?"; then
    printf "\n  No changes made.\n"
    exit 0
  fi

  backup_agents
  apply_changes

  printf "\n  %b\n\n" "${BOLD_GREEN}✓ Done.${NC} Restart OpenCode to apply. Backup at: ${DIM}${BACKUP_PATH}${NC}"
}

main "$@"
