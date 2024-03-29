{
  description = "Docker container with Moodle build by Nix";

  nixConfig = {
    substituters = [ "https://cache.nixos.intr/" ];
    trustedPublicKeys = [ "cache.nixos.intr:6VD7bofl5zZFTEwsIDsUypprsgl7r9I+7OGY4WsubFA=" ];
  };

  inputs = {
    deploy-rs.url = "github:serokell/deploy-rs";
    flake-compat = { url = "github:edolstra/flake-compat"; flake = false; };
    flake-utils.url = "github:numtide/flake-utils";
    majordomo.url = "git+https://gitlab.intr/_ci/nixpkgs";
    containerImageApache.url = "git+https://gitlab.intr/webservices/apache2-php73.git";
    moodle-language.url = "git+https://gitlab.intr/apps/moodle-language.git";
  };

  outputs = { self, flake-utils, nixpkgs, majordomo, deploy-rs, moodle-language, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: {
      devShell = with nixpkgs.legacyPackages."${system}"; mkShell {
        buildInputs = [
          nixUnstable
          deploy-rs.outputs.packages.${system}.deploy-rs
        ];
        shellHook = ''
          . ${nixUnstable}/share/bash-completion/completions/nix
          export LANG=C
        '';
      };
    }) // (
      let
        system = "x86_64-linux";
        tests = { driver ? false }: with nixpkgs.legacyPackages.${system}; { } // (with nixpkgs.legacyPackages.${system}.lib;
          listToAttrs (map
            (test: nameValuePair "moodle-${test.name}" (if driver then test.driver else test))
            (import ./tests.nix {
              inherit (majordomo.outputs) nixpkgs;
              inherit (import majordomo.inputs.nixpkgs {
                inherit system;
                overlays = [ majordomo.overlay ];
              }) maketestCms;
              containerImageCMS = self.packages.${system}.container;
              containerImageApache = inputs.containerImageApache.packages.${system}.container-master;
            })));
      in
        with nixpkgs.legacyPackages.${system}; {
          packages.${system} = {
            moodle = (callPackage ./pkgs/moodle { }).dist;
            moodle-language-pack-ru = moodle-language.packages.${system}.moodle-language-pack-ru;
            entrypoint = callPackage ./pkgs/entrypoint {
              inherit (self.packages.${system}) moodle moodle-language-pack-ru;
              php = majordomo.packages.${system}.php73;
            };
            container = callPackage ./. {
              inherit (self.packages.${system}) entrypoint;
              tag = self.packages.${system}.moodle.version;
            };
          } // (tests { driver = true; });
          defaultPackage.${system} = self.packages.${system}.container;
          checks.${system} = tests { };
          apps.${system}.vm = {
            type = "app";
            program = "${self.packages.${system}.moodle-vm-test-run-moodle-mariadb-nix-upstream}/bin/nixos-run-vms";
          };
          deploy.nodes.jenkins = {
            sshUser = "jenkins";
            autoRollback = false;
            magicRollback = false;
            hostname = "jenkins.intr";
            profiles = with nixpkgs.legacyPackages.${system}; {
              moodle = {
                path = deploy-rs.lib.${system}.activate.custom
                  (symlinkJoin {
                    name = "profile";
                    paths = [];
                  })
                  ((with self.packages.${system}.container; ''
                    #!${runtimeShell} -e
                    ${docker}/bin/docker load --input ${out}
                    ${docker}/bin/docker push ${imageName}:${imageTag}
                  ''));
              };
            };
          };
        }
    );
}
