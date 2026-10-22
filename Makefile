.PHONY: sync lint test ios-test

sync:          ## install the Python workspace for this machine
	uv sync

lint:
	uv run ruff check .

test:
	uv run pytest -q

ios-test:      ## Swift library targets, no Xcode needed
	cd apps/ios && swift test
