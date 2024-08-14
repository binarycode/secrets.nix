{
  outputs = _: {
    nixosModules.default = import ./module.nix;
  };
}
