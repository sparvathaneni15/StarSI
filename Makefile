.PHONY: sync lint test ios-test charts compose-up buildx

sync:          ## install the Python workspace (chflags: iCloud marks fresh .pth files hidden, which breaks site.py)
	uv sync --all-packages
	chflags -R nohidden .venv 2>/dev/null || true

lint:
	uv run ruff check blocks train

test: sync
	uv run pytest -q

ios-test:      ## Swift library targets, no Xcode needed (scratch path off iCloud)
	cd apps/ios && swift test --scratch-path /tmp/starsi-spm

charts:        ## lint + render every block chart
	@for c in blocks/*/chart; do \
		helm lint $$c --set authToken=x --set gpuInstanceId=i-x --quiet && \
		helm template t $$c --set authToken=x --set gpuInstanceId=i-x > /dev/null && \
		echo "chart OK: $$c" || exit 1; \
	done

compose-up:    ## local dev stack on the Mac (gateway + memory + llama.cpp stand-in)
	docker compose -f deploy/sites/mac/compose.yaml up --build

buildx:        ## multi-arch images for every block with a Dockerfile (needs a buildx builder)
	@for d in blocks/*/Dockerfile; do \
		b=$$(basename $$(dirname $$d)); \
		docker buildx build --platform linux/arm64,linux/amd64 -t starsi-$$b:dev $$(dirname $$d) || exit 1; \
	done
