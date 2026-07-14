SHELL=/bin/bash
WHEELDIR ?= /tmp/wheelhouse
ST2_COMPONENT := $(notdir $(CURDIR))
ST2PKG_RELEASE ?= 1

OS_ID := $(shell source /etc/os-release; echo $$ID)
# Major OS version is sufficient.
OS_VERSION := $(shell source /etc/os-release; echo $${VERSION_ID%.*})

PYBIN := python3
PIPBIN := pip3

ifeq ($(OS_ID),rocky)
	EL_VERSION := $(OS_VERSION)
	# Rocky9 requires py3.11 instead of default py3.9 interpreter.
	ifeq ($(OS_VERSION),9)
		PYBIN = python3.11
	endif
else ifeq ($(OS_ID),rhel)
	EL_VERSION := $(OS_VERSION)
else ifeq ($(OS_ID),ubuntu)
	DEB_DISTRO := $(shell source /etc/os-release; echo $$VERSION_CODENAME)
	DESTDIR ?= $(CURDIR)/debian/$(ST2_COMPONENT)
else ifeq ($(OS_ID),debian)
	DEB_DISTRO := $(shell source /etc/os-release; echo $$VERSION_CODENAME)
	DESTDIR ?= $(CURDIR)/debian/$(ST2_COMPONENT)
else
	echo "$(OS_ID) is not supported."
	exit 1
endif


# Moved from top of file to handle when only py2 or py3 available
ST2PKG_VERSION ?= $(shell $(PYBIN) -c "from $(ST2_COMPONENT) import __version__; print(__version__),")

# Note: We dynamically obtain the version, this is required because dev
# build versions don't store correct version identifier in __init__.py
# and we need setup.py to normalize it (e.g. 1.4dev -> 1.4.dev0)
ST2PKG_NORMALIZED_VERSION ?= $(shell $(PYBIN) setup.py --version || echo "failed_to_retrieve_version")

.PHONY: info
info:
	@echo "DEB_DISTRO=$(DEB_DISTRO)"
	@echo "DESTDIR=$(DESTDIR)"
	@echo "EL_VERSION=$(EL_VERSION)"
	@echo "PYTHON_BINARY=$(PYBIN)"
	@echo "PIP_BINARY=$(PIPBIN)"
	@$(PYBIN) --version
	@$(PIPBIN) --version


.PHONY: populate_version requirements wheelhouse bdist_wheel
all: info populate_version requirements bdist_wheel

populate_version: .stamp-populate_version
.stamp-populate_version:
	# populate version should be run before any pip/setup.py works
	sh ../scripts/populate-version.sh
	touch $@

requirements: .stamp-requirements
.stamp-requirements:
	$(PYBIN) ../scripts/fixate-requirements.py -s in-requirements.txt -f ../fixed-requirements.txt
	cat requirements.txt

wheelhouse: .stamp-wheelhouse
.stamp-wheelhouse: | populate_version requirements
	# Install wheels into shared location
	cat requirements.txt
	# Try to install wheels 2x in case the first one fails
	$(PIPBIN) wheel --wheel-dir=$(WHEELDIR) --find-links=$(WHEELDIR) -r requirements.txt || \
	$(PIPBIN) wheel --wheel-dir=$(WHEELDIR) --find-links=$(WHEELDIR) -r requirements.txt
	touch $@

bdist_wheel: .stamp-bdist_wheel
.stamp-bdist_wheel: | populate_version requirements inject-deps
	cat requirements.txt

	$(PYBIN) -m build --wheel --outdir $(WHEELDIR) || \
	$(PYBIN) -m build --wheel --outdir $(WHEELDIR)
	touch $@

# Note: We want to dynamically inject "st2client" dependency. This way we can
# pin it to the version we build so the requirement is satisfied by locally
# built wheel and not version from PyPi
inject-deps: .stamp-inject-deps
.stamp-inject-deps:
	echo "st2client==$(ST2PKG_NORMALIZED_VERSION)" >> requirements.txt
	touch $@
