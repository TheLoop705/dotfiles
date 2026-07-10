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
      # Per-host usernames. Each machine gets its own value here instead of a
      # single shared variable, so changing one machine's account never
      # touches another machine's target. Add a new line here (and to
      # linuxSystems below for a new architecture) instead of editing the
      # structure of this file.
      macUser = "vpnuser";
      linuxUser = "sultan";
      # WSL is a separate target so its local account can differ from the
      # regular Ubuntu machine without rewriting that machine's config.
      wslUser = "ubuntu";

      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];

      linuxTargetName = system:
        if system == "x86_64-linux" then "${linuxUser}@linux-x86_64"
        else if system == "aarch64-linux" then "${linuxUser}@linux-aarch64"
        else throw "Unsupported Linux system: ${system}";

      wslTargetName = system:
        if system == "x86_64-linux" then "${wslUser}@wsl-x86_64"
        else if system == "aarch64-linux" then "${wslUser}@wsl-aarch64"
        else throw "Unsupported WSL system: ${system}";

      mkLinuxHome = user: system:
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
          user = macUser;
          homeDirectory = "/Users/${macUser}";
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
              user = macUser;
              homeDirectory = "/Users/${macUser}";
            };
            home-manager.users.${macUser} = import ./home.nix;
          }
        ];
      };

      homeConfigurations = builtins.listToAttrs (
        (map
          (system: {
            name = linuxTargetName system;
            value = mkLinuxHome linuxUser system;
          })
          linuxSystems)
        ++ (map
          (system: {
            name = wslTargetName system;
            value = mkLinuxHome wslUser system;
          })
          linuxSystems)
      );
    };
}
