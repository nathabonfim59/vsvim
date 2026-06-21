.PHONY: major minor patch _bump current-version help

# Version bump targets: edit VERSION, commit, tag, then print the push command
# without pushing by themselves. The actual bump logic lives in _bump, which
# receives the bump type via TYPE.

major:
	@$(MAKE) --no-print-directory _bump TYPE=major

minor:
	@$(MAKE) --no-print-directory _bump TYPE=minor

patch:
	@$(MAKE) --no-print-directory _bump TYPE=patch

_bump:
	@set -eu; \
	if ! git diff --quiet || ! git diff --cached --quiet; then \
		echo "error: working tree has uncommitted changes; commit or stash first." >&2; \
		exit 1; \
	fi; \
	cur=$$(sed 's/-.*//' VERSION | tr -d '[:space:]'); \
	major=$${cur%%.*}; rest=$${cur#*.}; \
	minor=$${rest%%.*}; patch=$${rest#*.}; \
	[ "$$patch" = "$$rest" ] && patch=0; \
	case "$(TYPE)" in \
		major) major=$$((major + 1)); minor=0; patch=0 ;; \
		minor) minor=$$((minor + 1)); patch=0 ;; \
		patch) patch=$$((patch + 1)) ;; \
	esac; \
	new="$$major.$$minor.$$patch"; \
	printf '%s\n' "$$new" > VERSION; \
	git add VERSION; \
	git commit -m "chore: bump version to v$$new"; \
	git tag "v$$new"; \
	echo; \
	echo "Tagged v$$new. Push with:"; \
	echo "  git push origin main && git push origin v$$new"

current-version:
	@cat VERSION

help:
	@echo "vsvim Makefile targets:"
	@echo "  make major            Bump major version (X.0.0), commit, tag"
	@echo "  make minor            Bump minor version (x.Y.0), commit, tag"
	@echo "  make patch            Bump patch version (x.y.Z), commit, tag"
	@echo "  make current-version  Print the current VERSION file contents"
	@echo ""
	@echo "After bumping, push the commit and tag (not done automatically):"
	@echo "  git push origin main && git push origin vX.Y.Z"
