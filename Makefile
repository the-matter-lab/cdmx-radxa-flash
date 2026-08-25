.PHONY: test shellcheck

test:
	./tests/host/imager_test.sh
	./tests/host/network_monitor_test.sh
	python3 -m unittest tests/test_network_portal.py
	python3 -m unittest tests/test_imager_app.py
	python3 -m unittest tests/test_manifest_metadata.py
	python3 -m py_compile host/imager_app.py device/network/network_portal.py device/desktop/reset-workshop.py
	@for file in $$(find host device site -type f \( -name '*.sh' -o -name cdmx-network \)); do bash -n "$$file"; done

shellcheck:
	shellcheck -x --exclude=SC1091 host/*.sh host/lib/*.sh site/*.sh device/*.sh device/*/*.sh device/network/cdmx-network tests/host/*.sh
