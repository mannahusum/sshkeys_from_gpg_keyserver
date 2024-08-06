{
  description = "Create a file with ssh-keys";

  # Nixpkgs / NixOS version to use.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    # gpg_public_key = {
    #   type = "file";
    #   url = "https://keys.openpgp.org/vks/v1/by-email/christian@wudika.de";
    # };
  };

  # outputs = { self, nixpkgs, gpg_public_key }:
  outputs = {
    self,
    nixpkgs,
  }: let
    # to work with older version of flakes
    lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";

    # Generate a user-friendly version number.
    version = builtins.substring 0 8 lastModifiedDate;

    # System types to support.
    supportedSystems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

    # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    # Nixpkgs instantiated for supported system types.
    nixpkgsFor = forAllSystems (system:
      import nixpkgs {
        inherit system;
        overlays = [self.overlay];
      });
  in {
    # A Nixpkgs overlay.
    overlay = final: prev: {
      ssh_public_keys = with final;
        stdenv.mkDerivation {
          name = "ssh_public_keys-${version}";

          unpackPhase = ''
            cp "$src" armored_public_key
          '';

          src = pkgs.fetchurl {
            url = "https://keys.openpgp.org/vks/v1/by-email/christian@wudika.de";
            sha256 = "sha256-Cbde+zzog36S56lhkTbYsJTB5pVeFxXLz+Fsg/mfglk=";
          };

          buildInputs = [
            gnupg
          ];

          buildPhase = ''
            declare -a TO_DELETE=()
            trap cleanup_on_exit EXIT

            cleanup_on_exit() {
              for tempfile in "''${TO_DELETE[@]}"; do
                rm -rf "''${tempfile}"
              done
            }

            delete_and_forget() {
              local filename="''${1}"; shift
              local i

              rm -rf "''${filename}"

              for i in "''${!TO_DELETE[@]}"; do
                if [[ ''${TO_DELETE[i]} = "$filename" ]]; then
                  unset 'TO_DELETE[i]'
                fi
              done
            }

            line_to_keyid() {
              local line="''${1}"; shift
              local keypattern='.*/([0-9A-Z]+) '

              [[ $line =~ $keypattern ]]
              echo -n "''${BASH_REMATCH[1]}"
            }

            extract_ssh_public_keys() {
              local gpg_public_key="''${1}"; shift
              local ssh_keys="''${1}"; shift
              local keyline
              local gpgdir
              gpgdir="$(mktemp -d)"
              TO_DELETE+=("''${gpgdir}")

              gpg --quiet --homedir "''${gpgdir}" --import "''${gpg_public_key}"
              while read -r keyline; do
                gpg --homedir "''${gpgdir}" --export-ssh-key "$(line_to_keyid "''${keyline}")!" >>"''${ssh_keys}"
              done < <(gpg --homedir "''${gpgdir}" --list-public-keys --keyid-format LONG | grep '\[A\]')
              delete_and_forget "''${gpgdir}"
            }

            main() {
              extract_ssh_public_keys armored_public_key authorized_keys
            }

            main
          '';

          installPhase = ''
            cp authorized_keys $out
          '';
        };
    };

    # Provide some binary packages for selected system types.
    packages = forAllSystems (system: {
      inherit (nixpkgsFor.${system}) ssh_public_keys;
    });

    # The default package for 'nix build'. This makes sense if the
    # flake provides only one package or there is a clear "main"
    # package.
    defaultPackage = forAllSystems (system: self.packages.${system}.ssh_public_keys);

    # A NixOS module, if applicable (e.g. if the package provides a system service).
    devShell = forAllSystems (
      system: let
        pkgs = nixpkgsFor.${system};
      in
        pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            git
            statix
            alejandra
          ];
        }
    );
  };
}
