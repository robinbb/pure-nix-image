{ pkgs ? import <nixpkgs> {}
}:
let
  imageName = "robinbb-pure-nix";

  imageTag = "draft";

  baseEnv =
    pkgs.buildEnv {
      name = "${imageName}-env";
      paths =
        with pkgs; [
          bashInteractive
          cacert
          coreutils
          gnutar  # Needed to nix-instantiate expressions with tarballs.
          gnugrep # TODO: Needed for testing?
          gzip    # Needed to nix-instantiate expressions with tarballs.
          less    # TODO: not needed? This is the pager.
          nix
          shadow
        ];
    };

  basePkgs = pkgs.path;

  passwdFile = ''
    root:x:0:0::/root:${baseEnv}/bin/sh
    ${builtins.concatStringsSep
        "\n"
        (builtins.genList
          (i: "nixbld${toString (i+1)}:x:${toString (i+30001)}:30000::/var/empty:/run/current-system/sw/bin/nologin")
          32
        )
     }
  '';

  shadowFile = ''
    root:!x:::::::
  '';

  groupFile = ''
    root:x:0:
    nixbld:x:30000:${builtins.concatStringsSep "," (builtins.genList (i: "nixbld${toString (i+1)}") 32)}
  '';

  gshadowFile = ''
    root:x::
  '';

  pamdOtherFile = ''
    account sufficient pam_unix.so
    auth sufficient pam_rootok.so
    password requisite pam_unix.so nullok sha512
    session required pam_unix.so
  '';

  nixConfFile = ''
    build-users-group = nixbld
    sandbox = false
  '';

  baseEnvMapping = [
    "PATH=/run/current-system/sw/bin:/usr/bin:/bin"
    "MANPATH=/run/current-system/sw/share/man"
    "NIX_PAGER=less"
    "USER=root"
    "NIX_SSL_CERT_FILE=${baseEnv}/etc/ssl/certs/ca-bundle.crt"
  ];

  baseConfig =
   {
     Cmd = ["bash" "-il"];
     Env = baseEnvMapping;
   };

  image =
    pkgs.dockerTools.buildImageWithNixDb {
      name = imageName;
      contents = [ basePkgs baseEnv ];
      extraCommands = ''
        set -eu

        # Investigate what is already present in the build environment.
        whoami
        pwd
        ls -laR

        # Create system-wide directories.
        mkdir etc/nix
        mkdir -p bin \
                 etc/pam.d \
                 usr/bin \
                 var/empty \
                 run/current-system \
                 nix/var/nix/gcroots
        mkdir -m 1777 -p tmp

        touch etc/login.defs
        echo '${passwdFile}' > etc/passwd
        echo '${shadowFile}' > etc/shadow
        echo '${groupFile}' > etc/group
        echo '${gshadowFile}' > etc/gshadow
        echo '${pamdOtherFile}' > etc/pam.d/other

        echo '${nixConfFile}' > etc/nix/nix.conf
        ln -s ${baseEnv} nix/var/nix/gcroots/booted-system
        ln -s ${baseEnv} run/current-system/sw
        ln -s ${baseEnv}/bin/sh bin/sh
        ln -s ${baseEnv}/bin/env usr/bin/env

        # Configure the root user.
        mkdir -p nix/var/nix/profiles/per-user/root \
                 root/.nix-defexpr
        ln -s /nix/var/nix/profiles/per-user/root/profile root/.nix-profile
        ln -s ${basePkgs} root/.nix-defexpr/nixpkgs
      '';
      config = baseConfig;
    };
in
  image
