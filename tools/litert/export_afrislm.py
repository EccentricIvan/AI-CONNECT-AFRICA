"""Exports AfriSLM (a Qwen3.5-0.8B fine-tune) to a .litertlm bundle.

Wraps litert-torch's own exporter (litert_torch.generative.export_hf) with
one compatibility patch:

litert-torch 0.9.4's static Qwen3.5 decoder hands the rotary embedding 2-D
position ids, shape (batch, n). Current transformers'
Qwen3_5TextRotaryEmbedding expects Qwen3.5's multimodal (M-RoPE) layout,
(3, batch, n) — one stream each for time/height/width — and fails with
"too many indices for tensor of dimension 2". For text, all three streams
are the same positions; transformers' own Qwen3.5 text model expands them
exactly this way. So 2-D ids are expanded to 3-D before the call: same
math, no change for inputs that are already 3-D.

usage: python export_afrislm.py <model_dir> <output_dir>
"""
import sys

import transformers.models.qwen3_5.modeling_qwen3_5 as qwen3_5

_original_forward = qwen3_5.Qwen3_5TextRotaryEmbedding.forward


def _forward(self, x, position_ids, *args, **kwargs):
    if position_ids.ndim == 2:
        position_ids = position_ids[None, ...].expand(3, position_ids.shape[0], -1)
    return _original_forward(self, x, position_ids, *args, **kwargs)


qwen3_5.Qwen3_5TextRotaryEmbedding.forward = _forward

from litert_torch.generative.export_hf import export as export_lib  # noqa: E402


def main():
    model_dir, output_dir = sys.argv[1], sys.argv[2]
    export_lib.export(
        model=model_dir,
        output_dir=output_dir,
        quantization_recipe="dynamic_wi8_afp32",
        cache_length=1024,
        prefill_lengths=[32, 64, 128, 256, 512],
        use_jinja_template=True,
        bundle_litert_lm=True,
        export_vision_encoder=False,
    )


if __name__ == "__main__":
    main()
