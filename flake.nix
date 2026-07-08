{
  description = "TheLoop705 dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, nixpkgs-linux }:
    let
      # The one username line to change if this is not your account.
      # bootstrap.sh offers to rewrite this for the current machine.
      user = "vpnuser";

      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];

      linuxTargetName = system:
        if system == "x86_64-linux" then "${user}@linux-x86_64"
        else if system == "aarch64-linux" then "${user}@linux-aarch64"
        else throw "Unsupported Linux system: ${system}";

      mkLinuxHome = system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs-linux {
            inherit system;
            config.allowUnfree = true;
          };
          extraSpecialArgs = {
            inherit user;
            homeDirectory = "/home/${user}";
          };
          modules = [
            ./home.nix
          ];
        };
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit user;
          homeDirectory = "/Users/${user}";
        };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = {
              inherit user;
              homeDirectory = "/Users/${user}";
            };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };

      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = linuxTargetName system;
          value = mkLinuxHome system;
        })
        linuxSystems);
    };
}
