AI Usage Sentinel 1.9.0 adds a small offline decision-tree semantic classifier for public reset evidence.

- Shared CART model in macOS, Windows/Linux and website; no paid inference API or account uploads.
- Recognizes completed claims, personal reports, forecasts, polls, speculation, denial, scheduled resets and unrelated reset text.
- Semantic multipliers can only reduce public-source scores, never increase them. Local quota evidence stays independent. Forecast wording is not proof of completion.
- Each source shows the semantic interpretation and evidence multiplier. Unknown wording falls back to existing rules.
- Reproducible pilot training: 108 author-written synthetic training examples and 36 grouped held-out synthetic examples, not a real-world accuracy claim. English pilot, multilingual UI. Existing language rules remain fallback.

macOS 14+, universal Apple Silicon/Intel. Ad-hoc signed, not notarized. Windows/Linux beta ports have CI coverage, not full physical desktop validation.
