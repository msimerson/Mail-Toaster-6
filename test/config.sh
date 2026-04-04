cat << 'EO_CONF' > mail-toaster.conf
export TOASTER_ORG_NAME="test-runner.example.io"
export TOASTER_HOSTNAME="test-runner.example.io"
export TOASTER_MAIL_DOMAIN="gha.example.io"
export TOASTER_ADMIN_EMAIL="postmaster@gha.example.io"
export TOASTER_SRC_URL="https://raw.githubusercontent.com/msimerson/Mail-Toaster-6/master"
export JAIL_NET6="fd7a:e5cd:1fc1:403d:dead:beef:cafe"
EO_CONF
