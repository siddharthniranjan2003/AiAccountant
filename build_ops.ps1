# Website 1 — Queue, History, Profile.
# Deploys to the ops hosting target = aiaccountant-b60ed.web.app (the existing
# URL). Run from the project root:  .\build_ops.ps1
#
# Credentials come from lib/core/config.dart, same as build_test.ps1 — no env
# file is passed, so this ships the config.dart defaults.
#
# Both site scripts build into build/web, so this builds AND deploys in one go.
# Never run build_ops.ps1 and build_rate.ps1 at the same time: the second build
# would overwrite build/web under the first one's deploy.
$ErrorActionPreference = 'Stop'

$FIREBASE_PROJECT = 'aiaccountant-b60ed'

flutter build web --release --dart-define=SITE=ops
if ($?) { firebase deploy --only hosting:ops --project $FIREBASE_PROJECT }
