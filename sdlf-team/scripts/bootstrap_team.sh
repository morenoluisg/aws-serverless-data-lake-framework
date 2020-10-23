#!/bin/bash
DIRNAME=$(pwd)
TEAM_NAME=$(sed -e 's/^"//' -e 's/"$//' <<<"$(jq '.[] | select(.ParameterKey=="pTeamName") | .ParameterValue' ${DIRNAME}/../parameters-${ENV}.json)")

function bootstrap_team_repository()
{
  TEAM=${1}
  TEMPLATE_REPOSITORY=${2}
  TEAM_REPOSITORY=sdlf-${TEAM}-$(cut -d'-' -f2 <<<${TEMPLATE_REPOSITORY})
  set +e
  OUTPUT=$(aws codecommit create-repository --repository-name ${TEAM_REPOSITORY} 2>&1)
  STATUS=$?
  set -e
  if [ ${STATUS} -ne 0 ] ; then
      if [[ ${OUTPUT} == *"Repository named"* && ${OUTPUT} == *"already exists"* ]] ; then
          echo -e "\nRepository named ${TEAM_REPOSITORY} already exists.";
      else
          exit ${STATUS}
      fi
  else
      git clone --bare https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/${TEMPLATE_REPOSITORY}
      cd ${TEMPLATE_REPOSITORY}.git/
      git push --mirror https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/${TEAM_REPOSITORY}
      cd ../ && rm -rf ${TEMPLATE_REPOSITORY}.git
  fi
}

declare -a REPOSITORIES=("sdlf-pipeline" "sdlf-dataset" "sdlf-datalakeLibrary" "sdlf-pipLibrary" "sdlf-stageA" "sdlf-stageB")
for REPOSITORY in "${REPOSITORIES[@]}"
do
  bootstrap_team_repository ${TEAM_NAME} ${REPOSITORY}
done

CHILD_ACCOUNT=$(sed -e 's/^"//' -e 's/"$//' <<<"$(aws ssm get-parameter --name /SDLF/Misc/${ENV}/AccountId --query "Parameter.Value")")
echo "Checking if stack exists ..."
STACK_NAME=sdlf-crossaccount-role-${ENV}-${TEAM_NAME}
if ! aws cloudformation describe-stacks --stack-name ${STACK_NAME}; then
  echo -e "Stack does not exist, creating ..."
  aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --parameters \
        ParameterKey=pChildAccountId,ParameterValue="${CHILD_ACCOUNT}" \
        ParameterKey=pEnvironment,ParameterValue="${ENV}" \
        ParameterKey=pTeamName,ParameterValue="${TEAM_NAME}" \
    --template-body file://${DIRNAME}/template-team-repos.yaml \
    --tags file://${DIRNAME}/../tags.json \
    --capabilities "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND"

  echo "Waiting for stack to be created ..."
  aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME}
fi