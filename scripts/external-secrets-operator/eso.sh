#!/bin/bash

# exit on error
set -e

# set -xv

# eso.sh
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
ES_VERSION=2.0.1  # latest as of Feb 2026
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
  echo -e "\n${BLUE}Enabling Vault Kubernetes auth method...${NC}"
  VAULT_AUTH_EXISTS=$(vault auth list | grep -c $VAULT_AUTH_NAME || true)
  if [ $VAULT_AUTH_EXISTS -eq 0 ] ; then
    vault auth enable -path=$VAULT_AUTH_NAME -description="External Secrets Operator for K8s cluster $K8S_CLUSTER" kubernetes
  else
    echo -e "\n${YELLOW}Vault Kubernetes auth method already enabled. Skipping...${NC}"
  fi
}

# install external secrets operator
eso_install() {
  echo -e "\n${BLUE}Installing External Secrets Operator...${NC}"

  # add helm repo
  helm repo add external-secrets https://charts.external-secrets.io
  helm repo update

  # install eso
  helm upgrade --install external-secrets external-secrets/external-secrets --version $ES_VERSION -n external-secrets --create-namespace --wait

  # create vault service account and token
  kubectl apply -f $SCRIPT_DIR/vault-sa.yaml
  sleep 2
}

# write vault auth config
vault_auth_config() {
  echo -e "\n${BLUE}Configuring Vault Kubernetes auth method...${NC}"

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
    audience=vault \
    bound_service_account_names=vault \
    bound_service_account_namespaces=external-secrets \
    token_policies=$VAULT_POLICY \
    ttl=1h
}

# create cluster secret store
cluster_secret_store() {
  # customize template
  cp $CSS_MANIFEST_SRC $CSS_MANIFEST
  $SED_CMD "s/mountPath.*/mountPath:\ eso-$K8S_CLUSTER/" $CSS_MANIFEST

  # wait for external-secrets-webhook to become available
  echo -e "\n${BLUE}Waiting for external-secrets-webhook to become available...${NC}"
  kubectl wait -n external-secrets deploy/external-secrets-webhook --for condition=available --timeout=60s

  # apply manifest
  sleep 2
  kubectl apply -f $CSS_MANIFEST

  # delete manifest file
  rm -f $CSS_MANIFEST

  # apply test secret manifest
  kubectl apply -f $TEST_SECRET_MANIFEST

  # get test secret status
  echo -e "\n${BLUE}Waiting for test secret to be ready...${NC}"
  kubectl wait -n external-secrets externalsecret/test-secret --for=condition=Ready --timeout=60s
  echo -e "\n${GREEN}Test secret synced successfully!${NC}"
}

### main

# check syntax
if [ $# -ne 2 ] ; then
  usage
  exit 1
fi

echo -e "\n${BLUE}This script will use the Kubernetes cluster context: $(kubectl config current-context). Press enter to continue or ctrl+c to cancel.${NC}"
read CONTINUE

# configure vault auth
vault_login
vault_auth

# check for existing external secrets operator installation
ESO_STATUS=$(helm get metadata -n external-secrets external-secrets | grep STATUS | awk '{print $NF}' 2> /dev/null)
if [ "$ESO_STATUS" = "deployed" ] ; then
  echo -e "\n${GREEN}External Secrets Operator already installed...${NC}"
else
  eso_install
fi

# complete setup
vault_auth_config
cluster_secret_store
