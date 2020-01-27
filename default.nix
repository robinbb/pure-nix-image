{ pkgs ? import <nixpkgs> {}
}:
let
  imageName = "pure-nix";

  rootHome = "root";  # Do not include the leading '/'.

  systemPath = "run/current-system/sw";  # Do not include the leading '/'.

  passwdFile = ''
    root:x:0:0::/${rootHome}:/${systemPath}/bin/sh
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
    "NIX_SSL_CERT_FILE=/${systemPath}/etc/ssl/certs/ca-bundle.crt"
    "PATH=/${rootHome}/.nix-profile/bin:/${systemPath}/bin:/usr/bin:/bin"
    "USER=root"
  ];

  baseConfig =
   {
     Cmd = ["bash" "-il"];
     Env = baseEnvMapping;
   };

  fhsStructure =
    pkgs.runCommand "fhs-structure" {} ''
      mkdir $out
      cd $out

      # Create system-wide directories.
      mkdir -p etc/nix \
               etc/pam.d \
               usr/bin \
               var/empty
      mkdir -m 1777 -p tmp

      touch etc/login.defs
      echo '${passwdFile}' > etc/passwd
      echo '${shadowFile}' > etc/shadow
      echo '${groupFile}' > etc/group
      echo '${gshadowFile}' > etc/gshadow
      echo '${pamdOtherFile}' > etc/pam.d/other

      echo '${nixConfFile}' > etc/nix/nix.conf
      ln -s /${systemPath}/bin/env usr/bin/env
    '';

  baseEnv =
    pkgs.buildEnv {
      name = "${imageName}-env";
      paths =
        [ fhsStructure ] ++
        (with pkgs; [
          bashInteractive
          cacert
          coreutils
          gnutar  # Needed to nix-instantiate expressions with tarballs.
          gzip    # Needed to nix-instantiate expressions with tarballs.
          man
          nix
        ]);
    };

  buildImageWithNixDb = args@{ contents ? null, extraCommands ? "", ... }:
    let contentsList = if builtins.isList contents then contents else [ contents ];
    in pkgs.dockerTools.buildImage (args // {
      extraCommands = ''
        echo "Generating the nix database..."
        echo "Warning: only the database of the deepest Nix layer is loaded."
        echo "         If you want to use nix commands in the container, it would"
        echo "         be better to only have one layer that contains a nix store."

        export NIX_REMOTE=local?root=$PWD
        # A user is required by nix
        # https://github.com/NixOS/nix/blob/9348f9291e5d9e4ba3c4347ea1b235640f54fd79/src/libutil/util.cc#L478
        export USER=nobody
        ${pkgs.nix}/bin/nix-store --load-db < ${pkgs.closureInfo {rootPaths = contentsList;}}/registration

        mkdir -p nix/var/nix/gcroots/docker/
        for i in ${pkgs.lib.concatStringsSep " " contentsList}; do
          ln -s $i nix/var/nix/gcroots/docker/$(basename $i)
        done;
      '' + extraCommands;
    });

  image =
    buildImageWithNixDb {
      name = imageName;
      keepContentsDirlinks = true;
      contents = [ baseEnv ];
      extraCommands = ''
        mkdir -p "$(dirname "${systemPath}")"
        ln -s ${baseEnv} ${systemPath}

        # Configure the root user.
        mkdir -p ${rootHome}/.nix-defexpr
        ln -s ${pkgs.path} ${rootHome}/.nix-defexpr/nixpkgs
        mkdir -p nix/var/nix/profiles/per-user/root
        ln -s /nix/var/nix/profiles/per-user/root/profile \
              ${rootHome}/.nix-profile
      '';
      config = baseConfig;
    };

  # A program which yields the image tag based on the hash in the name.
  imageTag =
    pkgs.writeScript "image-tag" ''
      #!/bin/sh
      set -eu
      imgName="$(basename "${image}")"
      imgHash="$(echo "$imgName" | cut -d - -f 1)"
      echo "$imgHash"
    '';

  load =
    pkgs.writeScript "load-${imageName}" ''
      #! /bin/sh
      set -eu
      tag="$(${imageTag})"
      if [ -z "$(docker image ls -q ${imageName}:$tag)" ]; then
        echo "Loading ${imageName}:$tag..."
        docker load < ${image}
      fi
    '';

  run =
    pkgs.writeScript "run-${imageName}-image" ''
      #! /bin/sh
      set -eu
      tag="$(${imageTag})"
      ${load}
      if [ -t 0 ]; then
        USE_TTY='-t'
      else
        USE_TTY=
      fi
      docker run --rm -i $USE_TTY ${imageName}:$tag "$@"
    '';
in
  { inherit image load run; }
