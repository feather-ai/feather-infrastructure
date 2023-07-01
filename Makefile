# Dev environment
export AWS_PROFILE=featherai

init_dev:
	@cd environments/dev && terraform init

plan_dev:
	@cd environments/dev && terraform plan -var-file="../../.local/dev.tfvars"

apply_dev:
	@cd environments/dev && terraform apply -var-file="../../.local/dev.tfvars"

destroy_dev:
	@cd environments/dev && terraform destroy -var-file="../../.local/dev.tfvars"