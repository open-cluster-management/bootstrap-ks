#!/bin/bash

# Color codes for bash output
BLUE='\e[36m'
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
CLEAR='\e[39m'

# Handle MacOS being incapable of tr, grep, and others
export LC_ALL=C

#----DEFAULTS----#
# Generate a 5-digit random cluster identifier for resource tagging purposes
RANDOM_IDENTIFIER=$(head /dev/urandom | LC_CTYPE=C tr -dc a-z0-9 | head -c 5 ; echo '')
# Ensure USER has a value
if [ -z "$JENKINS_HOME" ]; then
  USER=${USER:-"unknown"}
else
  USER=${USER:-"jenkins"}
fi

SHORTNAME=$(echo $USER | head -c 8)

# Generate a default resource name
RESOURCE_NAME="$SHORTNAME-$RANDOM_IDENTIFIER"

# Default to eastus
AZURE_REGION=${AZURE_REGION:-"eastus"}

# Default to disable the service principal login
SERVICE_PRINCIPAL=${SERVICE_PRINCIPAL:-"false"}


#----VALIDATE ENV VARS----#

if [ ! -z "$CLUSTER_NAME" ]; then
    RESOURCE_NAME="$CLUSTER_NAME-$RANDOM_IDENTIFIER"
    printf "${BLUE}Using $RESOURCE_NAME to identify all created resources.${CLEAR}\n"
else
    printf "${BLUE}Using $RESOURCE_NAME to identify all created resources.${CLEAR}\n"
fi

#----LOG IN----#
# Log in and optionally choose a specific subscription
printf "${YELLOW}"
if [ $SERVICE_PRINCIPAL == "true" ]; then
    if [ -z "$CLIENT_ID" ]; then
        printf "${RED}CLIENT_ID env var not set. flagging for exit.${CLEAR}\n"
        exit 1
    fi
    if [ -z "$CLIENT_SECRET" ]; then
        printf "${RED}CLIENT_SECRET env var not set. flagging for exit.${CLEAR}\n"
        exit 1
    fi
    if [ -z "$TENANT_ID" ]; then
        printf "${RED}TENANT_ID env var not set. flagging for exit.${CLEAR}\n"
        exit 1
    fi    
    az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" -t "$TENANT_ID" > /dev/null
    if [ "$?" -ne 0 ]; then
        printf "${RED}Azure login failed, check credentials. Exiting.${CLEAR}\n"
        exit 1
    fi
else
    if [ -z "$AZURE_PASS" ]; then
        printf "${RED}AZURE_PASS env var not set. flagging for exit.${CLEAR}\n"
        exit 1
    fi
    if [ -z "$AZURE_USER" ]; then
        printf "${RED}AZURE_USER env var not set. flagging for exit.${CLEAR}\n"
        exit 1
    fi
    az login -u "$AZURE_USER" -p "$AZURE_PASS" > /dev/null
    if [ "$?" -ne 0 ]; then
        printf "${RED}Azure login failed, check credentials. Exiting.${CLEAR}\n"
        exit 1
    fi
fi

if [ ! -z "$AZURE_SUBSCRIPTION_ID" ]; then
    az account set --subscription $AZURE_SUBSCRIPTION_ID
    if [ "$?" -ne 0 ]; then
        printf "${RED}Unable to set azure subscription, az account set --subscription $AZURE_SUBSCRIPTION_ID returned non-zero.${CLEAR}\n"
        printf "${RED}Exiting to avoid the creation of a cluster in the wrong account.${CLEAR}\n"
        exit 1
    fi
fi

printf "${BLUE}Using subscription:${CLEAR}\n"
printf "${YELLOW}"
SUBSCRIPTION=$(az account show | jq -r '.id')
if [ -z "${SUBSCRIPTION}" ]; then
    printf "${RED}Couldn't detect a subscription to be used, exiting.${CLEAR}"
    exit 1
fi
az account show
printf "${CLEAR}"


#----CREATE RESOURCE GROUP----#
RESOURCE_GROUP_NAME="${RESOURCE_NAME}-rg"
printf "${BLUE}Creating a resource group named ${RESOURCE_GROUP_NAME}.${CLEAR}\n"

printf "${YELLOW}"
az group create --name "${RESOURCE_GROUP_NAME}" --location "$AZURE_REGION" --subscription $SUBSCRIPTION
if [ "$?" -ne 0 ]; then
    printf "${RED}Failed to create resource group ${RESOURCE_GROUP_NAME}, exiting${CLEAR}\n"
    exit 1
fi
printf "${CLEAR}"


#----CREATE AKS CLUSTER----#
AKS_CLUSTER_NAME="${RESOURCE_NAME}-aks"
printf "${BLUE}Creating an AKS cluster named ${AKS_CLUSTER_NAME}.${CLEAR}\n"

printf "${YELLOW}"
az aks create --resource-group "${RESOURCE_GROUP_NAME}" --name "${AKS_CLUSTER_NAME}" --location "${AZURE_REGION}" --subscription $SUBSCRIPTION --generate-ssh-keys
if [ "$?" -ne 0 ]; then
    printf "${RED}Failed to create AKS cluster ${AKS_CLUSTER_NAME}, exiting${CLEAR}\n"
    exit 1
fi
printf "${CLEAR}"


#----EXTRACTING KUBECONFIG----#
printf "${BLUE}Getting Kubeconfig for cluster.${CLEAR}\n"
printf "${YELLOW}"
az aks get-credentials --name ${AKS_CLUSTER_NAME} --resource-group ${RESOURCE_GROUP_NAME} -f $(pwd)/${AKS_CLUSTER_NAME}.kubeconfig
if [ "$?" -ne 0 ]; then
    printf "${RED}Failed to get credentials for AKS cluster ${AKS_CLUSTER_NAME}, complaining and continuing${CLEAR}\n"
    exit 1
fi
printf "You can find your kubeconfig file for this cluster in $(pwd)/${AKS_CLUSTER_NAME}.kubeconfig.\n"
printf "${CLEAR}"


#-----DUMP STATE FILE----#
cat > ./${AKS_CLUSTER_NAME}.json <<EOF
{
    "RESOURCE_GROUP_NAME": "${RESOURCE_GROUP_NAME}",
    "CLUSTER_NAME": "${AKS_CLUSTER_NAME}",
    "RESOURCE_NAME": "${RESOURCE_NAME}",
    "REGION": "${AZURE_REGION}",
    "SUBSCRIPTION": "${SUBSCRIPTION}",
    "PLATFORM": "AZURE"
}
EOF
printf "${GREEN}AKS cluster provision successful.  Cluster named ${AKS_CLUSTER_NAME} created.  State file saved for cleanup in $(pwd)/${AKS_CLUSTER_NAME}.json"
