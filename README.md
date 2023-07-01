# Overview

Infrastructure-as-code repository for FeatherAI. You must be running Terraform 0.12.26
This repo follows the KISS principle. We support multiple environemnts, but simply via different
root folders. The root for each environment is in ./environments/name.

## Usage

Ensure you have valid AWS credentials.

    export AWS_PROFILE=featherai

All operations should be done via make, since it encapsulates the intricacies of supporting different environments.
For now, we support dev, so the commands are:

    make init_dev
    make plan_dev
    make apply_dev


