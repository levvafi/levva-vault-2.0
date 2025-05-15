-include .env

.PHONY: help build test stageTest

help:
	@echo "Usage:"
	@echo "  make build"
	@echo ""
	@echo "  make test"
	@echo ""
	@echo "  make stageTest"

build :; forge build --sizes

test :; forge test -vvv

stageTest :; forge test -vvv --match-path "test/staging/*"

coverage :; forge coverage --no-match-coverage test
