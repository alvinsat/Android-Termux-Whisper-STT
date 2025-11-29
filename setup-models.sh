#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ----------------------------------------
# Config - keep consistent with other scripts
# ----------------------------------------
PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="$HOME"

WHISPER_DIR="$HOME_DIR/whisper.cpp"
MODELS_DIR="$WHISPER_DIR/models"
ACTIVE_MODEL_FILE="$WHISPER_DIR/.active-model"

# Global array for models
MODELS=()

# ----------------------------------------
# Helpers
# ----------------------------------------

ensure_dirs() {
    mkdir -p "$MODELS_DIR"
}

# Load all model files into a global array MODELS[]
reload_models() {
    shopt -s nullglob
    MODELS=( "$MODELS_DIR"/*.bin "$MODELS_DIR"/*.gguf )
    shopt -u nullglob
}

# Return 0 if given path is considered a "tiny" model (protected from delete)
is_tiny_model() {
    local path="$1"
    local base
    base="$(basename "$path")"
    [[ "$base" == *tiny* ]]
}

# Echo full path of default tiny model; return 0 if found, 1 if not
get_default_tiny_model() {
    reload_models
    for m in "${MODELS[@]}"; do
        if is_tiny_model "$m"; then
            printf '%s\n' "$m"
            return 0
        fi
    done
    return 1
}

# Ensure ACTIVE_MODEL_FILE points to a valid model.
# If not, fall back to tiny; if no tiny, fall back to first found model.
ensure_active_model() {
    reload_models

    # No models at all
    if [ "${#MODELS[@]}" -eq 0 ]; then
        echo "❌ No models found in: $MODELS_DIR"
        echo "   Run whisper-model-picker.sh to download at least the tiny model."
        exit 1
    fi

    local active_name=""
    if [ -f "$ACTIVE_MODEL_FILE" ]; then
        active_name="$(cat "$ACTIVE_MODEL_FILE" 2>/dev/null || true)"
    fi

    if [ -n "$active_name" ] && [ -f "$MODELS_DIR/$active_name" ]; then
        # Active model is valid, nothing to do
        return 0
    fi

    # Try to use tiny as fallback
    local tiny_path=""
    if tiny_path="$(get_default_tiny_model)"; then
        local tiny_base
        tiny_base="$(basename "$tiny_path")"
        echo "$tiny_base" > "$ACTIVE_MODEL_FILE"
        echo "ℹ️ Active model reset to tiny: $tiny_base"
        return 0
    fi

    # No tiny model; fall back to first model file
    local first
    first="$(basename "${MODELS[0]}")"
    echo "$first" > "$ACTIVE_MODEL_FILE"
    echo "⚠️ No tiny model found. Active model set to first available: $first"
}

get_current_active_name() {
    if [ -f "$ACTIVE_MODEL_FILE" ]; then
        cat "$ACTIVE_MODEL_FILE" 2>/dev/null || true
    else
        echo ""
    fi
}

# ----------------------------------------
# UI Actions
# ----------------------------------------

show_current_active() {
    ensure_active_model
    local active_name
    active_name="$(get_current_active_name)"

    if [ -z "$active_name" ]; then
        echo "No active model set."
        return
    fi

    echo "Current active model:"
    echo "  Name : $active_name"
    echo "  Path : $MODELS_DIR/$active_name"
}

select_active_model() {
    ensure_active_model
    reload_models

    if [ "${#MODELS[@]}" -eq 0 ]; then
        echo "❌ No models found in $MODELS_DIR"
        return
    fi

    local active_name
    active_name="$(get_current_active_name)"

    echo "Available models in: $MODELS_DIR"
    echo

    local i=1
    for m in "${MODELS[@]}"; do
        local base
        base="$(basename "$m")"
        if [ "$base" = "$active_name" ]; then
            echo "  $i) $base  [active]"
        else
            echo "  $i) $base"
        fi
        i=$((i + 1))
    done

    echo
    read -rp "Select model number to set active (or press Enter to cancel): " choice || true
    if [ -z "${choice:-}" ]; then
        echo "Cancelled."
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid choice."
        return
    fi

    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#MODELS[@]}" ]; then
        echo "❌ Choice out of range."
        return
    fi

    local selected="${MODELS[$idx]}"
    local selected_base
    selected_base="$(basename "$selected")"

    echo "$selected_base" > "$ACTIVE_MODEL_FILE"
    echo "✅ Active model set to: $selected_base"
}

delete_models_menu() {
    ensure_active_model
    reload_models

    if [ "${#MODELS[@]}" -eq 0 ]; then
        echo "❌ No models found in $MODELS_DIR"
        return
    fi

    # Build list of deletable models (non-tiny)
    local DELETABLE=()
    local M
    for M in "${MODELS[@]}"; do
        if is_tiny_model "$M"; then
            continue
        fi
        DELETABLE+=( "$M" )
    done

    if [ "${#DELETABLE[@]}" -eq 0 ]; then
        echo "Nothing to delete. Only tiny model(s) exist, which are protected."
        return
    fi

    echo "Delete downloaded models (tiny models are protected and cannot be deleted)."
    echo "Models that CAN be deleted:"
    echo

    local i=1
    local base
    for M in "${DELETABLE[@]}"; do
        base="$(basename "$M")"
        echo "  $i) $base"
        i=$((i + 1))
    done
    echo "  0) Cancel"
    echo

    read -rp "Select model number to delete: " choice || true

    if [ -z "${choice:-}" ] || [ "$choice" = "0" ]; then
        echo "Cancelled."
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid choice."
        return
    fi

    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#DELETABLE[@]}" ]; then
        echo "❌ Choice out of range."
        return
    fi

    local target="${DELETABLE[$idx]}"
    local target_base
    target_base="$(basename "$target")"

    # Double-check it's not tiny (safety)
    if is_tiny_model "$target"; then
        echo "❌ Tiny model is protected and cannot be deleted."
        return
    fi

    echo "You are about to delete: $target_base"
    read -rp "Type 'yes' to confirm: " confirm || true

    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        return
    fi

    rm -f -- "$target"
    echo "🗑  Deleted: $target_base"

    # If deleted model was the active one, refresh active model (fallback to tiny)
    local active_name
    active_name="$(get_current_active_name)"
    if [ "$active_name" = "$target_base" ]; then
        echo "ℹ️ Deleted model was active. Resetting active model..."
        ensure_active_model
    fi
}

main_menu() {
    ensure_dirs
    ensure_active_model

    while true; do
        local active
        active="$(get_current_active_name)"
        echo
        echo "========== Whisper Model Setup =========="
        echo "Models directory: $MODELS_DIR"
        echo "Active model    : ${active:-'(none)'}"
        echo "-----------------------------------------"
        echo "  1) Select active model"
        echo "  2) Delete downloaded models"
        echo "  3) Show current active model"
        echo "  4) Exit"
        echo "-----------------------------------------"
        read -rp "Choose an option [1-4]: " choice || true

        case "${choice:-}" in
            1) select_active_model ;;
            2) delete_models_menu ;;
            3) show_current_active ;;
            4) echo "Bye."; exit 0 ;;
            *) echo "Invalid choice."; ;;
        esac
    done
}

# ----------------------------------------
# Entry
# ----------------------------------------
main_menu
