# Shared Gotchas

## Default Engine Impersonation

Do not let a missing CXX or specialist silently run as the default AI engine. Hire first.

## Command Misuse

Do not add internal slash commands for CXX or workers. Commands are Owner entrypoints only.

## Runtime State In Package Repo

Do not create or commit project runtime `.harness/` state in this package repository.
