# Copyright 2021 Adam Chalkley
#
# https://github.com/atc0005/query-meta
#
# Licensed under the MIT License. See LICENSE file in the project root for
# full license information.

# References:
#
# https://golang.org/cmd/go/#hdr-Compile_packages_and_dependencies
# https://github.com/mapnik/sphinx-docs/blob/master/Makefile
# https://stackoverflow.com/questions/23843106/how-to-set-child-process-environment-variable-in-makefile
# https://stackoverflow.com/questions/3267145/makefile-execute-another-target
# https://unix.stackexchange.com/questions/124386/using-a-make-rule-to-call-another
# https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html
# https://www.gnu.org/software/make/manual/html_node/Recipe-Syntax.html#Recipe-Syntax
# https://www.gnu.org/software/make/manual/html_node/Special-Variables.html#Special-Variables
# https://danishpraka.sh/2019/12/07/using-makefiles-for-go.html
# https://gist.github.com/subfuzion/0bd969d08fe0d8b5cc4b23c795854a13
# https://stackoverflow.com/questions/10858261/abort-makefile-if-variable-not-set
# https://stackoverflow.com/questions/38801796/makefile-set-if-variable-is-empty

SHELL = /bin/bash

# Space-separated list of cmd/BINARY_NAME directories to build
WHAT 					= qm

# TODO: This will need to be standardized across all cmd files in order to
# work as intended.
#
# What package holds the "version" variable used in branding/version output?
# VERSION_VAR_PKG			= $(shell go list .)
VERSION_VAR_PKG			= $(shell go list .)/internal/config
# VERSION_VAR_PKG			= main

OUTPUTDIR 				= release_assets

# https://gist.github.com/TheHippo/7e4d9ec4b7ed4c0d7a39839e6800cc16
VERSION 				= $(shell git describe --always --long --dirty)

# The default `go build` process embeds debugging information. Building
# without that debugging information reduces the binary size by around 28%.
#
# We also include additional flags in an effort to generate static binaries
# that do not have external dependencies. As of Go 1.15 this still appears to
# be a mixed bag, so YMMV.
#
# See https://github.com/golang/go/issues/26492 for more information.
#
# -s
#	Omit the symbol table and debug information.
#
# -w
#	Omit the DWARF symbol table.
#
# -tags 'osusergo,netgo'
#	Use pure Go implementation of user and group id/name resolution.
#	Use pure Go implementation of DNS resolver.
#
# -extldflags '-static'
#	Pass 'static' flag to external linker.
#
# -linkmode=external
#	https://golang.org/src/cmd/cgo/doc.go
#
#   NOTE: Using external linker requires installation of `gcc-multilib`
#   package when building 32-bit binaries on a Debian/Ubuntu system. It also
#   seems to result in an unstable build that crashes on startup. This *might*
#   be specific to the WSL environment used for builds, but since this is a
#   new issue and and I do not yet know much about this option, I am leaving
#   it out.
#
# CGO_ENABLED=0
#	https://golang.org/cmd/cgo/
#	explicitly disable use of cgo
#	removes potential need for linkage against local c library (e.g., glibc)
BUILDCMD				=	CGO_ENABLED=0 go build -mod=vendor -trimpath -a -ldflags "-s -w -X $(VERSION_VAR_PKG).version=$(VERSION)"
GOCLEANCMD				=	go clean -mod=vendor ./...
GITCLEANCMD				= 	git clean -xfd
CHECKSUMCMD				=	sha256sum -b

.DEFAULT_GOAL := help

  ##########################################################################
  # Targets will not work properly if a file with the same name is ever
  # created in this directory. We explicitly declare our targets to be phony
  # by making them a prerequisite of the special target .PHONY
  ##########################################################################

.PHONY: help
## help: prints this help message
help:
	@echo "Usage:"
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

.PHONY: lintinstall
## lintinstall: install common linting tools
# https://github.com/golang/go/issues/30515#issuecomment-582044819
lintinstall:
	@echo "Installing linting tools"

	@export PATH="${PATH}:$(go env GOPATH)/bin"

	@echo "Explicitly enabling Go modules mode per command"
	(cd; GO111MODULE="on" go get honnef.co/go/tools/cmd/staticcheck)

	@echo Installing latest stable golangci-lint version per official installation script ...
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell go env GOPATH)/bin
	golangci-lint --version

	@echo "Finished updating linting tools"

.PHONY: linting
## linting: runs common linting checks
linting:
	@echo "Running linting tools ..."

	@echo "Running go vet ..."
	@go vet -mod=vendor $(shell go list -mod=vendor ./... | grep -v /vendor/)

	@echo "Running golangci-lint ..."
	@golangci-lint run

	@echo "Running staticcheck ..."
	@staticcheck $(shell go list -mod=vendor ./... | grep -v /vendor/)

	@echo "Finished running linting checks"

.PHONY: gotests
## gotests: runs go test recursively, verbosely
gotests:
	@echo "Running go tests ..."
	@go test -mod=vendor ./...
	@echo "Finished running go tests"

.PHONY: goclean
## goclean: removes local build artifacts, temporary files, etc
goclean:
	@echo "Removing object files and cached files ..."
	@$(GOCLEANCMD)
	@echo "Removing any existing release assets"
	@mkdir -p "$(OUTPUTDIR)"
	@rm -vf $(wildcard ${OUTPUTDIR}/*/*-linux-*)
	@rm -vf $(wildcard ${OUTPUTDIR}/*/*-windows-*)

.PHONY: clean
## clean: alias for goclean
clean: goclean

.PHONY: gitclean
## gitclean: WARNING - recursively cleans working tree by removing non-versioned files
gitclean:
	@echo "Removing non-versioned files ..."
	@$(GITCLEANCMD)

.PHONY: pristine
## pristine: run goclean and gitclean to remove local changes
pristine: goclean gitclean

.PHONY: all
# https://stackoverflow.com/questions/3267145/makefile-execute-another-target
## all: generates assets for Linux distros and Windows
all: clean windows linux
	@echo "Completed all cross-platform builds ..."

.PHONY: windows
## windows: generates assets for Windows systems
windows:
	@echo "Building release assets for windows ..."

	@for target in $(WHAT); do \
		mkdir -p $(OUTPUTDIR)/$$target && \
		echo "Building $$target 386 binaries" && \
		env GOOS=windows GOARCH=386 $(BUILDCMD) -o $(OUTPUTDIR)/$$target/$$target-$(VERSION)-windows-386.exe ${PWD}/cmd/$$target && \
		echo "Building $$target amd64 binaries" && \
		env GOOS=windows GOARCH=amd64 $(BUILDCMD) -o $(OUTPUTDIR)/$$target/$$target-$(VERSION)-windows-amd64.exe ${PWD}/cmd/$$target && \
		echo "Generating $$target checksum files" && \
		cd $(OUTPUTDIR)/$$target && \
		$(CHECKSUMCMD) $$target-$(VERSION)-windows-386.exe > $$target-$(VERSION)-windows-386.exe.sha256 && \
		$(CHECKSUMCMD) $$target-$(VERSION)-windows-amd64.exe > $$target-$(VERSION)-windows-amd64.exe.sha256 && \
		cd $$OLDPWD; \
	done

	@echo "Completed build tasks for windows"

.PHONY: linux
## linux: generates assets for Linux distros
linux:
	@echo "Building release assets for linux ..."

	@for target in $(WHAT); do \
		mkdir -p $(OUTPUTDIR)/$$target && \
		echo "Building $$target 386 binaries" && \
		env GOOS=linux GOARCH=386 $(BUILDCMD) -o $(OUTPUTDIR)/$$target/$$target-$(VERSION)-linux-386 ${PWD}/cmd/$$target && \
		echo "Building $$target amd64 binaries" && \
		env GOOS=linux GOARCH=amd64 $(BUILDCMD) -o $(OUTPUTDIR)/$$target/$$target-$(VERSION)-linux-amd64 ${PWD}/cmd/$$target && \
		echo "Generating $$target checksum files" && \
		cd $(OUTPUTDIR)/$$target && \
		$(CHECKSUMCMD) $$target-$(VERSION)-linux-386 > $$target-$(VERSION)-linux-386.sha256 && \
		$(CHECKSUMCMD) $$target-$(VERSION)-linux-amd64 > $$target-$(VERSION)-linux-amd64.sha256 && \
		cd $$OLDPWD; \
	done

	@echo "Completed build tasks for linux"
