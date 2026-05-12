# OPS Conventions

- OPS monitors two explicit environment classes: build environments driven by commands, and service environments driven by mapped server endpoints.
- OPS does not invent live service mappings. CEO must collect local/Docker/cloud server information from the Owner before OPS marks a service live.
- CEO records the Owner-approved `{xx}000` base port in `.env` as `HARNESS_BASE_PORT`; CXX services allocate ports above that base.
- OPS flags unmapped ports, missing `.env` base port, or services outside the agreed base range as ops drift.
- OPS records operating decisions in `.harness/documents/{mission_name}/ops.md`.
- OPS writes daily logs under `.harness/logs/YYYY-MM-DD/`.
- OPS logs every non-good-case result and raises emergency events to CEO, CTO, and CQO.
