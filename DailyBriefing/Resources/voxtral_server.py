#!/usr/bin/env python3
"""
Voxtral Local Transcription Server
Runs on-device using MLX for Apple Silicon optimization.
Communicates with DailyBriefing via local HTTP.
"""

import asyncio
import json
import sys
import os
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import threading
import tempfile
import time

# Check for MLX availability
try:
    import mlx.core as mx
    from mlx_voxtral import VoxtralForConditionalGeneration, VoxtralProcessor
    MLX_AVAILABLE = True
except ImportError:
    MLX_AVAILABLE = False
    print("Warning: mlx-voxtral not installed. Run: pip install mlx-voxtral", file=sys.stderr)

# Configuration
DEFAULT_PORT = 8473
MODEL_ID = "mzbac/voxtral-mini-3b-4bit-mixed"  # Quantized for efficiency
CACHE_DIR = Path.home() / ".cache" / "dailybriefing" / "voxtral"

# Global model instance (loaded once)
model = None
processor = None
model_lock = threading.Lock()


def load_model():
    """Load Voxtral model (lazy loading on first request)."""
    global model, processor
    
    if not MLX_AVAILABLE:
        raise RuntimeError("mlx-voxtral not installed")
    
    with model_lock:
        if model is None:
            print(f"Loading Voxtral model: {MODEL_ID}...")
            start = time.time()
            
            # Ensure cache directory exists
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            
            # Load model and processor
            model = VoxtralForConditionalGeneration.from_pretrained(
                MODEL_ID,
                dtype=mx.bfloat16
            )
            processor = VoxtralProcessor.from_pretrained(MODEL_ID)
            
            print(f"Model loaded in {time.time() - start:.1f}s")
    
    return model, processor


def transcribe_audio(audio_path: str, language: str = "de") -> dict:
    """
    Transcribe audio file using Voxtral.
    
    Returns:
        {
            "text": "transcribed text",
            "segments": [{"start": 0.0, "end": 1.5, "text": "..."}],
            "language": "de",
            "duration": 45.2
        }
    """
    m, p = load_model()
    
    start_time = time.time()
    
    # Prepare inputs
    inputs = p.apply_transcrition_request(
        language=language,
        audio=audio_path
    )
    
    # Generate transcription
    outputs = m.generate(
        **inputs,
        max_new_tokens=2048,
        temperature=0.0
    )
    
    # Decode
    text = p.decode(
        outputs[0][inputs.input_ids.shape[1]:],
        skip_special_tokens=True
    )
    
    processing_time = time.time() - start_time
    
    return {
        "text": text.strip(),
        "language": language,
        "processing_time": processing_time,
        "model": MODEL_ID
    }


class VoxtralHandler(BaseHTTPRequestHandler):
    """HTTP handler for transcription requests."""
    
    def log_message(self, format, *args):
        """Suppress default logging."""
        pass
    
    def send_json(self, data: dict, status: int = 200):
        """Send JSON response."""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        
        if parsed.path == "/health":
            self.send_json({
                "status": "ok",
                "mlx_available": MLX_AVAILABLE,
                "model_loaded": model is not None,
                "model_id": MODEL_ID
            })
        
        elif parsed.path == "/status":
            self.send_json({
                "ready": model is not None,
                "model": MODEL_ID,
                "mlx_available": MLX_AVAILABLE
            })
        
        else:
            self.send_json({"error": "Not found"}, 404)
    
    def do_POST(self):
        """Handle POST requests."""
        parsed = urlparse(self.path)
        
        if parsed.path == "/transcribe":
            self.handle_transcribe()
        
        elif parsed.path == "/load":
            self.handle_load_model()
        
        else:
            self.send_json({"error": "Not found"}, 404)
    
    def handle_load_model(self):
        """Pre-load model without transcribing."""
        try:
            load_model()
            self.send_json({"status": "loaded", "model": MODEL_ID})
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
    
    def handle_transcribe(self):
        """Handle transcription request."""
        try:
            # Read request body
            content_length = int(self.headers.get("Content-Length", 0))
            
            if content_length == 0:
                self.send_json({"error": "No audio data"}, 400)
                return
            
            # Get language from query params
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            language = params.get("language", ["de"])[0]
            
            # Save audio to temp file
            audio_data = self.rfile.read(content_length)
            
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                f.write(audio_data)
                temp_path = f.name
            
            try:
                # Transcribe
                result = transcribe_audio(temp_path, language)
                self.send_json(result)
            finally:
                # Cleanup temp file
                os.unlink(temp_path)
        
        except Exception as e:
            self.send_json({"error": str(e)}, 500)


def run_server(port: int = DEFAULT_PORT):
    """Run the transcription server."""
    server = HTTPServer(("127.0.0.1", port), VoxtralHandler)
    print(f"Voxtral server running on http://127.0.0.1:{port}")
    print(f"Model: {MODEL_ID}")
    print(f"MLX available: {MLX_AVAILABLE}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Voxtral Local Transcription Server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to listen on")
    parser.add_argument("--preload", action="store_true", help="Pre-load model on startup")
    
    args = parser.parse_args()
    
    if args.preload and MLX_AVAILABLE:
        print("Pre-loading model...")
        load_model()
    
    run_server(args.port)
