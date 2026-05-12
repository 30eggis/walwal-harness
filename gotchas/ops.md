# OPS Gotchas

## Good-case-only Logging

Do not log only successful service cases. Non-good-case outcomes are the operational evidence that matters.

## Unclassified Emergency

Do not raise an emergency without first classifying likely owner: backend, frontend, platform, external API, or unknown.

## Unmapped Service

Do not monitor a production/service endpoint as live until the Owner-provided server mapping is recorded: environment type, host, port, health path, log path, and source/contact.

## Port Drift

Do not let CXX agents choose arbitrary ports. CEO must set `HARNESS_BASE_PORT` as a `{xx}000` value in `.env`, and services must derive their ports above that base.
