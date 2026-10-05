check:
    cargo check --tests

lint:
    cargo clippy --tests -- -D warnings

test:
    cargo test

fmt:
    cargo fmt --all

lua-fmt:
    stylua --syntax luau --indent-type Spaces --indent-width 2 lua/ plugin/ tests/

lua-fmt-check:
    stylua --check --syntax luau --indent-type Spaces --indent-width 2 lua/ plugin/ tests/

lua-lint:
    selene lua/ plugin/ tests/

lua-test:
    lua tests/store.lua
    lua tests/ui.lua
