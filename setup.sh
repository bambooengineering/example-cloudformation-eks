#!/usr/bin/env bash
set -euo pipefail

echo "Setting up EKS cluster with cloudformation and helm..."
echo "AWS region: $AWS_DEFAULT_REGION"
echo "EC2 ssh key name: $KEY_NAME"

# Check the key pair exists
aws ec2 describe-key-pairs --key-name $KEY_NAME

CLUSTER_NAME="example-eks-cluster"
STACK_NAME=$CLUSTER_NAME
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# This command creates the full environment for the example to run.
# Since it necessarily creates roles, the `--capabilities CAPABILITY_NAMED_IAM` flag
# is required.
echo "Creating cloudformation stack..."
aws cloudformation create-stack  \
    --capabilities CAPABILITY_NAMED_IAM \
    --stack-name $STACK_NAME \
    --parameters ParameterKey=EKSClusterName,ParameterValue=$CLUSTER_NAME ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    --template-body file://cloudformation-vpc-eks.yaml

echo "Waiting for the $STACK_NAME stack to finish creating. This can take some time (~15 minutes). Looks like a good day to make a tea..."
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME

echo "Retrieve the connection details for the new cluster..."
aws eks update-kubeconfig --name $CLUSTER_NAME

echo "Retrieving the role of the worker node group"
NODE_INSTANCE_ROLE=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`NodeInstanceRole`].OutputValue' --output text)

echo "Found node instance role: $NODE_INSTANCE_ROLE"

echo "Ensure that the nodes from the worker groups can join the cluster."
# Note, the file must contain the above node instance role so we insert it before applying the template.
cp aws-auth-cm.yaml /tmp/aws-auth-cm-temp.yaml
sed -i 's@NODE_INSTANCE_ROLE@'$NODE_INSTANCE_ROLE'@g' /tmp/aws-auth-cm-temp.yaml
kubectl apply -f /tmp/aws-auth-cm-temp.yaml
rm /tmp/aws-auth-cm-temp.yaml

echo "Wait for the worker nodes to become visible and Ready."
until kubectl get nodes | grep -m 1 " Ready "; do echo "$(date): Looking for running nodes..." && sleep 2 ; done

echo "Node found to be Ready."
kubectl get nodes

echo "Done!"
