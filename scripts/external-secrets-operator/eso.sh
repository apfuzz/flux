#!/bin/bash

# set -xv

# eso.sh
# Aaron Patrick <apatrick@crunchtime.com>
# v0.1 - 02/04/2026 - initial script

# This script will set up External Secrets Operator (ESO) in a specified Kubernetes cluster to sync secrets from Vault.
# It configures Vault's Kubernetes authentication method and creates a ClusterSecretStore for ESO.

### asumptions

# the user running the script is in the correct kubectl context
# there is an existing vault policy that allows read-only access to desired secrets
# vault is not running in the cluster in this context

### variables

# set variables from input
K8S_CLUSTER=$1
VAULT_ADDR="https://$2"

# set variables
ES_VERSION=1.3.2  # latest as of Feb 2026
VAULT_AUTH_NAME=eso-$K8S_CLUSTER
VAULT_POLICY=gangsterkitties-readonly

SCRIPT_DIR=$(dirname "$(readlink -f $0)")
CSS_MANIFEST_SRC=$SCRIPT_DIR/css.yaml
CSS_MANIFEST=$SCRIPT_DIR/css-$K8S_CLUSTER.yaml
TEST_SECRET_MANIFEST=$SCRIPT_DIR/test-secret.yaml

# set colors
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;96m'
NC='\033[0m' # No Color

# check sed version
SED_VERSION_CHECK=`sed --version > /dev/null 2>&1`
if [ $? -eq 0 ] ; then
  SED_CMD="sed -i"
else
  test ! -f /opt/homebrew/bin/gsed && echo -e "${YELLOW}GNU sed not present. Please install with 'brew install gnu-sed'. Exiting.${NC}\n" && cleanup && exit 1
  SED_CMD="/opt/homebrew/bin/gsed -i"
fi

### functions

# usage function
usage() {
  cat <<EOF
  Usage: ./$(basename $0) <K8s cluster name> <Vault address>
  Example: ./$(basename $0) poptart vault.gangsterkitties.com

EOF
}

# log into vault
vault_login() {
  echo -e "${BLUE}Logging into Vault at $VAULT_ADDR...${NC}"
  read -s -p "Enter root token: " VAULT_ROOT_TOKEN
  echo

  export VAULT_ADDR=$VAULT_ADDR
  echo $VAULT_ROOT_TOKEN | vault login -
}

# enable the kubernetes authentication method in vault
vault_auth() {
  echo -e "${BLUE}Enabling Vault Kubernetes auth method...${NC}"
  vault auth enable -path=$VAULT_AUTH_NAME -description="External Secrets Operator for K8s cluster $K8S_CLUSTER" kubernetes
}

# install external secrets operator
eso_install() {
  echo -e "${BLUE}Installing External Secrets Operator...${NC}"

  # add helm repo
  helm repo add external-secrets https://charts.external-secrets.io
  helm repo update

  # install eso
  helm upgrade --install external-secrets external-secrets/external-secrets --version $ES_VERSION -n external-secrets --create-namespace

  # create vault service account and token
  kubectl apply -f $SCRIPT_DIR/vault-sa.yaml
}

# write vault auth config
vault_auth_config() {
  echo -e "${BLUE}Configuring Vault Kubernetes auth method...${NC}"

  # set variables for Vault Kubernetes auth config
  TOKEN_REVIEW_JWT=$(kubectl get secret vault-token -n external-secrets --output='go-template={{ .data.token }}' | base64 -d)
  KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 -d)
  KUBE_HOST=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.server}')

  # configure the Kubernetes auth method in Vault
  vault write auth/$VAULT_AUTH_NAME/config \
    token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
    kubernetes_host="$KUBE_HOST" \
    kubernetes_ca_cert="$KUBE_CA_CERT"

  # create Vault role for Kubernetes
  vault write auth/$VAULT_AUTH_NAME/role/kubernetes \
    bound_service_account_names=vault \
    bound_service_account_namespaces="*" \
    policies=$VAULT_POLICY \
    ttl=24h
}

# create cluster secret store
cluster_secret_store() {
  # customize template
  cp $CSS_MANIFEST_SRC $CSS_MANIFEST
  $SED_CMD "s/mountPath.*/mountPath:\ eso-$K8S_CLUSTER/" $CSS_MANIFEST

  # wait for external-secrets-webhook to become available
  echo -e "${BLUE}Waiting for external-secrets-webhook to become available...${NC}"
  kubectl wait -n external-secrets deploy/external-secrets-webhook --for condition=available --timeout=60s

  # apply manifest
  kubectl apply -f $CSS_MANIFEST

  # delete manifest file
  rm -f $CSS_MANIFEST

  # apply test secret manifest
  kubectl apply -f $TEST_SECRET_MANIFEST

  # get test secret status
  echo -e "${BLUE}Waiting for test secret to be ready...${NC}"
  kubectl wait -n external-secrets externalsecret/test-secret --for jsonpath='{.status.conditions[0].status}' --timeout=60s
  echo -e "${GREEN}Test secret synced successfully!${NC}"
}

### main

# check syntax
if [ $# -ne 2 ] ; then
  usage
  exit 1
fi

echo -e "\n${BLUE}This script will use the Kubernetes cluster context: $(kubectl config current-context). Press enter to continue or ctrl+c to cancel.${NC}"
read CONTINUE

# execute functions
vault_login
vault_auth
eso_install
vault_auth_config
cluster_secret_store
