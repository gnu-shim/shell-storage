#!/bin/bash
# retrive ethtool execution result for network debug
set -e
export AWS_PAGER=""
AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
EC2_NAME=$1
IF_NAME=$2
EXECUTION_TIME=$(date +"%Y%m%d_%H%M%S")
EC2_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*${EC2_NAME}*" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)
COMMAND_ID=$(aws ssm send-command \
  --instance-ids $EC2_IDS \
  --document-name "AWS-RunShellScript" \
  --comment "Run ethtool stats" \
  --parameters 'commands=["sudo ethtool -S '${IF_NAME}'"]' \
  --query "Command.CommandId" \
  --output text)
echo "# Command executed"
sleep 5
echo "# Command execution result - ${COMMAND_ID}"
aws ssm list-command-invocations --command-id ${COMMAND_ID} --details --output json | jq -r '.[][].InstanceId' \
| while read INSTANCE_ID; do
INSTANCE_ID=$(echo "$INSTANCE_ID" | tr -d '\n')
OUTPUT=$(aws ssm get-command-invocation --command-id ${COMMAND_ID} --instance-id ${INSTANCE_ID} \
--query "StandardOutputContent" --output text)
NR_TOTAL=$(echo "$OUTPUT" | wc -l)
echo "$OUTPUT" | sed 's/^[[:space:]]*//' | awk -F: -v NR_TOTAL="$NR_TOTAL" -v instance="$INSTANCE_ID" '
  BEGIN { print "{" }
  NR==1 {
    gsub(/ /, "_", $0);
    if ($1 == "NIC_statistics") {
      printf "\"%s\": {\n", instance
    } else {
      printf "\"%s\": {\n", $1
    }
    next
  }
  {
    gsub(/^[[:space:]]*/, "", $1);
    gsub(/^[[:space:]]*/, "", $2);
    gsub(/ /, "_", $1);
    gsub(/ /, "_", $2);
    printf "\"%s\": %s", $1, $2
    if (NR!=NR_TOTAL) { printf ",\n" }
  }
  END {
    print ""
    print "} }"
  }
' | jq --unbuffered -r 'to_entries[0]' | jq -s '.' | tee -a "${COMMAND_ID}_${AWS_ACCOUNT}-${EXECUTION_TIME}.json"
done
jq -r '
map({InstanceId: .key} + .value) as $rows
| (["InstanceId"] + ($rows | map(keys) | add | unique | map(select(. != "InstanceId")))) as $cols
| $cols,
  ($rows[] | [ $cols[] as $k | .[$k] // "" ])
| @csv
' "${COMMAND_ID}_${AWS_ACCOUNT}-${EXECUTION_TIME}.json" > "${COMMAND_ID}_${AWS_ACCOUNT}-${EXECUTION_TIME}.csv"
ls "${COMMAND_ID}_${AWS_ACCOUNT}-${EXECUTION_TIME}.*"
