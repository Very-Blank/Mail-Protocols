{
  description = "Dev flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixnvim = {
      url = "github:Very-Blank/NixNvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos = {
      url = "github:Very-Blank/Nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    system = "x86_64-linux";
  in {
    devShells."${system}".default = let
      pkgs = import nixpkgs {inherit system;};

      tmux = inputs.nixos.packages.${system}.tmux.override {
        name = "Mail-Protocols";
        shell = "${pkgs.lib.getExe pkgs.zsh}";
        windows = [
          {
            name = "NVIM";
            cmd = ["nvim"];
            onExit = "respawn";
          }
          {
            name = "COMMANDS";
          }
        ];
      };
    in
      pkgs.mkShell
      {
        packages = [
          pkgs.zig_0_17

          (pkgs.writeShellApplication {
            name = "do-test";
            runtimeInputs = [pkgs.netcat pkgs.coreutils];
            text = ''
              commands=(
              'HELO localhost\r\n'
              'MAIL FROM:<sender@example.com>\r\n'
              'RCPT TO:<recipient@example.com>\r\n'
              'DATA\r\n'
              'Subject: Test message\r\nFrom: sender@example.com\r\nTo: recipient@example.com\r\n\r\nHello, this is a test.\r\n.\r\n'
              'QUIT\r\n'
              )
                      
              (for command in "''${commands[@]}" ; do
                  sleep 1
                  printf '%b' "$command"
              done) | nc 127.0.0.1 6000
            '';
          })

          (
            inputs.nixnvim.mkPackage {
              system = system;
              extraModule = {...}: {
                config = {
                  vim = {
                    languages = {
                      zig = {
                        enable = true;
                        lsp.enable = true;
                        treesitter.enable = true;
                      };
                    };

                    lsp.servers.zls = pkgs.lib.mkForce {
                      filetypes = ["zig"];
                      cmd = pkgs.lib.mkForce [
                        "${pkgs.lib.getExe pkgs.zigscient}"
                      ];
                    };
                  };
                };
              };
            }
          )
        ];

        shellHook = ''
          unset shellHook
          ${tmux.shellGuard}
          exit
        '';
      };
  };
}
