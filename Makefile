SHELL := /bin/bash

PACKAGE ?= configuration-aws-network
XRD_DIR := apis/networks
COMPOSITION := $(XRD_DIR)/composition.yaml
DEFINITION := $(XRD_DIR)/definition.yaml
EXAMPLE_DEFAULT := examples/networks/example-minimal.yaml
RENDER_TESTS := $(wildcard tests/test-*)
E2E_TESTS := $(wildcard tests/e2etest-*)

# Examples list - mirrors GitHub Actions workflow
# Format: example_path::observed_resources_path (observed_resources_path is optional)
EXAMPLES := \
    examples/networks/example-minimal.yaml:: \
    examples/networks/example-minimal.yaml::examples/observed-resources/example-minimal/steps/1 \
    examples/networks/example-dual-stack.yaml:: \
    examples/networks/example-enterprise.yaml:: \
    examples/networks/example-manual-cidr.yaml:: \
    examples/networks/example-private-only.yaml:: \
    examples/networks/example-ipam-subnets.yaml:: \
    examples/networks/example-ipam-subnets.yaml::examples/observed-resources/example-ipam-subnets/steps/1 \
    examples/networks/example-ipam-subnets-ondemand.yaml:: \
    examples/networks/example-ipam-subnets-ondemand.yaml::examples/observed-resources/example-ipam-subnets-ondemand/steps/1 \
    examples/networks/example-ipam-subnets-ondemand.yaml::examples/observed-resources/example-ipam-subnets-ondemand/steps/2 \
    examples/networks/example-ipam-subnets-ondemand.yaml::examples/observed-resources/example-ipam-subnets-ondemand/steps/3

clean:
	rm -rf _output
	rm -rf .up

build:
	up project build

# Render all examples
render\:all:
	@for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; \
		observed=$${entry#*::}; \
		if [ -n "$$observed" ]; then \
			echo "=== Rendering $$example with observed-resources $$observed ==="; \
			up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example --observed-resources=$$observed; \
		else \
			echo "=== Rendering $$example ==="; \
			up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example; \
		fi; \
		echo ""; \
	done

# Validate all examples
validate\:all:
	@for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; \
		observed=$${entry#*::}; \
		if [ -n "$$observed" ]; then \
			echo "=== Validating $$example with observed-resources $$observed ==="; \
			up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
				--observed-resources=$$observed --include-full-xr --quiet | \
				crossplane beta validate $(XRD_DIR) --error-on-missing-schemas -; \
		else \
			echo "=== Validating $$example ==="; \
			up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
				--include-full-xr --quiet | \
				crossplane beta validate $(XRD_DIR) --error-on-missing-schemas -; \
		fi; \
		echo ""; \
	done

# Shorthand aliases
render: render\:all
validate: validate\:all

# Single example render (usage: make render:example-minimal)
render\:%:
	@example="examples/networks/$*.yaml"; \
	if [ -f "$$example" ]; then \
		echo "=== Rendering $$example ==="; \
		up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example; \
	else \
		echo "Example $$example not found"; \
		exit 1; \
	fi

# Single example validate (usage: make validate:example-minimal)
validate\:%:
	@example="examples/networks/$*.yaml"; \
	if [ -f "$$example" ]; then \
		echo "=== Validating $$example ==="; \
		up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
			--include-full-xr --quiet | \
			crossplane beta validate $(XRD_DIR) --error-on-missing-schemas -; \
	else \
		echo "Example $$example not found"; \
		exit 1; \
	fi

test:
	up test run $(RENDER_TESTS)

e2e:
	up test run $(E2E_TESTS) --e2e

publish:
	@if [ -z "$(tag)" ]; then echo "Error: tag is not set. Usage: make publish tag=<version>"; exit 1; fi
	up project build --push --tag $(tag)

generate-definitions:
	up xrd generate $(EXAMPLE_DEFAULT)

generate-function:
	up function generate --language=go-templating render $(COMPOSITION)
