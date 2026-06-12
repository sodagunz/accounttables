# ContabilizAR

A lightweight accounting app in Elm.

## Development

Enter the Nix shell:

```sh
nix develop
```

Build the Elm app:

```sh
elm make src/Main.elm --output=elm.js
```

Serve the static page:

```sh
python3 -m http.server 8000
```

Then open <http://localhost:8000>.
