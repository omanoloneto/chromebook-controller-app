#!/usr/bin/env bash
set -Eeuo pipefail

# Prova os adaptadores REST (Linux) contra os emuladores do Firebase.
# O projeto é demo-*: nada aqui alcança a produção nem pede login.

cd "$(dirname "${BASH_SOURCE[0]}")/../firebase"
exec firebase emulators:exec --only auth,database,storage --project demo-cda \
    'cd .. && flutter test --no-pub test/rest_emulator_test.dart'
