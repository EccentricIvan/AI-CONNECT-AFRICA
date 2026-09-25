"""Quality gate for a converted AfriSLM .litertlm (run in CI, Linux).

The converted model must translate about as well as the GGUF the app ships
today. Each sentence goes English -> language -> English on BOTH runtimes,
with the app's exact AfriSLM prompts (lib/ai_core/translate/
translation_pipeline.dart), and the round trip is scored against the
original English with chrF. Greedy decoding on both sides.

Fails (exit 1) when the LiteRT model returns empty or looping output, or
its round-trip chrF is clearly below the GGUF's. Writes a side-by-side
report either way, for a human to read the actual Luganda.

usage: python translation_gate.py --litertlm X.litertlm --gguf Y.gguf --out report.md
"""
import argparse
import re
import statistics
import sys
import time

import litert_lm
import sacrebleu
from llama_cpp import Llama

SENTENCES = [
    "Plants make their own food using sunlight.",
    "Please open your books to page twelve.",
    "Water boils at one hundred degrees Celsius.",
    "What is the capital city of Uganda?",
    "Wash your hands before you eat.",
    "The teacher will check our homework tomorrow.",
    "A triangle has three sides.",
    "Farmers plant maize when the rains begin.",
    "Can you explain how a computer works?",
    "Drink clean water to stay healthy.",
]

LANGUAGES = ["Luganda", "Swahili", "Kinyarwanda", "Yoruba"]


def system_prompt(src: str, dst: str) -> str:
    return (
        f"You are a professional {src} to {dst} translator. Your goal is to "
        f"accurately convey the meaning and nuances of the original {src} text "
        f"while adhering to {dst} grammar, vocabulary, and cultural "
        f"sensitivities. Produce only the {dst} translation, without any "
        f"additional explanations or commentary."
    )


def user_prompt(src: str, dst: str, text: str) -> str:
    # Same as the app, including the /no_think switch it appends for AfriSLM.
    return f"Please translate the following {src} text into {dst}: {text}.\n\nTranslation:\n/no_think"


def clean(text: str) -> str:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    text = text.replace("<think>", "").replace("</think>", "")
    return text.strip().split("\n")[0].strip()


def looks_broken(text: str) -> bool:
    if not text:
        return True
    words = text.split()
    if len(words) >= 8:
        # The same 3-word phrase repeated 3+ times = a decode loop.
        grams = [" ".join(words[i:i + 3]) for i in range(len(words) - 2)]
        if max(grams.count(g) for g in set(grams)) >= 3:
            return True
    return len(text) > 400


class LiteRt:
    def __init__(self, path: str):
        backend = getattr(litert_lm, "Backend").CPU
        self.engine = litert_lm.Engine(path, backend=backend, max_num_tokens=1024)
        self.engine.__enter__()

    def translate(self, src, dst, text):
        with self.engine.create_conversation(
            messages=[{"role": "system", "content": system_prompt(src, dst)}],
        ) as conv:
            response = conv.send_message(user_prompt(src, dst, text))
        return clean("".join(
            item.get("text", "") for item in response.get("content", [])
            if item.get("type") == "text"
        ))


class Gguf:
    def __init__(self, path: str):
        self.llm = Llama(model_path=path, n_ctx=1024, n_threads=4, verbose=False)

    def translate(self, src, dst, text):
        out = self.llm.create_chat_completion(
            messages=[
                {"role": "system", "content": system_prompt(src, dst)},
                {"role": "user", "content": user_prompt(src, dst, text)},
            ],
            temperature=0.0,
            top_k=1,
            max_tokens=160,
        )
        return clean(out["choices"][0]["message"]["content"] or "")


def round_trip(model, lang):
    rows = []
    for en in SENTENCES:
        t0 = time.time()
        there = model.translate("English", lang, en)
        back = model.translate(lang, "English", there) if there else ""
        rows.append({
            "en": en,
            "there": there,
            "back": back,
            "broken": looks_broken(there) or looks_broken(back),
            "chrf": sacrebleu.sentence_chrf(back, [en]).score if back else 0.0,
            "secs": time.time() - t0,
        })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--litertlm", required=True)
    ap.add_argument("--gguf", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--min-ratio", type=float, default=0.8,
                    help="LiteRT median chrF must be >= this x the GGUF's")
    args = ap.parse_args()

    models = {"litert": LiteRt(args.litertlm), "gguf": Gguf(args.gguf)}
    results = {name: {lang: round_trip(m, lang) for lang in LANGUAGES}
               for name, m in models.items()}

    lines = ["# AfriSLM LiteRT conversion gate", ""]
    failed = []
    for lang in LANGUAGES:
        lit = results["litert"][lang]
        gg = results["gguf"][lang]
        lit_med = statistics.median(r["chrf"] for r in lit)
        gg_med = statistics.median(r["chrf"] for r in gg)
        broken = sum(r["broken"] for r in lit)
        ok = broken <= 2 and lit_med >= args.min_ratio * gg_med
        if not ok:
            failed.append(lang)
        lines += [
            f"## {lang}: {'PASS' if ok else 'FAIL'}",
            f"round-trip chrF median — LiteRT {lit_med:.1f} vs GGUF {gg_med:.1f}; "
            f"broken LiteRT outputs {broken}/{len(lit)}; "
            f"LiteRT {statistics.mean(r['secs'] for r in lit):.1f}s/sentence, "
            f"GGUF {statistics.mean(r['secs'] for r in gg):.1f}s/sentence",
            "",
            "| English | LiteRT | GGUF |",
            "|---|---|---|",
        ]
        for a, b in zip(lit, gg):
            lines.append(f"| {a['en']} | {a['there']} | {b['there']} |")
        lines.append("")

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("\n".join(lines))
    if failed:
        print(f"GATE FAILED for: {', '.join(failed)}", file=sys.stderr)
        sys.exit(1)
    print("GATE PASSED")


if __name__ == "__main__":
    main()
