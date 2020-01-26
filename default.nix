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
          gzip    # Needed to nix-instantiate expressions with tarballs.
          nix
        ];
    };

  basePkgs = pkgs.path;

  rootHome = "root";  # Do not include the leading '/'.

  systemPath = "run/current-system/sw";  # Do not include the leading '/'.

  passwdFile = ''
    root:x:0:0::/${rootHome}:${systemPath}/bin/sh
    ${builtins.concatStringsSep
        "\n"
        (builtins.genList
          (i: "nixbld${toString (i+1)}:x:${toString (i+30001)}:30000::/var/empty:/${systemPath}/bin/nologin")
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
    "HOME=/${rootHome}"
    "MANPATH=/${systemPath}/share/man"
    "NIX_PAGER=cat"
    "NIX_SSL_CERT_FILE=${systemPath}/etc/ssl/certs/ca-bundle.crt"
    "PATH=/${rootHome}/.nix-profile/bin:/${systemPath}/bin:/usr/bin:/bin"
    "USER=root"
  ];

  baseConfig =
   {
     Cmd = ["bash" "-il"];
     Env = baseEnvMapping;
   };

  image =
    pkgs.dockerTools.buildImageWithNixDb {
      name = imageName;
      tag = imageTag;
      contents = [];
      extraCommands = ''

        # Create system-wide directories.
        mkdir -p bin \
                 etc/nix \
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
        ln -s ${baseEnv} ${systemPath}
        ln -s /${systemPath}/bin/sh bin/sh
        ln -s /${systemPath}/bin/env usr/bin/env

        # Configure the root user.
        mkdir -p nix/var/nix/profiles/per-user/root \
                 ${rootHome}/.nix-defexpr
        ln -s /nix/var/nix/profiles/per-user/root/profile \
              ${rootHome}/.nix-profile
        ln -s ${basePkgs} \
              ${rootHome}/.nix-defexpr/nixpkgs
      '';
      config = baseConfig;
    };
  load =
    pkgs.writeScript "load-${imageName}" ''
      #! /bin/sh
      set -eu
      if [ -z "$(docker image ls -q ${imageName}:${imageTag})" ]; then
        echo "Loading ${imageName}:${imageTag}..."
        docker load < ${image}
      fi
    '';
  run =
    pkgs.writeScript "run-${imageName}-image" ''
      #! /bin/sh
      set -ex
      ${load}
      if [ -t 0 ]; then
        USE_TTY='-t'
      else
        USE_TTY=
      fi
      docker run --rm -i $USE_TTY ${imageName}:${imageTag} "$@"
    '';
in
  { inherit image load run; }
