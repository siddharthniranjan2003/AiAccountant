# Build the FULL app (every screen, no SITE flag) and deploy it to Firebase
# Hosting. Credentials come from lib/core/config.dart (the single source of
# truth) — edit them there to target a different environment before building.
# Run from the project root:  .\build_test.ps1
#
# Hosting now has two targets, so a deploy has to name one: this pushes to
# `ops` = aiaccountant-b60ed.web.app, the site it has always used. For the
# per-site builds use .\build_ops.ps1 / .\build_rate.ps1 instead.
$ErrorActionPreference = 'Stop'

$FIREBASE_PROJECT = 'aiaccountant-b60ed'

flutter build web --release
if ($?) { firebase deploy --only hosting:ops --project $FIREBASE_PROJECT }
