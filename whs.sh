#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

echo "========================================="
echo "  Whisper.cpp + Realtime Mic on Termux"
echo "========================================="

PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="$HOME"

# -----------------------------
# 1. Install Termux packages
# -----------------------------
echo "[1/6] Updating packages..."
pkg update -y >/dev/null
pkg upgrade -y >/dev/null || true

echo "[2/6] Installing dependencies (clang, cmake, git, make, ffmpeg, termux-api)..."
pkg install -y clang cmake git make ffmpeg termux-api >/dev/null

# -----------------------------
# 2. Clone whisper.cpp
# -----------------------------
WHISPER_DIR="$HOME_DIR/whisper.cpp"

echo "[3/6] Cloning whisper.cpp (if needed)..."
if [ -d "$WHISPER_DIR" ]; then
    echo "  - Repo already exists at $WHISPER_DIR, skipping clone."
else
    git clone https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi

# -----------------------------
# 3. Build whisper.cpp (whisper-cli)
# -----------------------------
echo "[4/6] Building whisper.cpp..."
cd "$WHISPER_DIR"

mkdir -p build
cd build

# Configure and build
cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null
cmake --build . -j"$(nproc)" --config Release >/dev/null

WHISPER_BIN="$WHISPER_DIR/build/bin/whisper-cli"

if [ ! -x "$WHISPER_BIN" ]; then
    echo "ERROR: whisper-cli binary not found at $WHISPER_BIN"
    exit 1
fi

echo "  - Built: $WHISPER_BIN"

# -----------------------------
# 4. Download tiny.en model
# -----------------------------
echo "[5/6] Downloading tiny.en model (if needed)..."
cd "$WHISPER_DIR/models"

# Use official whisper.cpp model download helper
if [ ! -f "ggml-tiny.en.bin" ]; then
    sh ./download-ggml-model.sh tiny.en
else
    echo "  - ggml-tiny.en.bin already exists, skipping download."
fi

MODEL_PATH="$WHISPER_DIR/models/ggml-tiny.en.bin"
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model ggml-tiny.en.bin not found after download."
    exit 1
fi

echo "  - Model ready: $MODEL_PATH"

# -----------------------------
# 5. Ensure ~/bin in PATH (no duplicates)
# -----------------------------
echo "[6/6] Ensuring \$HOME/bin is in PATH (without duplicates)..."
BIN_DIR="$HOME_DIR/bin"
mkdir -p "$BIN_DIR"

SHELL_RC="$HOME_DIR/.bashrc"

if [ -f "$SHELL_RC" ]; then
    if grep -q 'export PATH="$HOME/bin:$PATH"' "$SHELL_RC"; then
        echo "  - \$HOME/bin already in PATH in .bashrc."
    else
        echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
        echo "  - Added \$HOME/bin to PATH in .bashrc."
    fi
else
    echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
    echo "  - Created .bashrc and added \$HOME/bin to PATH."
fi

# -----------------------------
# 6. Create realtime mic script
# -----------------------------
REALTIME_SCRIPT="$BIN_DIR/whisper-realtime"

echo "Creating realtime mic script at: $REALTIME_SCRIPT"

cat > "$REALTIME_SCRIPT" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

WHISPER_ROOT="$HOME/whisper.cpp"
WHISPER_BIN="$WHISPER_ROOT/build/bin/whisper-cli"
MODEL_PATH="${WHISPER_MODEL:-$WHISPER_ROOT/models/ggml-tiny.en.bin}"

if [ ! -x "$WHISPER_BIN" ]; then
    echo "whisper-cli binary not found at: $WHISPER_BIN"
    echo "Make sure whisper.cpp is built."
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "Model not found at: $MODEL_PATH"
    echo "Set WHISPER_MODEL or re-run setup."
    exit 1
fi

if ! command -v termux-microphone-record >/dev/null 2>&1; then
    echo "termux-microphone-record not found."
    echo "Install Termux:API app and 'pkg install termux-api' in Termux."
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg not found. Install with: pkg install ffmpeg"
    exit 1
fi

CHUNK_SEC="${1:-4}"   # seconds per chunk (default 4s)
WORKDIR="$HOME/.cache/whisper-mic"
mkdir -p "$WORKDIR"

echo "============================================"
echo "  Whisper Realtime (chunked) Mic Loop"
echo "--------------------------------------------"
echo "Model:      $MODEL_PATH"
echo "Chunk size: ${CHUNK_SEC}s"
echo "Workdir:    $WORKDIR"
echo ""
echo "Make sure Termux:API app has microphone permission."
echo "Press Ctrl + C to stop."
echo "============================================"

i=0
while true; do
    RAW_FILE="$WORKDIR/chunk_${i}.amr"
    WAV_FILE="$WORKDIR/chunk_${i}.wav"
    OUT_PREFIX="$WORKDIR/chunk_${i}"

    # Clean old files for this index
    rm -f "$RAW_FILE" "$WAV_FILE" "${OUT_PREFIX}.txt" "${OUT_PREFIX}.srt" "${OUT_PREFIX}.vtt" 2>/dev/null || true

    echo ""
    echo "[Chunk $i] Recording ${CHUNK_SEC}s..."
    termux-microphone-record -l "$CHUNK_SEC" -f "$RAW_FILE"

    if [ ! -f "$RAW_FILE" ]; then
        echo "[Chunk $i] No audio file recorded, skipping."
        i=$((i+1))
        continue
    fi

    echo "[Chunk $i] Converting to 16k mono WAV..."
    ffmpeg -hide_banner -loglevel error -y -i "$RAW_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE"

    if [ ! -f "$WAV_FILE" ]; then
        echo "[Chunk $i] Failed to convert audio to WAV, skipping."
        i=$((i+1))
        continue
    fi

    echo "[Chunk $i] Transcribing with whisper.cpp..."
    "$WHISPER_BIN" \
        -m "$MODEL_PATH" \
        -f "$WAV_FILE" \
        -l auto \
        -nt \
        -of "$OUT_PREFIX" \
        -otxt \
        -t "$(nproc)" \
        >/dev/null

    if [ -f "${OUT_PREFIX}.txt" ]; then
        TEXT_OUT="$(cat "${OUT_PREFIX}.txt" | tr '\n' ' ' | sed 's/  */ /g')"
        if [ -n "$TEXT_OUT" ]; then
            # Print result clearly
            echo "[Chunk $i] >>> $TEXT_OUT"
        else
            echo "[Chunk $i] (no speech / empty result)"
        fi
    else
        echo "[Chunk $i] No transcription file produced."
    fi

    i=$((i+1))
done
EOF

chmod +x "$REALTIME_SCRIPT"

echo ""
echo "========================================="
echo " Setup complete!"
echo ""
echo "To start realtime (chunked) mic recognition, run:"
echo ""
echo "  source ~/.bashrc   # once, so \$HOME/bin is in PATH (or restart Termux)"
echo "  whisper-realtime        # default 4s chunks"
echo "  whisper-realtime 2      # faster, 2s chunks"
echo ""
echo "Note:"
echo " - Install the Termux:API app from Play Store / F-Droid"
echo " - Grant microphone permission when prompted."
echo "========================================="
