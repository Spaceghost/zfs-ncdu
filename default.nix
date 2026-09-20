# Fallback for people not using flakes: nix-build
{ pkgs ? import <nixpkgs> { } }:
pkgs.callPackage ./package.nix { }
