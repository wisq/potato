# Shell snippet used by all potato services.

cd /usr/local/potato/app

rvm_path=/usr/local/potato/rvm
. $rvm_path/scripts/rvm

rvm use 1.9.2

set -e

export GEM_HOME=/usr/local/potato/gems
export BUNDLE_APP_CONFIG=/usr/local/potato/bundler

if [ "$bundle_install" = "auto" ]; then
	bundle check || bundle install --deployment
elif ! bundle check; then
	echo "Bundle not ready, main app needs restarting."
	sleep 30
	exit 1
fi
