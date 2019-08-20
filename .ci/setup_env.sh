#!/usr/bin/env bash
# set -e

#---------
# Download
#---------

DEPS_HASH=$(cat .requirements .ci/setup_env.sh | md5sum | awk '{ print $1 }')
BUILD_TOOLS_DOWNLOAD=$DOWNLOAD_ROOT/openresty-build-tools

git clone --single-branch --branch ${OPENRESTY_BUILD_TOOLS_VERSION:-master} https://github.com/Kong/openresty-build-tools.git $DOWNLOAD_ROOT/openresty-build-tools
export PATH=$BUILD_TOOLS_DOWNLOAD:$PATH

#--------
# Install
#--------
INSTALL_ROOT=$INSTALL_CACHE/$DEPS_HASH

kong-ngx-build \
    --work $DOWNLOAD_ROOT \
    --prefix $INSTALL_ROOT \
    --openresty $RESTY_VERSION \
    --openresty-patches $OPENRESTY_PATCHES_BRANCH \
    --kong-nginx-module $KONG_NGINX_MODULE_BRANCH \
    --luarocks $RESTY_LUAROCKS_VERSION \
    --openssl $RESTY_OPENSSL_VERSION \
    -j $JOBS

OPENSSL_INSTALL=$INSTALL_ROOT/openssl
OPENRESTY_INSTALL=$INSTALL_ROOT/openresty
LUAROCKS_INSTALL=$INSTALL_ROOT/luarocks

export OPENSSL_DIR=$OPENSSL_INSTALL # for LuaSec install

export PATH=$OPENSSL_INSTALL/bin:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin:$PATH
export LD_LIBRARY_PATH=$OPENSSL_INSTALL/lib:$LD_LIBRARY_PATH # for openssl's CLI invoked in the test suite

eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$KONG_TEST_DATABASE" == "cassandra" ]]; then
  echo "Setting up Cassandra"
  docker run -d --name=cassandra --rm -p 7199:7199 -p 7000:7000 -p 9160:9160 -p 9042:9042 cassandra:$CASSANDRA
  grep -q 'Created default superuser role' <(docker logs -f cassandra)
fi

# -------------------
# Install Test::Nginx
# -------------------
if [[ "$TEST_SUITE" == "pdk" ]]; then
  CPAN_DOWNLOAD=$DOWNLOAD_ROOT/cpanm
  mkdir -p $CPAN_DOWNLOAD
  wget -O $CPAN_DOWNLOAD/cpanm https://cpanmin.us
  chmod +x $CPAN_DOWNLOAD/cpanm
  export PATH=$CPAN_DOWNLOAD:$PATH

  echo "Installing CPAN dependencies..."
  cpanm --notest Test::Nginx &> build.log || (cat build.log && exit 1)
  cpanm --notest --local-lib=$TRAVIS_BUILD_DIR/perl5 local::lib && eval $(perl -I $TRAVIS_BUILD_DIR/perl5/lib/perl5/ -Mlocal::lib)
fi

# ----------------
# Run gRPC server |
# ----------------
if [[ "$TEST_SUITE" =~ integration|dbless|plugins ]]; then
  docker run -d --name grpcbin -p 15002:9000 -p 15003:9001 moul/grpcbin
fi

ln -s $LUAROCKS_INSTALL/bin/luarocks ~/bin/luarocks
ln -s $OPENRESTY_INSTALL/bin/resty ~/bin/resty
ln -s $OPENSSL_INSTALL/bin/openssl ~/bin/openssl
ln -s $OPENRESTY_INSTALL/nginx/sbin/nginx ~/bin/nginx

luarocks install luacheck
ln -s $LUAROCKS_INSTALL/bin/luacheck ~/bin/luacheck

nginx -V
resty -V
luarocks --version
openssl version
