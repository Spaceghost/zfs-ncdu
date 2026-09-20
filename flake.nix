{
  description = "Browse ZFS space accounting in ncdu";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        zfs-ncdu = pkgs.callPackage ./package.nix { };
        default = zfs-ncdu;
      });

      checks = forAllSystems (pkgs: {
        # The package builds with its test suite enabled, so this covers both.
        zfs-ncdu = self.packages.${pkgs.stdenv.hostPlatform.system}.zfs-ncdu;

        busybox-awk = pkgs.runCommand "zfs-ncdu-busybox-awk" { } ''
          cd ${self}
          ${pkgs.busybox}/bin/busybox sh ./tests/run.sh "${pkgs.busybox}/bin/busybox awk"
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [ gawk mawk busybox ncdu shellcheck python3 ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
