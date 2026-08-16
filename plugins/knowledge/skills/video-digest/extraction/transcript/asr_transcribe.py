"""Transcribe a media file with faster-whisper for the video-digest ASR rung.

Prints one JSON object to stdout:

    {"model": ..., "language": ..., "segments": [
        {"start": s, "end": s, "text": ..., "words": [{"start": s, "end": s, "word": ...}]}
    ]}

Contract: this script NEVER installs anything. faster-whisper is a documented
optional prerequisite; when it is not importable the script exits 3 and the
caller records the capability as absent.
"""

import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media", required=True)
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--initial-prompt", default=None)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--compute-type", default="default")
    args = parser.parse_args()

    try:
        from faster_whisper import BatchedInferencePipeline, WhisperModel
    except ImportError as exc:
        print(f"faster-whisper not importable: {exc}", file=sys.stderr)
        return 3

    try:
        model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    except Exception as exc:  # noqa: BLE001 - CUDA/toolkit init failures fall back to CPU
        print(f"device '{args.device}' unavailable ({exc}); falling back to CPU int8", file=sys.stderr)
        model = WhisperModel(args.model, device="cpu", compute_type="int8")

    pipeline = BatchedInferencePipeline(model=model)
    segments, info = pipeline.transcribe(
        args.media,
        batch_size=args.batch_size,
        word_timestamps=True,
        initial_prompt=args.initial_prompt or None,
    )

    out = {"model": args.model, "language": info.language, "segments": []}
    for segment in segments:
        out["segments"].append(
            {
                "start": segment.start,
                "end": segment.end,
                "text": segment.text.strip(),
                "words": [
                    {"start": word.start, "end": word.end, "word": word.word}
                    for word in (segment.words or [])
                ],
            }
        )
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
