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

## Firebase Auth

The app uses Firebase Auth through the modular browser SDK.

To enable Google sign-in:

1. Create or open a Firebase project.
2. Register a Web app in Project settings.
3. Copy the Firebase config into `firebase-config.js`.
4. In Authentication > Sign-in method, enable Google.
5. Add your local and deployed domains under Authentication > Settings > Authorized domains.

For local development, `localhost` is usually already authorized.
