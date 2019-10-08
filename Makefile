ifeq ($(findstring clean,$(MAKECMDGOALS)),)
-include Makefile.config
endif

all: opam opam-installer
	@

ifeq ($(DUNE),)
  DUNE_EXE = src_ext/dune-local/_build_bootstrap/install/default/bin/dune$(EXE)
  ifeq ($(shell command -v cygpath 2>/dev/null),)
    DUNE := $(DUNE_EXE)
  else
    DUNE := $(shell echo "$(DUNE_EXE)" | cygpath -f - -a)
  endif
else
  DUNE_EXE=
endif

OPAMINSTALLER = ./opam-installer$(EXE)

ALWAYS:
	@

DUNE_PROMOTE_ARG := $(shell dune build --help=plain 2>/dev/null | sed -ne 's/.*\(--promote-install-files\).*/ \1/p')
DUNE_DEP = $(DUNE_EXE)
JBUILDER_ARGS ?= 
DUNE_ARGS ?= $(JBUILDER_ARGS)
DUNE_PROFILE ?= release

src_ext/dune-local/_build_bootstrap/install/default/bin/dune$(EXE): src_ext/dune-local.stamp
	cd src_ext/dune-local && ocaml bootstrap.ml && ./boot.exe --release

src_ext/dune-local.stamp:
	$(MAKE) -C src_ext dune-local.stamp

dune: $(DUNE_DEP)
	@$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS) @install

opam: $(DUNE_DEP) build-opam processed-opam.install
	$(LN_S) -f _build/default/src/client/opamMain.exe $@$(EXE)
ifneq ($(MANIFEST_ARCH),)
	@mkdir -p Opam.Runtime.$(MANIFEST_ARCH)
	@cp -f src/client/Opam.Runtime.$(MANIFEST_ARCH).manifest Opam.Runtime.$(MANIFEST_ARCH)/
	@cd Opam.Runtime.$(MANIFEST_ARCH) && $(LN_S) -f ../src/client/libstdc++-6.dll .
	@cd Opam.Runtime.$(MANIFEST_ARCH) && $(LN_S) -f ../src/client/libwinpthread-1.dll .
	@cd Opam.Runtime.$(MANIFEST_ARCH) && $(LN_S) -f ../src/client/$(RUNTIME_GCC_S).dll .
endif

opam-installer: $(DUNE_DEP) build-opam-installer processed-opam-installer.install
	$(LN_S) -f _build/default/src/tools/opam_installer.exe $@$(EXE)

opam-admin.top: ALWAYS $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS) src/tools/opam_admin_top.bc
	$(LN_S) -f _build/default/src/tools/opam_admin_top.bc $@$(EXE)

lib-ext:
	$(MAKE) -j -C src_ext lib-ext

lib-pkg:
	$(MAKE) -j -C src_ext lib-pkg

download-ext:
	$(MAKE) -C src_ext cache-archives

download-pkg:
	$(MAKE) -C src_ext archives-pkg

clean-ext:
	$(MAKE) -C src_ext distclean

clean:
	$(MAKE) -C doc $@
	rm -f *.install *.env *.err *.info *.out opam$(EXE) opam-admin.top$(EXE) opam-installer$(EXE)
	rm -rf _build Opam.Runtime.*

distclean: clean clean-ext
	rm -rf autom4te.cache bootstrap
	rm -f Makefile.config config.log config.status aclocal.m4
	rm -f src/*.META src/*/.merlin src/stubs/dune src/client/*.dll
	rm -f src/tools/opam-putenv.inc src/client/manifest.inc src/client/opamManifest.inc

OPAMINSTALLER_FLAGS = --prefix "$(DESTDIR)$(prefix)"
OPAMINSTALLER_FLAGS += --mandir "$(DESTDIR)$(mandir)"

# With ocamlfind, prefer to install to the standard directory rather
# than $(prefix) if there are no overrides
ifdef OCAMLFIND
ifndef DESTDIR
ifneq ($(OCAMLFIND),no)
    LIBINSTALL_DIR ?= $(shell PATH="$(PATH)" $(OCAMLFIND) printconf destdir)
endif
endif
endif

ifneq ($(LIBINSTALL_DIR),)
    OPAMINSTALLER_FLAGS += --libdir "$(LIBINSTALL_DIR)"
endif

opam-devel.install: $(DUNE_DEP)
	$(DUNE) build $(DUNE_ARGS) -p opam opam.install
	sed -e "s/bin:/libexec:/" opam.install > $@

opam-%.install: $(DUNE_DEP)
	$(DUNE) build $(DUNE_ARGS) -p opam-$* $@

.PHONY: build-opam-installer
build-opam-installer: $(DUNE_DEP) 
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS)$(DUNE_PROMOTE_ARG) opam-installer.install
opam-installer.install: $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS)$(DUNE_PROMOTE_ARG) opam-installer.install

.PHONY: build-opam
build-opam: $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS)$(DUNE_PROMOTE_ARG) opam-installer.install opam.install
opam.install: $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS)$(DUNE_PROMOTE_ARG) opam-installer.install opam.install

OPAMLIBS = core format solver repository state client

opam-%: $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS)$(DUNE_PROMOTE_ARG) opam-$*.install

opam-lib: $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS)$(DUNE_PROMOTE_ARG) $(patsubst %,opam-%.install,$(OPAMLIBS))

installlib-%: opam-installer opam-%.install
	$(if $(wildcard src_ext/lib/*),\
	  $(error Installing the opam libraries is incompatible with embedding \
	          the dependencies. Run 'make clean-ext' and try again))
	$(OPAMINSTALLER) $(OPAMINSTALLER_FLAGS) opam-$*.install

uninstalllib-%: opam-installer opam-%.install
	$(OPAMINSTALLER) -u $(OPAMINSTALLER_FLAGS) opam-$*.install

libinstall: $(DUNE_DEP) opam-admin.top $(OPAMLIBS:%=installlib-%)
	@

processed-%.install: %.install
	sed -f process.sed $^ > $@

install: processed-opam.install processed-opam-installer.install
	$(OPAMINSTALLER) $(OPAMINSTALLER_FLAGS) processed-opam.install
	$(OPAMINSTALLER) $(OPAMINSTALLER_FLAGS) processed-opam-installer.install

libuninstall: $(OPAMLIBS:%=uninstalllib-%)
	@

uninstall: opam.install
	$(OPAMINSTALLER) -u $(OPAMINSTALLER_FLAGS) $<
	$(OPAMINSTALLER) -u $(OPAMINSTALLER_FLAGS) opam-installer.install

checker:
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS) src/tools/opam_check.exe

.PHONY: tests tests-local tests-git
tests: $(DUNE_DEP)
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS) opam.install src/tools/opam_check.exe
	$(DUNE) build --profile=$(DUNE_PROFILE) $(DUNE_ARGS) doc/man/opam-topics.inc doc/man/opam-admin-topics.inc
	$(DUNE) runtest --force --no-buffer --profile=$(DUNE_PROFILE) $(DUNE_ARGS) src/ tests/

# tests-local, tests-git
tests-%:
	$(MAKE) -C tests $*

.PHONY: doc
doc: all
	$(MAKE) -C doc

.PHONY: man-html
man-html: opam opam-installer
	$(MAKE) -C doc $@

configure: configure.ac m4/*.m4
	aclocal -I m4
	autoconf

release-%:
	$(MAKE) -C release TAG="$*"

ifeq ($(OCAML_PORT),)
ifneq ($(COMSPEC),)
ifeq ($(shell which gcc 2>/dev/null),)
OCAML_PORT=auto
endif
endif
endif

.PHONY: compiler cold
compiler:
	env MAKE=$(MAKE) ./shell/bootstrap-ocaml.sh $(OCAML_PORT)

cold: compiler
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" ./configure --enable-cold-check $(CONFIGURE_ARGS)
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" $(MAKE) lib-ext
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" $(MAKE)

cold-%:
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" $(MAKE) $*

.PHONY: run-appveyor-test
run-appveyor-test:
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" ./appveyor_test.sh
