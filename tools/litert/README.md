# LiteRT-LM models for Android

Android runs both models on **LiteRT-LM**. It prefers the NPU, then the GPU,
then LiteRT's own CPU backend. Windows and Linux use the GGUFs on llama.cpp.

| Role | Android file | Source |
|------|--------------|--------|
| Brain (tutor + code) | `qwen2.5-coder-1.5b-instruct_int4.litertlm` | `litert-community/Qwen2.5-Coder-1.5B-Instruct`, mirrored |
| Translation | `afrislm-0.8b_int8.litertlm` | Converted from `qvac/TranslatePsy-AfriSLM-0.8B` by `.github/workflows/convert-afrislm-litertlm.yml` |

## Make them

1. Run **Convert AfriSLM to LiteRT-LM** from the Actions tab, or push a
   `convert/**` branch.
2. The job runs `translation_gate.py`. It translates English into Luganda,
   Swahili, Kinyarwanda and Yoruba and back again, on both the new
   `.litertlm` and the shipped GGUF. It fails if the LiteRT output is
   empty, loops, or is clearly worse.
3. Read `gate-report.md`, attached to the run and to the release. Check
   that the Luganda looks right.
4. When it passes, both files and their `.sha256` files are on the
   `litert-models` GitHub release.

## Mirror into the app's download repo

The in-app installer downloads from `Oticgroup/ai-connect-africa-packages`.
Download both files from the release, then run:

```
hf upload Oticgroup/ai-connect-africa-packages afrislm-0.8b_int8.litertlm afrislm-0.8b_int8.litertlm
hf upload Oticgroup/ai-connect-africa-packages qwen2.5-coder-1.5b-instruct_int4.litertlm qwen2.5-coder-1.5b-instruct_int4.litertlm
```

Then put the two SHA-256 values into `ModelFetchFiles` in
`lib/services/model_fetch_service.dart`.
