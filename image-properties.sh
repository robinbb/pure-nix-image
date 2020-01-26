# image-properties.sh
#
# This is test code for the generated image. It is a POSIX shell script in
# which, for tests to pass, each command must succeed.

set -ex

echo "Beginning tests from image-properties.sh"

# The 'sh' command must be on the PATH.
command -v sh

# The HOME environment variable must be set.
[ "$HOME" ]

# The USER environment variable must be set.
[ "$USER" ]

# The 'grep' command is not (yet) available.
if command -v grep; then
  exit 1
fi

# The '/etc/passwd' file exists.
[ -e /etc/passwd ]

# A '/etc/group' file exists.
[ -e /etc/group ]

# A '/etc/group' file exists.
[ -e /etc/group ]

# The 'groups' command is available and works.
command -v groups
groups root

# The 'NIX_SSL_CERT_FILE' environment variable is set.
[ "$NIX_SSL_CERT_FILE" ]

# The file or link '/root/.nix-profile' exists.
ls -ld /root/.nix-profile

# The user can install new packages with 'nix-env'.
command -v nix-env
nix-env -iA nixpkgs.gnugrep

# The 'grep' command is available.
command -v grep

# The 'env' command is available.
command -v env

# The 'bash' command is available.
command -v bash

# The 'PATH' is set.
bash -c 'set -o pipefail; env | grep PATH'

# The 'nixbld' group exists.
grep nixbld /etc/group

echo "Ending tests from image-properties.sh"
