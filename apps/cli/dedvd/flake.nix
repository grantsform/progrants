{
  description = "dedvd — optical disc backup TUI (Go + Charmbracelet)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          dedvd = pkgs.buildGoModule {
            pname = "dedvd";
            version = "0.1.0";
            src = ./.;
            vendorHash = null;       # deps vendored in-tree

            # Runtime tools invoked via os/exec
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postInstall = ''
              wrapProgram $out/bin/dedvd \
                --prefix PATH : ${pkgs.lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.util-linux     # blkid findmnt
                  pkgs.rsync
                  pkgs.udev           # udevadm
                  pkgs.udisks2        # udisksctl
                  pkgs.gnugrep
                  pkgs.findutils
                  pkgs.unzip
                  pkgs.handbrake
                  pkgs.openssh
                  pkgs.sshpass
                  pkgs.ddrescue
                  pkgs.dvdplusrwtools  # dvd+rw-mediainfo
                  pkgs.cdrkit          # readom (raw SCSI reader)
                  pkgs.cdparanoia      # cdparanoia (audio CD reader)
                  pkgs.testdisk        # photorec (data recovery tool)
                ]}
            '';

            meta = {
              description = "Optical disc backup TUI — watch, transcode, upload";
              mainProgram = "dedvd";
            };
          };
        in
        {
          dedvd = dedvd;
          default = dedvd;
        }
      );

      apps = forAllSystems (system: {
        dedvd = {
          type = "app";
          program = "${self.packages.${system}.dedvd}/bin/dedvd";
        };
        default = {
          type = "app";
          program = "${self.packages.${system}.dedvd}/bin/dedvd";
        };
      });
    };
}
