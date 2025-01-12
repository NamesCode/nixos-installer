# SPDX-FileCopyrightText: 2025 Name <lasagna@garfunkle.space>
# SPDX-License-Identifier: MPL-2.0

{
  description = "A NixOS installer so I can setup my servers faster";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nvame.url = "github:namescode/nvame";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;

      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      requiredPackages =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        with pkgs;
        [
          (inputs.nvame.packages.${system}.default)
          gptfdisk
          fzf
        ];
    in
    {
      packages =
        lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
          (
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            {
              default = self.packages.${system}.installerScript;

              installerScript =
                let
                  name = "install-nixos";
                in
                pkgs.symlinkJoin {
                  name = name;
                  paths = requiredPackages system ++ [
                    (pkgs.writeShellScriptBin "install-nixos" ./installer.sh)
                  ];
                  nativeBuildInputs = [ pkgs.makeWrapper ];
                  postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";

                  meta = {
                    description = "A bash script to install NixOS";
                    homepage = "https://git.garfunkles.space/nixos-installer";
                    license = lib.licenses.mpl20;
                    maintainers = with lib.maintainers; [ "Name" ];
                    platforms = lib.platforms.linux;
                  };
                };
            }
          );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs =
              [
                pkgs.bash-language-server
                pkgs.reuse
              ]
              ++ lib.optionals pkgs.stdenv.isLinux (
                requiredPackages system ++ [ (self.packages.${system}.installerScript) ]
              );

            shellHook = ''echo "You're now in the devshell for the installer. If you're at this point it means something went wrong."'';
          };
        }
      );
    };
}
