#!/bin/bash
##########################################################################################
# This script enable CloudWatch Events and SNS Topics for Amazon GuardDuty in all regions.
##########################################################################################
# PREREQUISITES:
# * Enable Amazon GuardDuty in all supported regions. If you have multiple accounts,
#   we recommend to enable and link with "amazon-guardduty-multiaccount-scripts" from
#   aws-samples in GitHub.
# * AWS CLI is installed and configured with a profile name.
##########################################################################################
# VARIABLES:
# Please configure following variables before you run.
#
# AWS Account Name. This is a same profile name in your ~/.aws/credentials file.
# If you have multiple accounts and already linked member accounts to master account.
# Please put master account's profile name here.
prof_name="your-profile"
#
# AWS Account ID for the master account for GuardDuty
acct_id="123456789012"
#
# Default region for the account
def_region="us-east-1"
#
# Email Address to receive alerts
email_addr="you@company.com"
#
##########################################################################################
region_list=$(aws --profile ${prof_name} --output text --region $def_region ec2 \
describe-regions --query 'Regions[].{Name:RegionName}')

for region in ${region_list}
do
        detector_id=$(aws --profile ${prof_name} --output text --region ${region} \
        guardduty list-detectors )
        if [ -z "${detector_id}" ] ; then
                # Director is not created yet. We will not create SNS topics and \
                # CloudWatch Events here.
                echo "GuardDuty is not enabled in ${region}"
        else
                # GuardDuty detector exists in this region. We will create SNS topics \
                # and CloudWatch Events rule.
                echo "${prof_name} - ${region} - Derector ID: ${detector_id}"

                ####################
                # SNS
                ####################

                # sns create-topic
                echo "Creating SNS topic"
                aws --profile ${prof_name} --output text --region ${region} sns \
                create-topic --name GuardDuty-topic-${prof_name}-${region}

                # sns set-topic-attributes (creating DisplayName)
                echo "Setting topic attributes"
                aws --profile ${prof_name} --output json --region ${region} sns \
                set-topic-attributes --topic-arn \
                arn:aws:sns:${region}:${acct_id}:GuardDuty-topic-${prof_name}-${region} \
                --attribute-name DisplayName --attribute-value GuardDuty

		# sns set-topic-attributes (creating a policy)
		echo "Creating a policy to allow CloudWatch Events to publish to the SNS topic"
		aws --profile ${prof_name} --output text --region ${region} sns \
		set-topic-attributes --topic-arn \
		"arn:aws:sns:${region}:${acct_id}:GuardDuty-topic-${prof_name}-${region}" \
		--attribute-name Policy \
		--attribute-value "{\"Version\":\"2012-10-17\",\"Id\":\"__default_policy_ID\",\"Statement\":[{\"Sid\":\"__default_statement_ID\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":[\"SNS:GetTopicAttributes\",\"SNS:SetTopicAttributes\",\"SNS:AddPermission\",\"SNS:RemovePermission\",\"SNS:DeleteTopic\",\"SNS:Subscribe\",\"SNS:ListSubscriptionsByTopic\",\"SNS:Publish\",\"SNS:Receive\"],\"Resource\":\"arn:aws:sns:${region}:${acct_id}:GuardDuty-topic-${prof_name}-${region}\",\"Condition\":{\"StringEquals\":{\"AWS:SourceOwner\":\"${acct_id}\"}}}, {\"Sid\":\"TrustCWEToPublishEventsToMyTopic\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"events.amazonaws.com\"},\"Action\":\"sns:Publish\",\"Resource\":\"arn:aws:sns:${region}:${acct_id}:GuardDuty-topic-${prof_name}-${region}\"}]}"

                # sns subscribe
                echo "Subscribing topic"
                aws --profile ${prof_name} --output text --region ${region} sns subscribe \
                --topic-arn arn:aws:sns:${region}:${acct_id}:GuardDuty-topic-${prof_name}-${region} \
                --protocol email --notification-endpoint ${email_addr}

                # sns list-topics
                echo "listing topics"
                aws --profile ${prof_name} --output text --region ${region} sns list-topics

                # Pause 5 seconds
                sleep 5

                ####################
                # CloudWatch Events
                ####################

                # events put-rule
                echo "Creating CloudWatch Event rule"
                aws --profile ${prof_name} --output json --region ${region} events put-rule \
                --name "GuardDutyEventRule" --event-pattern "{\"source\":[\"aws.guardduty\"]}" \
                --state ENABLED --description GuardDutyEventRule

                # events put-targets
                echo "Putting target for the CloudWatch Events rule"
                aws --profile ${prof_name} --output json --region ${region} events put-targets --rule \
                GuardDutyEventRule --targets \
                "Id"="1","Arn"="arn:aws:sns:${region}:${acct_id}:GuardDuty-topic-${prof_name}-${region}"

                # events list-rules
                echo "listing CloudWatch Events rules"
                aws --profile ${prof_name} --output text --region ${region} events list-rules
        fi
done

