PWD                           := $(shell pwd)
MYSELF                        := $(shell id -u)
MY_GROUP					  := $(shell id -g)
GOPATH                        := $(GOPATH)
ARTIFACTS_DIR                 := artifacts
COVERAGE_OUT                  := $(ARTIFACTS_DIR)/coverage.out
GO_FORMAT                     := gofmt -s -w
THIS                          := github.com/verygoodsoftwarenotvirus/tools
TOTAL_PACKAGE_LIST            := `go list $(THIS)/...`
TESTABLE_PACKAGE_LIST         := `go list $(THIS)/... | grep -Ev '(cmd|generated)'`
SQL_GENERATOR_IMAGE           := sqlc/sqlc:1.22.0
LINTER_IMAGE                  := golangci/golangci-lint:v1.54.2
CONTAINER_LINTER_IMAGE        := openpolicyagent/conftest:v0.45.0

## non-PHONY folders/files

clean:
	rm -rf $(ARTIFACTS_DIR)

$(ARTIFACTS_DIR):
	@mkdir --parents $(ARTIFACTS_DIR)

clean-$(ARTIFACTS_DIR):
	@rm -rf $(ARTIFACTS_DIR)

.PHONY: setup
setup: $(ARTIFACTS_DIR) revendor rewire

## prerequisites

.PHONY: ensure_fieldalignment_installed
ensure_fieldalignment_installed:
ifeq (, $(shell which fieldalignment))
	$(shell go install golang.org/x/tools/go/analysis/passes/fieldalignment/cmd/fieldalignment@latest)
endif

.PHONY: ensure_gci_installed
ensure_gci_installed:
ifeq (, $(shell which gci))
	$(shell go install github.com/daixiang0/gci@latest)
endif

.PHONY: ensure_tagalign_installed
ensure_tagalign_installed:
ifeq (, $(shell which tagalign))
	$(shell go install github.com/4meepo/tagalign/cmd/tagalign@latest)
endif

.PHONY: clean_vendor
clean_vendor:
	rm -rf vendor go.sum

vendor:
	if [ ! -f go.mod ]; then go mod init; fi
	go mod tidy
	go mod vendor
	for thing in $(CLOUD_FUNCTIONS); do \
  		(cd cmd/functions/$$thing && go mod tidy) \
	done
	for thing in $(CLOUD_JOBS); do \
  		(cd cmd/jobs/$$thing && go mod tidy) \
	done

.PHONY: revendor
revendor: clean_vendor vendor

## dependency injection

.PHONY: rewire
rewire:
	for tgt in $(WIRE_TARGETS); do \
		rm -f $(THIS)/internal/$$tgt/wire_gen.go && wire gen $(THIS)/internal/$$tgt; \
	done

## formatting

.PHONY: format
format: format_golang terraformat

.PHONY: format_golang
format_golang: format_imports ensure_fieldalignment_installed ensure_tagalign_installed
	@until fieldalignment -fix ./...; do true; done > /dev/null
	@until tagalign -fix -sort -order "json,toml" ./...; do true; done > /dev/null
	for file in `find $(PWD) -type f -not -path '*/vendor/*' -name "*.go"`; do $(GO_FORMAT) $$file; done

.PHONY: format_imports
format_imports: ensure_gci_installed
	gci write --skip-generated --section standard --section "prefix($(THIS))" --section "prefix($(dir $(THIS)))" --section default --custom-order `find $(PWD) -type f -not -path '*/vendor/*' -name "*.go"`

.PHONY: terraformat
terraformat:
	@touch environments/dev/terraform/service-config.json
	@touch environments/dev/terraform/worker-config.json
	@(cd environments/dev/terraform && terraform fmt)

.PHONY: lint_terraform
lint_terraform: terraformat
	@(cd environments/dev/terraform && terraform init -upgrade && terraform validate && terraform fmt && terraform fmt -check)

.PHONY: fmt
fmt: format terraformat

## Testing things

.PHONY: pre_lint
pre_lint:
	@until fieldalignment -fix ./...; do true; done > /dev/null
	@echo ""

.PHONY: lint_docker
lint_docker:
	@docker pull --quiet $(CONTAINER_LINTER_IMAGE)
	docker run --rm --volume $(PWD):$(PWD) --workdir=$(PWD) --user $(MYSELF):$(MY_GROUP) $(CONTAINER_LINTER_IMAGE) test --policy docker_security.rego `find . -type f -name "*.Dockerfile"`

.PHONY: golang_lint
golang_lint:
	@docker pull --quiet $(LINTER_IMAGE)
	docker run --rm \
		--volume $(PWD):$(PWD) \
		--workdir=$(PWD) \
		$(LINTER_IMAGE) golangci-lint run --config=.golangci.yml --timeout 15m ./...

.PHONY: lint
lint: lint_docker golang_lint

.PHONY: clean_coverage
clean_coverage:
	@rm --force $(COVERAGE_OUT) profile.out;

.PHONY: coverage
coverage: clean_coverage $(ARTIFACTS_DIR)
	@go test -coverprofile=$(COVERAGE_OUT) -shuffle=on -covermode=atomic -race $(TESTABLE_PACKAGE_LIST) > /dev/null
	@go tool cover -func=$(ARTIFACTS_DIR)/coverage.out | grep 'total:' | xargs | awk '{ print "COVERAGE: " $$3 }'

.PHONY: build
build:
	go build $(TOTAL_PACKAGE_LIST)

.PHONY: test
test: $(ARTIFACTS_DIR) vendor build
	go test -cover -shuffle=on -race -vet=all -failfast $(TESTABLE_PACKAGE_LIST)

## misc

.PHONY: tree
tree:
	# there are no longargs for tree, but d means "directories only" and I means "ignore pattern"
	tree -d -I vendor

.PHONY: line_count
line_count: ensure_scc_installed
	@scc --include-ext go --exclude-dir vendor
