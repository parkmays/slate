#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import traceback
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock
from typing import Any


@dataclass
class BridgeConfig:
    model_id: str
    host: str
    port: int
    enable_thinking: bool
    max_new_tokens: int

    @classmethod
    def from_env(cls) -> "BridgeConfig":
        return cls(
            model_id=os.environ.get("SLATE_GEMMA_MODEL_ID", "google/gemma-4-E2B-it"),
            host=os.environ.get("SLATE_GEMMA_HOST", "127.0.0.1"),
            port=int(os.environ.get("SLATE_GEMMA_PORT", "8797")),
            enable_thinking=_parse_bool(os.environ.get("SLATE_GEMMA_ENABLE_THINKING")),
            max_new_tokens=int(os.environ.get("SLATE_GEMMA_MAX_NEW_TOKENS", "384")),
        )


def _parse_bool(raw: str | None) -> bool:
    if raw is None:
        return False
    return raw.strip().lower() in {"1", "true", "yes", "on"}


class GemmaRuntime:
    def __init__(self, config: BridgeConfig) -> None:
        self.config = config
        self._lock = Lock()
        self._processor = None
        self._model = None
        self._torch = None

    def health(self) -> dict[str, Any]:
        return {
            "ok": True,
            "model_id": self.config.model_id,
            "model_loaded": self._model is not None,
            "thinking_enabled": self.config.enable_thinking,
        }

    def generate_performance_insight(self, payload: dict[str, Any]) -> dict[str, Any]:
        transcript_text = str(payload.get("transcript_text") or "").strip()
        if not transcript_text:
            raise ValueError("transcript_text is required")

        self._ensure_model_loaded()

        metrics = payload.get("metrics") or {}
        heuristic_score = payload.get("heuristic_score")
        word_count = payload.get("word_count") or 0
        script_text = str(payload.get("script_text") or "").strip()

        system_prompt = (
            "You are a film dailies performance analysis assistant. "
            "Return strict JSON only. Do not use markdown. "
            "Focus on pacing, clarity, hesitation, energy, and emotional continuity. "
            "The transcript may be imperfect or approximate, so avoid overly literal word-level judgments."
        )
        user_prompt = "\n".join(
            [
                "Review this narrative take and return JSON with the shape:",
                '{"score": 0-100, "reasons": [{"dimension": "performance", "score": 0-100, "flag": "info|warning|error", "message": "...", "timecode": null}]}',
                "Rules:",
                "- Keep reasons to at most 3.",
                "- Use dimension=performance.",
                "- If uncertain, stay close to the heuristic score.",
                "- Mention only material strengths or risks.",
                "",
                f"Heuristic score: {heuristic_score}",
                f"Word count: {word_count}",
                f"Total duration (s): {metrics.get('total_duration')}",
                f"Speech coverage: {metrics.get('speech_coverage')}",
                f"Average phrase duration (s): {metrics.get('average_phrase_duration')}",
                f"Average pause duration (s): {metrics.get('average_pause_duration')}",
                f"Phrase duration variance: {metrics.get('phrase_duration_variance')}",
                f"Words per second: {metrics.get('words_per_second')}",
                "",
                "Script context:",
                script_text[:8000] if script_text else "(none provided)",
                "",
                "Transcript:",
                transcript_text[:20000],
            ]
        )

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        processor = self._processor
        model = self._model
        torch = self._torch

        try:
            prompt = processor.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=self.config.enable_thinking,
            )
        except TypeError:
            prompt = processor.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True,
            )

        inputs = processor(text=prompt, return_tensors="pt").to(model.device)
        input_len = inputs["input_ids"].shape[-1]

        with torch.inference_mode():
            outputs = model.generate(**inputs, max_new_tokens=self.config.max_new_tokens)

        decoded = processor.decode(outputs[0][input_len:], skip_special_tokens=False)
        parsed = processor.parse_response(decoded)
        raw_text = _extract_text(parsed) or _extract_text(decoded)
        response_json = _extract_json(raw_text)

        score = _normalize_score(response_json.get("score"))
        reasons = [
            normalized
            for normalized in (_normalize_reason(item) for item in response_json.get("reasons", []))
            if normalized is not None
        ][:3]

        if not reasons:
            reasons = [
                {
                    "dimension": "performance",
                    "score": score,
                    "flag": "info",
                    "message": "Gemma found the narrative delivery broadly aligned with the supplied pacing metrics.",
                    "timecode": None,
                }
            ]

        return {
            "model_version": self.config.model_id,
            "score": score,
            "reasons": reasons,
        }

    def _ensure_model_loaded(self) -> None:
        if self._model is not None and self._processor is not None and self._torch is not None:
            return

        with self._lock:
            if self._model is not None and self._processor is not None and self._torch is not None:
                return

            from transformers import AutoModelForCausalLM, AutoProcessor
            import torch

            self._processor = AutoProcessor.from_pretrained(self.config.model_id)
            self._model = AutoModelForCausalLM.from_pretrained(
                self.config.model_id,
                dtype="auto",
                device_map="auto",
            )
            self._model.eval()
            self._torch = torch


def _extract_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(part for part in (_extract_text(item) for item in value) if part)
    if isinstance(value, dict):
        for key in ("text", "output_text", "content", "response", "answer"):
            if key in value:
                candidate = _extract_text(value[key])
                if candidate:
                    return candidate
        return "\n".join(part for part in (_extract_text(item) for item in value.values()) if part)
    return str(value)


def _extract_json(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = stripped.strip("`")
        stripped = stripped.replace("json\n", "", 1).strip()

    start = stripped.find("{")
    end = stripped.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise ValueError(f"Model did not return JSON: {stripped[:240]}")

    return json.loads(stripped[start : end + 1])


def _normalize_score(value: Any) -> float | None:
    try:
        if value is None:
            return None
        score = float(value)
    except (TypeError, ValueError):
        return None
    return max(0.0, min(100.0, score))


def _normalize_reason(reason: Any) -> dict[str, Any] | None:
    if not isinstance(reason, dict):
        return None

    message = str(reason.get("message") or "").strip()
    if not message:
        return None

    flag = str(reason.get("flag") or "info").strip().lower()
    if flag not in {"info", "warning", "error"}:
        flag = "info"

    return {
        "dimension": str(reason.get("dimension") or "performance"),
        "score": _normalize_score(reason.get("score")),
        "flag": flag,
        "message": message,
        "timecode": reason.get("timecode"),
    }


CONFIG = BridgeConfig.from_env()
RUNTIME = GemmaRuntime(CONFIG)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._send_json(200, RUNTIME.health())
            return
        self._send_json(404, {"error": f"Unknown route: {self.path}"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/performance-insight":
            self._send_json(404, {"error": f"Unknown route: {self.path}"})
            return

        try:
            body = self._read_json_body()
            response = RUNTIME.generate_performance_insight(body)
            self._send_json(200, response)
        except Exception as exc:  # noqa: BLE001
            self._send_json(
                500,
                {
                    "error": f"{exc}",
                    "traceback": traceback.format_exc(limit=5),
                },
            )

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(content_length) if content_length > 0 else b"{}"
        return json.loads(payload.decode("utf-8"))

    def _send_json(self, status_code: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    server = ThreadingHTTPServer((CONFIG.host, CONFIG.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
