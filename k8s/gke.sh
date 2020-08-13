#!/bin/bash

if [ -z "$TFH_token" ] || [ -z "$TFH_org" ] || [ -z "$GOOGLE_CREDENTIALS_PATH" ] || [ -z "GOOGLE_PROJECT" ];
then
  echo "You must set TFH_token, GOOGLE_CREDENTIALS_PATH, GOOGLE_PROJECT and TFH_org"
  exit 1
fi

[[ -z "$1" ]] && echo "Usage: gke.sh cluster_name [apply|destroy]" && exit 1
[[ -z "$2" ]] && echo "Usage: gke.sh cluster_name [apply|destroy]" && exit 1

echo "Listing available clusters"
gcloud container clusters list

cluster_name=$1
echo "Using cluster name: $cluster_name"
export TFH_name="terraform-gke-k8s-$cluster_name"

operation=$2
echo "Going to perform terraform $operation on workspace $TFH_name"

[[ -z "$region" ]] && region="us-east-4"
[[ -z "$zone" ]] && zone="us-east4-b"

echo "Using region: $region"
echo "Using zone: $zone"

export machine_type="n1-standard-2"
export node_count=3
echo "Defaulting to machine_type: $machine_type and node_count: $node_count"

cat <<EOF >./backend.tf
terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "${TFH_org}"
    workspaces {
      name = "${TFH_name}"
    }
  }
}
EOF

terraform init
workspace_id=$(curl -s --header "Authorization: Bearer ${TFH_token}" --header "Content-Type: application/vnd.api+json" "https://app.terraform.io/api/v2/organizations/${TFH_org}/workspaces/${TFH_name}" | jq -r .data.id)

# Delete existing variables
curl --header "Authorization: Bearer ${TFH_token}" --header "Content-Type: application/vnd.api+json" "https://app.terraform.io/api/v2/vars?filter%5Borganization%5D%5Bname%5D=${TFH_org}&filter%5Bworkspace%5D%5Bname%5D=${TFH_name}" > vars.json
x=$(cat vars.json | jq -r ".data[].id" | wc -l | awk '{print $1}')
for (( i=0; i<$x; i++ ))
do
  curl --header "Authorization: Bearer ${TFH_token}" --header "Content-Type: application/vnd.api+json" --request DELETE https://app.terraform.io/api/v2/vars/$(cat vars.json | jq -r ".data[$i].id")
done

tfh pushvars -var "masterAuthPass=solstice-vault-021219" -var "masterAuthUser=solstice-k8s" -var "serviceAccount=k8s-vault" -var "project=${GOOGLE_PROJECT}" -var "region=$region" -var "zone=$zone" -var "cluster_name=${cluster_name}" -var "node_count=${node_count}" -var "machine_type=${machine_type}" -env-var "CONFIRM_DESTROY=1" -overwrite-all -dry-run false

echo "Setting new GOOGLE_CREDENTIALS from $GOOGLE_CREDENTIALS_PATH"
export GOOGLE_CREDENTIALS=$(tr '\n' ' ' < $GOOGLE_CREDENTIALS_PATH | sed -e 's/\"/\\\\"/g' -e 's/\//\\\//g' -e 's/\\n/\\\\\\\\n/g')
sed -e "s/my-key/GOOGLE_CREDENTIALS/" -e "s/my-hcl/false/" -e "s/my-value/${GOOGLE_CREDENTIALS}/" -e "s/my-category/env/" -e "s/my-sensitive/true/" -e "s/my-workspace-id/${workspace_id}/" < ./tfe.variable.json.template  > variable.json;
curl --header "Authorization: Bearer ${TFH_token}" --header "Content-Type: application/vnd.api+json" --data @variable.json "https://app.terraform.io/api/v2/vars"
rm -f variable.json

terraform $operation

echo "Sleeping 10 seconds before proceeding"

if [ $operation == "apply" ]; then

  echo "Checking for existing context with this cluster name"
  context=$(kubectl config get-contexts | grep $cluster_name | awk '{print $2}')
  if [ ! -z $context ]; then
    echo "Deleting previous context: $context"
    kubectl config delete-context $context
  fi

  echo "Generating kubeconfig"
  gcloud container clusters get-credentials $cluster_name --zone $zone --project $GOOGLE_PROJECT

  context=$(kubectl config get-contexts | grep $cluster_name | awk '{print $2}')
  echo "Switching context to: $context"
  kubectl config use-context $context
  kubectl config current-context

  echo "Dumping cluster-info:"
  kubectl cluster-info
fi
