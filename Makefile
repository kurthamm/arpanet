# ARPANET lab — top-level make targets.

.PHONY: check verify-routing

# Regression gate: assert every visitor session routes THROUGH the IMP network
# (no terminal-line bypass) and each host actually answers @L. Requires the lab
# to be running (./mini/arpanet-recover.sh recover first if it isn't).
check: verify-routing

verify-routing:
	@bash mini/verify-imp-routing.sh
