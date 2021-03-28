#!/bin/bash

# Plan.out is binary file populated with "terraform plan -out plan.out"
# Use terraform show to read plan.out as text, and filter for resource change lines, output to file
terraform show -no-color plan.out | grep "will be" > plan_decoded.out
terraform show -no-color plan.out | grep "must be" >> plan_decoded.out
input="plan_decoded.out"

# These resource types are always unsafe to modify, destroy, and replace
# Creation of new resources doesn't consult this list
# If a resource in this list will be modified or destroyed, an env review is triggered
declare -a ResourceTypesAlwaysUnsafe=(
    "aws_instance"
    "foobar"
)

# These resource types are always safe to modify and destroy
# Creation of new resources doesn't consult this list
# If a resource in this list will be modified or destroyed, an env review is not triggered
declare -a ResourceTypesAlwaysSafe=(
    "aws_security_group_rule"
    "foobar"
)

# Check if any resources changed. If no, immediately exit
if terraform show plan.out | grep -q " 0 to add, 0 to change, 0 to destroy"; then 
    echo "##[section]No changes detected, terraform apply will not run";
    # There are no changes
    exit 0
fi

# If any resources added, modified, or deleted, use logic
# Read terraform plan file
while IFS= read -r line; do

    # Set approvalRequired
    approvalRequired="notSure"

    # Prepare resource path, e.g.: module.networking.aws_security_group_rule.Inbound_192Slash16_PermitAll
    resource_path=$(echo $line | cut -d " " -f 2)
    # Prepare resource type, e.g.: aws_security_group_rule
    resource_type=$(echo $resource_path | rev | cut -d "." -f 2 | rev)

    # Resources which are destroyed
    if [[ $line == *"destroyed"* ]]; then

        # If destroyed resource is always unsafe, trigger approval
        if [[ ${ResourceTypesAlwaysUnsafe[@]} =~ ${resource_type} ]]; then
            # Mark this path unsafe, require approval
            echo "This resource is planned to be deleted, and is always unsafe to destroy without approval:" $resource_path
            approvalRequired="yes"

        # If destroyed resource is always safe, then don't trigger approval
        elif [[ ${ResourceTypesAlwaysSafe[@]} =~ ${resource_type} ]]; then
            echo "This resource is planned to be deleted, but is marked safe to destroy without approval:" $resource_path
            approvalRequired="no"

        # If destroyed resource isn't handled already, then
        else
            echo "Approval required on" $resource_path
            approvalRequired="yes"
        fi
    fi

    # Resources which are replaced
    if [[ $line == *"replaced"* ]]; then

        # If replaced resource is always unsafe, trigger approval
        if [[ ${ResourceTypesAlwaysUnsafe[@]} =~ ${resource_type} ]]; then
            # Mark this path unsafe, require approval
            echo "This resource is planned to be replaced, and is always unsafe to replace without approval:" $resource_path
            approvalRequired="yes"

        # If replaced resource is always safe, then don't trigger approval
        elif [[ ${ResourceTypesAlwaysSafe[@]} =~ ${resource_type} ]]; then
            echo "This resource is planned to be replaced, but is marked safe to replace without approval:" $resource_path
            approvalRequired="no"

        # If replaced resource isn't handled already, then
        else
            echo "Approval required on" $resource_path
            approvalRequired="yes"
        fi
    fi

    # Resources which are updated
    if [[ $line == *"updated"* ]]; then

        # If updated resource is always unsafe, trigger approval
        if [[ ${ResourceTypesAlwaysUnsafe[@]} =~ ${resource_type} ]]; then
            # Mark this path unsafe, require approval
            echo "This resource is planned to be deleted, but is always unsafe to destroy without approval:" $resource_path
            approvalRequired="yes"

        # If updated resource is always safe, then don't trigger approval
        elif [[ ${ResourceTypesAlwaysSafe[@]} =~ ${resource_type} ]]; then
            # Mark this path safe, do not require approval
            echo "This resource is planned to be deleted, but is marked safe to destroy without approval:" $resource_path
            approvalRequired="no"

        # If updated resource isn't handled already, then
        else
            echo "Normal policies apply on" $resource_path ", approval will not be required"
            approvalRequired="no"
        fi
    fi

    # Resources which are created
    if [[ $line == *"created"* ]]; then
        echo "##[section]Approval not required for" $resource_path
        approvalRequired="no"
    fi

    # If approval required, exit immediately and export values
    if [[ $approvalRequired == "yes" ]]; then
        echo "****************************************"
        echo "##[section]Approval will be required"
        echo "****************************************"
        echo ""
        echo "##vso[task.setvariable variable=approvalRequired;isOutput=true]true"
        echo ""
        echo ""
        break
    
    # If approval not required, continue
    elif [[ $approvalRequired == "no" ]]; then
        # Can't declare all good here until all lines evaluated, so removed from while loop
        # After loop, will gather info and make positive approval choice
        continue
    
    # If we haven't made a choice here yet, something has gone wrong, exit
    elif [[ $approvalRequired == "notSure" ]]; then
        echo "##[error]Something has gone wrong, can't determine"
        echo "##[error]Exiting, approval will be required to apply"
        exit 1
    
    # Shouldn't reach here
    else
        echo "##[error]Something has gone wrong, can't determine"
        echo "##[error]Exiting, approval will be required to apply"
        exit 1
    fi

done < $input

# If all lines evaluated, and we still haven't decided to require approval, then all
#  resources have been checked and none triggered approval flow
if [[ $approvalRequired == "no" ]]; then
    echo "****************************************"
    echo "##[section]Approval will not be required"
    echo "****************************************"
    echo "##vso[task.setvariable variable=approvalRequired;isOutput=true]false"
    echo ""
    echo ""
fi
