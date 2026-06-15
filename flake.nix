{
  description = "contabilizar development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems =
        function:
        nixpkgs.lib.genAttrs supportedSystems (system: function (import nixpkgs { inherit system; }));

      mkScripts = pkgs: [
        (pkgs.writeShellScriptBin "build" ''
          exec elm make src/Main.elm --output=public/elm.js
        '')
        (pkgs.writeShellScriptBin "update-rules" ''
          exec env GOOGLE_APPLICATION_CREDENTIALS=.secrets/contabilizar-admin-api.json \
            node scripts/deploy-firestore-rules.cjs contabilizar-78c2d firestore.rules
        '')
        (pkgs.writeShellScriptBin "start-local" ''
          exec python3 -m http.server 8008 -d $(git rev-parse --show-toplevel)/public
        '')
      ];
    in
    {
      apps = forAllSystems (pkgs: {
        build = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "build" "exec elm make src/Main.elm --output=public/elm.js"}/bin/build";
        };
        update-rules = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "update-rules" "exec env GOOGLE_APPLICATION_CREDENTIALS=.secrets/contabilizar-admin-api.json node scripts/deploy-firestore-rules.cjs contabilizar-78c2d firestore.rules"}/bin/update-rules";
        };
        start-local = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "start-local" "exec python3 -m http.server 8008 -d $(git rev-parse --show-toplevel)/public"}/bin/start-local";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              elmPackages.elm
              elmPackages.elm-format
              elmPackages.elm-test
              elmPackages.elm-review
              firebase-tools
              nodejs_22
              pnpm
              prettier
              prettierd
              nil
              zed-editor
              python314
            ]
            ++ mkScripts pkgs;

          shellHook = ''
            export NODE_PATH=${pkgs.firebase-tools}/lib/node_modules:${pkgs.firebase-tools}/lib/node_modules/firebase-tools/node_modules
            echo "Elm accounting app dev shell"
            echo "Available: build, update-rules, start-local, elm, elm-format, elm-test, elm-review, firebase, node, pnpm, prettier"
          '';
        };
      });
    };
}
