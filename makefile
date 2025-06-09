-include .env

.PHONY: help build test stageTest

help:
	@echo "Usage:"
	@echo "  make build"
	@echo ""
	@echo "  make test"
	@echo ""
	@echo "  make coverage"


build :; forge build --sizes

test :; forge test -vvv

coverage :; forge coverage --no-match-coverage test

coverageReport :; forge coverage --no-match-coverage test --report debug > coverage.info
