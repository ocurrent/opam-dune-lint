### Unreleased

- Add support for dune 3.0 , the command `dune external-lib-deps` was removed from
  dune. Now, the `opam-dune-lint` command works without `dune build`. (@moyodiallo #46).
- Print all the errors before the exit (@moyodiallo #55).

### v0.2

- Cope with missing `(depends ...)` in `dune-project` (@talex5 #33). We tried to add the missing packages to an existing depends field, but if there wasn't one at all then we did nothing.

- Use quoted versions in the fix suggestion string (@tmcgilchrist #32). Makes copy-and-paste easier for people using it via a web UI.

- Support older versions of OCaml back to 4.10 (@tmcgilchrist #31).

- Ignore dependencies on sub-packages (@dra27 #27). Library `foo` may depend on library `foo.bar` but this cannot introduce an opam dependency on `foo` in `foo.opam`.

- Require opam libraries compatible with the client (@dra27 #26).

- Add support for multiple dependency clauses for the same package (@kit-ty-kate #25).

- Upgrade to dune-private-libs 2.8.0 (@kit-ty-kate #20).

- Remove dependency on ocamlfind, as we don't use it for anything now (@talex5 #18).

### v0.1

Initial release.
