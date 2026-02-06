#!/bin/bash
#
# Setup script for Voxtral on-device transcription
# Requires: macOS with Apple Silicon (M1/M2/M3), Python 3.10+
#

set -e

echo "🎙️ Setting up Voxtral for DailyBriefing..."
echo ""

# Check for Apple Silicon
if [[ $(uname -m) != "arm64" ]]; then
    echo "❌ Error: Voxtral requires Apple Silicon (M1/M2/M3)"
    echo "   Your architecture: $(uname -m)"
    exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 not found"
    echo "   Install with: brew install python@3.11"
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "✓ Python $PYTHON_VERSION found"

# Create virtual environment (optional but recommended)
VENV_DIR="$HOME/.dailybriefing/voxtral-env"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"

# Install dependencies
echo "📦 Installing mlx-voxtral..."
pip install --upgrade pip
pip install mlx-voxtral

# Install transformers from GitHub (required for tokenizer)
pip install git+https://github.com/huggingface/transformers

echo ""
echo "📥 Pre-downloading model (this may take a few minutes)..."
python3 -c "
from mlx_voxtral import VoxtralForConditionalGeneration, VoxtralProcessor
import mlx.core as mx

model_id = 'mzbac/voxtral-mini-3b-4bit-mixed'
print(f'Downloading {model_id}...')

model = VoxtralForConditionalGeneration.from_pretrained(model_id, dtype=mx.bfloat16)
processor = VoxtralProcessor.from_pretrained(model_id)

print('✓ Model downloaded and cached')
"

echo ""
echo "✅ Voxtral setup complete!"
echo ""
echo "To start the transcription server manually:"
echo "  source $VENV_DIR/bin/activate"
echo "  python3 DailyBriefing/Resources/voxtral_server.py"
echo ""
echo "The app will start the server automatically when needed."
