SHELL := /bin/bash

PACKAGE ?= configuration-aws-network
XRD_DIR := apis/networks
COMPOSITION := $(XRD_DIR)/composition.yaml
DEFINITION := $(XRD_DIR)/definition.yaml
EXAMPLE_DEFAULT := examples/networks/example-minimal.yaml
EXAMPLES := $(wildcard examples/networks/*.yaml)
RENDER_TESTS := $(wildcard tests/test-*)
E2E_TESTS := $(wildcard tests/e2etest-*)

clean:
	rm -rf _output
	rm -rf .up

build:
	up project build

render: render-example

render-example:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) $(EXAMPLE_DEFAULT)

render-all:
	@for example in $(EXAMPLES); do \
		echo "Rendering $$example"; \
		up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example; \
	done

render-example-minimal:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) examples/networks/example-minimal.yaml

render-example-private-only:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) examples/networks/example-private-only.yaml

render-example-manual-cidr:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) examples/networks/example-manual-cidr.yaml

render-example-dual-stack:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) examples/networks/example-dual-stack.yaml

render-example-enterprise:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) examples/networks/example-enterprise.yaml

test:
	up test run $(RENDER_TESTS)

validate: validate-composition validate-examples

validate-composition:
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) $(EXAMPLE_DEFAULT) --include-full-xr --quiet | crossplane beta validate $(XRD_DIR) --error-on-missing-schemas -

validate-examples:
	crossplane beta validate $(XRD_DIR) examples/networks

publish:
	@if [ -z "$(tag)" ]; then echo "Error: tag is not set. Usage: make publish tag=<version>"; exit 1; fi
	up project build --push --tag $(tag)

generate-definitions:
	up xrd generate $(EXAMPLE_DEFAULT)

e2e:
	up test run $(E2E_TESTS) --e2e
