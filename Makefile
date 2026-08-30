.PHONY: test lint build scan sbom policy all clean

APP_DIR    := app
IMAGE      := zt-go-microservice:dev
DOCKERFILE := build/Dockerfile

test:                ## Go vet + unit tests with race detector
	cd $(APP_DIR) && go vet ./... && go test ./... -race -count=1

lint:                ## Hadolint the Dockerfile (Gate 2 preview)
	docker run --rm -i hadolint/hadolint hadolint \
	  --config build/.hadolint.yaml - < $(DOCKERFILE)

build:               ## Build the container image
	docker build -f $(DOCKERFILE) -t $(IMAGE) .

scan:                ## Trivy scan, fail on CRITICAL/HIGH (Gate 3 preview)
	trivy image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 $(IMAGE)

sbom:                ## Generate SPDX + CycloneDX SBOMs (Gate 4 preview)
	syft $(IMAGE) -o spdx-json=sbom.spdx.json
	syft $(IMAGE) -o cyclonedx-json=sbom.cyclonedx.json

policy:              ## Run Rego unit tests + fixtures (Gate 6 preview)
	opa test policy/ -v
	conftest test policy/tests/fixtures/compliant.json --policy policy/ --all-namespaces

verify-nonroot:      ## Prove the image runs as UID 65532 with no shell
	docker inspect $(IMAGE) --format 'User={{.Config.User}}'
	docker run --rm --entrypoint /bin/sh $(IMAGE) -c 'echo hi' || echo "GOOD: no shell"

all: test lint build scan sbom policy

clean:
	rm -f sbom.*.json *.sarif policy_input.json
