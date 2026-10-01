# Fake eval responses

Synthetic responses for `EVAL_FAKE=test/fixtures/eval_fake rake eval:run[...]`, one directory per case in `evals/cases/`. They exist to exercise the pipeline without an API key. They are not model output, and runs made with them are marked `client: fake` and never reach the README.
