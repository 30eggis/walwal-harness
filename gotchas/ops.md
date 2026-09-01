# OPS Gotchas

## Good-case-only Logging

Do not log only successful service cases. Non-good-case outcomes are the operational evidence that matters.

## Unclassified Emergency

Do not raise an emergency without first classifying likely owner: backend, frontend, platform, external API, or unknown.

## Unmapped Service

Do not monitor a production/service endpoint as live until the Owner-provided server mapping is recorded: environment type, host, port, health path, log path, and source/contact.

## Port Drift

Do not let CXX agents choose arbitrary ports. CEO must set `HARNESS_BASE_PORT` as a `{xx}000` value in `.env`, and services must derive their ports above that base.

## Clean Log From An Unproven Instrument

"Nothing bad appeared in the log" is worth nothing until a positive control proves the log could have shown it. Dev servers, log middleware, proxies, and test runners routinely drop successful or sub-threshold requests at a log level nobody chose deliberately, and that rule appears nowhere in the project's own code. Record the instrument — tool, log level, filter, control — in Environment Evidence, or report the observation as unverified rather than clean.
