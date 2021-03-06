#!/bin/bash
set +e

cd "$HOME"
if [ ! -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_APP_NAME" ]
then
    fail "Missing or empty option APP_NAME, please check wercker.yml"
fi

if [ ! -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_ENV_NAME" ]
then
    fail "Missing or empty option ENV_NAME, please check wercker.yml"
fi

if [ ! -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_KEY" ]
then
    fail "Missing or empty option KEY, please check wercker.yml"
fi

if [ ! -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_SECRET" ]
then
    fail "Missing or empty option SECRET, please check wercker.yml"
fi

if [ ! -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_REGION" ]
then
    warn "Missing or empty option REGION, defaulting to us-west-2"
    WERCKER_ELASTIC_BEANSTALK_DEPLOY_REGION="us-west-2"
fi

if [ ! -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_SC" ]
then
    info "Missing or empty option SC, defaulting to git"
    WERCKER_ELASTIC_BEANSTALK_DEPLOY_SC="git"
fi

if [ -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_DEBUG" ]
then
    warn "Debug mode turned on, this can dump potentially dangerous information to log files."
fi

PACKAGES_TO_INSTALL=""

if ! hash python
then
    debug "python will be installed"
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL python"
fi

if ! hash pip
then
    debug "python-pip will be installed"
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL python-pip python-dev"
fi

if ! hash $WERCKER_ELASTIC_BEANSTALK_DEPLOY_SC
then
    debug "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_SC will be installed"
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $WERCKER_ELASTIC_BEANSTALK_DEPLOY_SC"
fi

if [ -n "$PACKAGES_TO_INSTALL" ]
then
    debug "Updating packages"
    sudo apt-get update
    debug "Installing packages: $PACKAGES_TO_INSTALL"
    if ! apt-get install -y $PACKAGES_TO_INSTALL
    then
        fail "Failed to install packages $PACKAGES_TO_INSTALL"
    fi
    debug "Clenup packages"
    rm -rf /var/lib/apt/lists/*
fi

if ! hash pip
then
    fail "PIP not installed"
fi

PIP_TOOL=$(which pip)
info "pip installed at $PIP_TOOL"

debug "Installing awsebcli"
if ! hash eb
then
    if ! sudo "$PIP_TOOL" install --upgrade awsebcli
    then
        fail "Unable to install awsebcli"
    fi
fi

debug "awsebcli installed"
AWSEB_TOOL=$(which eb)
info "EB CLI installed at $AWSEB_TOOL"
info "Using $($AWSEB_TOOL --version)"

mkdir -p "$HOME/.aws" || fail "Unable to make $HOME/.aws directory"
mkdir -p "$WERCKER_SOURCE_DIR/.elasticbeanstalk" || fail "Unable to make $WERCKER_SOURCE_DIR/.elasticbeanstalk directory"

debug "Change back to the source dir";
cd "$WERCKER_SOURCE_DIR"

AWSEB_CREDENTIAL_FILE="$HOME/.aws/credentials"
AWSEB_CONFIG_FILE="$HOME/.aws/config"
AWSEB_EB_CONFIG_FILE="$WERCKER_SOURCE_DIR/.elasticbeanstalk/config.yml"

debug "Setting up credentials"
cat <<EOT >> $AWSEB_CREDENTIAL_FILE
[default]
aws_access_key_id=$WERCKER_ELASTIC_BEANSTALK_DEPLOY_KEY
aws_secret_access_key=$WERCKER_ELASTIC_BEANSTALK_DEPLOY_SECRET
EOT
if [ $? -ne "0" ]
then
    fail "Unable to set up config file"
fi

debug "Setting up AWS config file"
cat <<EOT >> $AWSEB_CONFIG_FILE
[default]
output = text
region = $WERCKER_ELASTIC_BEANSTALK_DEPLOY_REGION
EOT
if [ $? -ne "0" ]
then
    fail "Unable to set up config file"
fi

debug "Setting up EB config file."
cat <<EOT >> $AWSEB_EB_CONFIG_FILE
branch-defaults:
  $WERCKER_GIT_BRANCH:
    environment: $WERCKER_ELASTIC_BEANSTALK_DEPLOY_ENV_NAME
global:
  application_name: $WERCKER_ELASTIC_BEANSTALK_DEPLOY_APP_NAME
  default_platform: null
  default_region: $WERCKER_ELASTIC_BEANSTALK_DEPLOY_REGION
  profile: default
  sc: $WERCKER_ELASTIC_BEANSTALK_DEPLOY_SC
EOT
if [ $? -ne "0" ]
then
    fail "Unable to set up config file."
fi

if [ -n "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_DEBUG" ]
then
    debug "Dumping config files."
    echo "=== $AWSEB_CREDENTIAL_FILE ==="
    cat "$AWSEB_CREDENTIAL_FILE"
    echo "=== $AWSEB_CONFIG_FILE ==="
    cat "$AWSEB_CONFIG_FILE"
    echo "=== $AWSEB_EB_CONFIG_FILE ==="
    cat "$AWSEB_EB_CONFIG_FILE"
fi

$AWSEB_TOOL use "$WERCKER_ELASTIC_BEANSTALK_DEPLOY_ENV_NAME" || fail "Unable set EB environment"

debug "Checking if eb exists and can connect"

if ! $AWSEB_TOOL status
then
    fail "EB is not working or is not set up correctly"
fi

debug "Pushing to AWS eb servers."
if [ $WERCKER_ELASTIC_BEANSTALK_DEPLOY_STAGED == "true" ]
then
    debug "Deploy with staged flag"
    DEPLOY_CMD="$AWSEB_TOOL deploy --staged"
else
    DEPLOY_CMD="$AWSEB_TOOL deploy"
fi

if $DEPLOY_CMD
then
    success "Successfully pushed to Amazon Elastic Beanstalk"
else
    fail "Failed deploy to Amazon Elastic Beanstalk"
fi
