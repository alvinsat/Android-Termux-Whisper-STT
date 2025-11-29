#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

echo "========================================="
echo "  Whisper.cpp Model Picker (Termux)"
echo "========================================="

WHISPER_ROOT="${HOME}/whisper.cpp"
MODELS_DIR="${WHISPER_ROOT}/models"
HELPER_SCRIPT="${MODELS_DIR}/download-ggml-model.sh"

# -----------------------------
# Basic checks
# -----------------------------
if [ ! -d "${WHISPER_ROOT}" ]; then
    echo "ERROR: whisper.cpp repo not found at: ${WHISPER_ROOT}"
    echo "Run your main setup script first to clone and build whisper.cpp."
    exit 1
fi

if [ ! -d "${MODELS_DIR}" ]; then
    echo "Models directory not found at: ${MODELS_DIR}"
    echo "Creating models directory..."
    mkdir -p "${MODELS_DIR}"
fi

if [ ! -f "${HELPER_SCRIPT}" ]; then
    echo "ERROR: download-ggml-model.sh not found at: ${HELPER_SCRIPT}"
    echo "Make sure you're using the official whisper.cpp repo."
    exit 1
fi

# -----------------------------
# Detect existing models
# -----------------------------
STATUS_TINY="[ ]"
STATUS_BASE="[ ]"
STATUS_SMALL="[ ]"
STATUS_MEDIUM="[ ]"
STATUS_LARGE_V3="[ ]"
STATUS_TINY_EN="[ ]"

[ -f "${MODELS_DIR}/ggml-tiny.bin" ]       && STATUS_TINY="[✓]"
[ -f "${MODELS_DIR}/ggml-base.bin" ]       && STATUS_BASE="[✓]"
[ -f "${MODELS_DIR}/ggml-small.bin" ]      && STATUS_SMALL="[✓]"
[ -f "${MODELS_DIR}/ggml-medium.bin" ]     && STATUS_MEDIUM="[✓]"
[ -f "${MODELS_DIR}/ggml-large-v3.bin" ]   && STATUS_LARGE_V3="[✓]"
[ -f "${MODELS_DIR}/ggml-tiny.en.bin" ]    && STATUS_TINY_EN="[✓]"

# -----------------------------
# Menu
# -----------------------------
echo ""
echo "Available Whisper models:"
echo ""
echo "  1) ${STATUS_TINY}     tiny      ~77 MB    speed: ⚡ fastest   accuracy: low         lang: multilingual"
echo "  2) ${STATUS_BASE}     base      ~145 MB   speed: fast        accuracy: medium      lang: multilingual"
echo "  3) ${STATUS_SMALL}    small     ~466 MB   speed: medium      accuracy: high        lang: multilingual"
echo "  4) ${STATUS_MEDIUM}   medium    ~1.5 GB   speed: slow        accuracy: very high   lang: multilingual"
echo "  5) ${STATUS_LARGE_V3} large-v3  ~2.9 GB   speed: very slow   accuracy: SOTA        lang: multilingual"
echo "  6) ${STATUS_TINY_EN}  tiny.en   ~77 MB    speed: ⚡ fastest   accuracy: low         lang: English only"
echo ""
echo "  0) Exit"
echo ""

read -rp "Select a model to download [0-6]: " choice

MODEL_ID=""
MODEL_FILE=""
SIZE=""
SPEED=""
ACC=""
LANG=""

case "${choice}" in
    1)
        MODEL_ID="tiny"
        MODEL_FILE="ggml-tiny.bin"
        SIZE="~77 MB"
        SPEED="⚡ fastest"
        ACC="low"
        LANG="multilingual"
        ;;
    2)
        MODEL_ID="base"
        MODEL_FILE="ggml-base.bin"
        SIZE="~145 MB"
        SPEED="fast"
        ACC="medium"
        LANG="multilingual"
        ;;
    3)
        MODEL_ID="small"
        MODEL_FILE="ggml-small.bin"
        SIZE="~466 MB"
        SPEED="medium"
        ACC="high"
        LANG="multilingual"
        ;;
    4)
        MODEL_ID="medium"
        MODEL_FILE="ggml-medium.bin"
        SIZE="~1.5 GB"
        SPEED="slow"
        ACC="very high"
        LANG="multilingual"
        ;;
    5)
        MODEL_ID="large-v3"
        MODEL_FILE="ggml-large-v3.bin"
        SIZE="~2.9 GB"
        SPEED="very slow"
        ACC="SOTA"
        LANG="multilingual"
        ;;
    6)
        MODEL_ID="tiny.en"
        MODEL_FILE="ggml-tiny.en.bin"
        SIZE="~77 MB"
        SPEED="⚡ fastest"
        ACC="low"
        LANG="English only"
        ;;
    0)
        echo "Exiting without downloading."
        exit 0
        ;;
    *)
        echo "Invalid choice: ${choice}"
        exit 1
        ;;
esac

echo ""
echo "You chose:"
echo "  ID:       ${MODEL_ID}"
echo "  File:     ${MODEL_FILE}"
echo "  Size:     ${SIZE}"
echo "  Speed:    ${SPEED}"
echo "  Accuracy: ${ACC}"
echo "  Lang:     ${LANG}"
echo ""

read -rp "Download this model now? [y/N]: " confirm
case "${confirm}" in
    y|Y)
        ;;
    *)
        echo "Cancelled by user."
        exit 0
        ;;
esac

# -----------------------------
# Download
# -----------------------------
cd "${MODELS_DIR}"

echo ""
echo "Downloading model '${MODEL_ID}' using download-ggml-model.sh ..."
sh "${HELPER_SCRIPT}" "${MODEL_ID}"

echo ""
if [ -f "${MODEL_FILE}" ]; then
    echo "✅ Download complete."
    echo ""
    echo "Model file path:"
    echo "  ${MODELS_DIR}/${MODEL_FILE}"
    echo ""
    echo "To use this with your whisper-realtime script:"
    echo ""
    echo "  export WHISPER_MODEL=\"${MODELS_DIR}/${MODEL_FILE}\""
    echo "  whisper-realtime"
    echo ""
    echo "Or one-shot:"
    echo ""
    echo "  WHISPER_MODEL=\"${MODELS_DIR}/${MODEL_FILE}\" whisper-realtime"
    echo ""
else
    echo "⚠️  Download script finished, but model file not found:"
    echo "    ${MODELS_DIR}/${MODEL_FILE}"
    echo "Check the output of download-ggml-model.sh above for errors."
    exit 1
fi
