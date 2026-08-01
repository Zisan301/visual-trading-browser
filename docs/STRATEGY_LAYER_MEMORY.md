# Strategy Layer Memory

## Core Idea

The final strategy layer will not be only simple rule-based scoring.

The long-term plan is to build a trained strategy dataset created from:

- professional trading videos
- YouTube trading lessons
- trading websites
- trading books
- manually reviewed chart examples
- replay/live market testing

## Correct Learning Workflow

Professional source
→ strategy idea extraction
→ measurable rule/features
→ dataset row creation
→ live/replay validation
→ accuracy measurement
→ offline model training
→ validated strategy inserted into prediction model

## Important Notes

The model should not initially learn directly from videos by itself.

Instead:

1. We extract strategy ideas.
2. We convert them into structured strategy rules.
3. We test those rules against real/replay market frames.
4. We collect labeled examples.
5. We train a model offline.
6. We only insert strategies that achieve satisfactory accuracy.

## Dataset Browser Plan

A separate browser/tool will be created only for strategy dataset creation.

It will be used to:

- watch or analyze professional trading videos
- read strategy examples
- mark strategy rules
- create labeled examples
- test strategies on replay/live captures
- export strategy datasets

It must not auto trade.

## Final Strategy Model Plan

The final prediction model should use:

- professional strategy rules
- collected strategy dataset
- live candle features
- trained ML probability
- confidence calibration
- no-signal filters
- strategy accuracy history

Output:

- CALL_WATCH
- PUT_WATCH
- NO_SIGNAL
- confidence
- strategy reason
- strategy name
- previous accuracy

## Safety

Current project remains prediction-only.

No auto trading.
No platform button clicking.
No private platform API.
No cookies.
