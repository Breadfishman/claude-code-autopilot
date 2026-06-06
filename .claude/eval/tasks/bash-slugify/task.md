Fix `slugify.sh` so it converts its first argument into a URL slug:

- lowercase everything
- every run of non-alphanumeric characters becomes a single hyphen
- no leading or trailing hyphen

Examples: `Hello World!` -> `hello-world`, `Foo_Bar.Baz` -> `foo-bar-baz`.
