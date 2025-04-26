#!/bin/bash
set -e
export AWS_PAGER=""
AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
EC2_NAME=$1
CMD="$2"
EXECUTION_TIME=$(date +"%Y%m%d_%H%M%S")
EC2_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*${EC2_NAME}*" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)
COMMAND_ID=$(aws ssm send-command \
  --instance-ids $EC2_IDS \
  --document-name "AWS-RunShellScript" \
  --comment "Run cmd at once" \
  --parameters 'commands=["'"${CMD}"'"]' \
  --query "Command.CommandId" \
  --output text)
SAVE_FILE="${COMMAND_ID}_${AWS_ACCOUNT}-${EXECUTION_TIME}.txt"
echo "# Command execute - ${CMD}" | tee -a "${SAVE_FILE}"
sleep 5
echo "# Command execution result - ${COMMAND_ID}" | tee -a "${SAVE_FILE}"
aws ssm list-command-invocations --command-id ${COMMAND_ID} --details --output json | jq -r '.[][].InstanceId' \
| while read INSTANCE_ID; do
    INSTANCE_ID=$(echo "$INSTANCE_ID" | tr -d '\n')
    echo "## ${INSTANCE_ID}" | tee -a "${SAVE_FILE}"
    OUTPUT=$(aws ssm get-command-invocation --command-id ${COMMAND_ID} --instance-id ${INSTANCE_ID} \
      --query "StandardOutputContent" --output text)
    echo "${OUTPUT}" | tee -a "${SAVE_FILE}"
  done
ls "${SAVE_FILE}"
