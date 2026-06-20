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
          exec elm make src/Main.elm --output=public/elm.min.js
        '')
        (pkgs.writeShellScriptBin "build-release" ''
          set -euo pipefail
          echo "Compiling optimized Elm..."
          elm make src/Main.elm --output=public/elm.min.js --optimize
          echo "Compressing with uglifyjs..."
          uglifyjs public/elm.min.js --compress "pure_funcs='F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9',pure_getters,keep_fargs=false,unsafe_comps,unsafe" --timings --output public/elm.min.js
          echo "Mangling with uglifyjs..."
          uglifyjs public/elm.min.js --mangle --timings --output public/elm.min.js
          echo "Release build written to public/elm.min.js"
        '')
        (pkgs.writeShellScriptBin "deploy" ''
          exec ${pkgs.firebase-tools}/bin/firebase deploy --project contabilizar-78c2d
        '')
        (pkgs.writeShellScriptBin "update-rules" ''
          exec env GOOGLE_APPLICATION_CREDENTIALS=.secrets/contabilizar-admin-api.json
            ${pkgs.nodejs_22}/bin/node scripts/deploy-firestore-rules.cjs contabilizar-78c2d firestore.rules
        '')
        (pkgs.writeShellScriptBin "run-local" ''
          exec ${pkgs.python314}/bin/python3 -m http.server 8008 -d $(${pkgs.git}/bin/git rev-parse --show-toplevel)/public
        '')
        (pkgs.writeShellScriptBin "format" ''
          exec elm-format --elm-version 0.19 src/ tests/ "$@"
        '')
        (pkgs.writeShellScriptBin "test" ''
          exec elm-test
        '')
        (pkgs.writeShellScriptBin "review" ''
          exec elm-review --config review/ "$@"
        '')
      ];
    in
    {
      apps = forAllSystems (pkgs: {
        build = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "build" "exec ${pkgs.elmPackages.elm}/bin/elm make src/Main.elm --output=public/elm.min.js"}/bin/build";
        };
        build-release = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "build-release" ''
            set -euo pipefail
            echo "Compiling optimized Elm..."
            ${pkgs.elmPackages.elm}/bin/elm make src/Main.elm --output=public/elm.min.js --optimize
            echo "Compressing with uglifyjs..."
            ${pkgs.uglify-js}/bin/uglifyjs public/elm.min.js --compress "pure_funcs='F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9',pure_getters,keep_fargs=false,unsafe_comps,unsafe" --timings --output public/elm.min.js
            echo "Mangling with uglifyjs..."
            ${pkgs.uglify-js}/bin/uglifyjs public/elm.min.js --mangle --timings --output public/elm.min.js
            echo "Release build written to public/elm.min.js"
          ''}/bin/build-release";
        };
        deploy = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "deploy" "exec ${pkgs.firebase-tools}/bin/firebase deploy --project contabilizar-78c2d"}/bin/deploy";
        };
        update-rules = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "update-rules" "exec env GOOGLE_APPLICATION_CREDENTIALS=.secrets/contabilizar-admin-api.json ${pkgs.nodejs_22}/bin/node scripts/deploy-firestore-rules.cjs contabilizar-78c2d firestore.rules"}/bin/update-rules";
        };
        run-local = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "run-local" "exec ${pkgs.python314}/bin/python3 -m http.server 8008 -d $(${pkgs.git}/bin/git rev-parse --show-toplevel)/public"}/bin/run-local";
        };
        format = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "format" ''
            exec ${pkgs.elmPackages.elm-format}/bin/elm-format src/ tests/ "$@"
          ''}/bin/format";
        };
        test = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "test" "exec ${pkgs.elmPackages.elm-test}/bin/elm-test --compiler ${pkgs.elmPackages.elm}/bin/elm"}/bin/test";
        };
        review = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "review" ''
            exec ${pkgs.elmPackages.elm-review}/bin/elm-review --config review/ --compiler ${pkgs.elmPackages.elm}/bin/elm "$@"
          ''}/bin/review";
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
              google-cloud-sdk
              git
              nil
              nodejs_22
              pnpm
              prettier
              prettierd
              python314
              uglify-js
              zed-editor
            ]
            ++ mkScripts pkgs;

          shellHook = ''
            export NODE_PATH=${pkgs.firebase-tools}/lib/node_modules:${pkgs.firebase-tools}/lib/node_modules/firebase-tools/node_modules
            echo "Elm accounting app dev shell"
            echo "Available: build, build-release, deploy, format, review, run-local, test, update-rules, elm, firebase, git, node, pnpm, prettier, python3, uglify-js"
          '';
        };
      });
    };
}
