# Website 3 — Sales Quote: Queue, History, Rate, Report, Profile, sale only.
# Deploys to the sales-quote hosting target. Run from the project root:
#   .\build_sales_quote.ps1              # testing (default)
#   .\build_sales_quote.ps1 deployment   # deployment
#
# Unlike build_ops.ps1 / build_rate.ps1 (which ship lib/core/config.dart's
# defaults against aiaccountant-b60ed), this site exists only under the testing
# and deployment projects, so it always passes an env file.
#
# The hosting sites must exist first (one-time, per project):
#   firebase hosting:sites:create tallybridge-testing-sales-quote --project testing --account testing.riplara@gmail.com
#   firebase hosting:sites:create tallybridge-deployment-sales-quote --project deployment --account deployment.riplara@gmail.com
#
# Every site script builds into build/web, so this builds AND deploys in one go.
# Never run two of them at the same time: the second build would overwrite
# build/web out from under the first one's deploy.
param([ValidateSet('testing', 'deployment')][string]$Env = 'testing')
$ErrorActionPreference = 'Stop'

$ACCOUNT = if ($Env -eq 'testing') { 'testing.riplara@gmail.com' } else { 'deployment.riplara@gmail.com' }

flutter build web --release --dart-define-from-file=env/$Env.json --dart-define=SITE=sales-quote
if ($?) { firebase deploy --only hosting:sales-quote --project $Env --account $ACCOUNT }
