# Website 2 — Rate, Report, Profile.
# Deploys to the rate hosting target = aiaccountant-rate.web.app. Run from the
# project root:  .\build_rate.ps1
#
# The hosting site must exist first (one-time):
#   firebase hosting:sites:create aiaccountant-rate --project aiaccountant-b60ed
#
# Credentials come from lib/core/config.dart, same as build_test.ps1 — no env
# file is passed, so this ships the config.dart defaults.
#
# Both site scripts build into build/web, so this builds AND deploys in one go.
# Never run build_ops.ps1 and build_rate.ps1 at the same time: the second build
# would overwrite build/web under the first one's deploy.
$ErrorActionPreference = 'Stop'

$FIREBASE_PROJECT = 'aiaccountant-b60ed'

flutter build web --release --dart-define=SITE=rate
if ($?) { firebase deploy --only hosting:rate --project $FIREBASE_PROJECT }
