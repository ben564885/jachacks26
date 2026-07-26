.PHONY: help setup test serve cli demo deploy notch install notch-test clean

help:
	@echo "Synqit — shared source control where a conflict becomes a question"
	@echo ""
	@echo "the system (graph, walkers, agent, GitHub I/O, CLI) — .jac at the repo root"
	@echo "  make setup       Create .jacvenv and install pinned jaclang/jac-scale/byllm"
	@echo "  make test        Type-check everything + run all six Jac suites (no keys needed)"
	@echo "  make serve       Serve every walker as a REST API on :8080"
	@echo "  make cli         Show the synqit CLI help (jac run cli.jac -- help)"
	@echo "  make demo        Scripted two-scenario walkthrough (needs OPENAI_API_KEY)"
	@echo "  make deploy      Redeploy the live Fly.io instance"
	@echo ""
	@echo "notch/ — the macOS escalation surface (Swift)"
	@echo "  make notch       Build Synqit Notch.app"
	@echo "  make install     Build and install it to /Applications"
	@echo "  make notch-test  Run the Swift test suite"
	@echo ""
	@echo "Live API: https://synqit-jac.fly.dev/graph"

# Idempotent: skips the reinstall if the venv already has the pinned versions.
setup:
	@( [ -d .jacvenv ] || python3.12 -m venv .jacvenv ) && \
	. .jacvenv/bin/activate && \
	( pip show jaclang 2>/dev/null | grep -q "0.16.7" \
	  && pip show jac-scale 2>/dev/null | grep -q "0.2.31" \
	  && pip show byllm 2>/dev/null | grep -q "0.6.19" \
	  || pip install -q "jaclang==0.16.7" "jac-scale==0.2.31" "byllm==0.6.19" "requests>=2.31.0" )
	@echo ".jacvenv ready"

# --ignore keeps the check off the Swift app, the Next.js site and the venv --
# none of them hold .jac modules, and landing/node_modules is enormous.
test: setup
	@echo "── jac ──"
	@. .jacvenv/bin/activate && \
	  jac check . --ignore .jacvenv --ignore notch --ignore landing --ignore docs && \
	  for suite in test_walkers test_conflict test_ingest test_identity test_escalation test_workspace; do \
	    echo "  → $$suite"; jac test $$suite.jac || exit 1; \
	  done

serve: setup
	@. .jacvenv/bin/activate && jac start main.jac

cli: setup
	@. .jacvenv/bin/activate && jac run cli.jac -- help

demo: setup
	@. .jacvenv/bin/activate && jac run demo.jac

deploy:
	@fly deploy -a synqit-jac

notch:
	@cd notch && $(MAKE) app

install:
	@cd notch && $(MAKE) install

notch-test:
	@echo "── notch ──"
	@cd notch && swift test

clean:
	@cd notch && $(MAKE) clean
	@rm -rf .jac
