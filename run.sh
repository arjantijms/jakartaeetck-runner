#!/bin/bash

############ 
# Payara Jakarta EE TCK Runner.
# Any environment customization is marked in commend with prefix (ENV) below.
#
# Usage:
# 1. copy or link tck binary, glassfish binary and payara binary to bundles/ (see BUNDLES below)
# 2. run bundles/run_server.sh
#      This starts download server at port 8000
# 3. run ./run.sh <test_bundle>
# 4. swear appropriately to number of failing test cases
# 5. collect failure logs
# 6. adjust test properties in ./ts.override.properties

# BUNDLES 
# 
# URLs to respective binaries that get downloaded thoughout the process. By default it assumes server
# running off bundles directory that serves on port 80. Any of these variables are overridable
# (ENV) BASE_URL - parent url, assuming binaries called jakartaeetck.zip, latest-glassfish.zip and payara-prerelease.zip
# (ENV) TCK_URL - full url to TCK
# (ENV) GLASSFISH_URL - full url to glassfish
# (ENV) PAYARA_URL - full url to payara

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
. $SCRIPTPATH/functions.sh

if [ -z "$BASE_URL"]; then
  BASE_URL=http://localhost:8000
fi
if [ -z "$TCK_URL"]; then
  TCK_URL=$BASE_URL/jakartaeetck.zip
fi
if [ -z "$GLASSFISH_URL" ]; then
  GLASSFISH_URL=$BASE_URL/latest-glassfish.zip
fi
if [ -z "$PAYARA_URL" ]; then
  PAYARA_URL=$BASE_URL/payara-prerelease.zip
fi

# Since this is multi-step process, there are some environment variables that help when troubleshooting
# (ENV) SKIP_TCK - skips cleaning CTS home and downloading TCK again

export CTS_HOME=$SCRIPTPATH/cts_home
export WORKSPACE=$CTS_HOME/jakartaeetck

echo "Cleaning and installing TCK"
killall java
if [ -z "$SKIP_TCK" ]; then
    # clean cts directory
    rm -rf $CTS_HOME/*
    # download and unzip TCK
    TCK_TEMP=`tempfile -s .zip`
    curl $TCK_URL -o $TCK_TEMP
    echo -n "Unzipping TCK... "
    unzip -q -d $CTS_HOME $TCK_TEMP
    rm $TCK_TEMP
    cp $WORKSPACE/bin/ts.jte $CTS_HOME/ts.jte.dist
    echo "Done"

    # test for https://github.com/eclipse-ee4j/jakartaee-tck/pull/89/
    if ! grep -q config.vi.javadb $WORKSPACE/docker/run_jakartaeetck.sh; then
      echo "Replacing runner script with patched one"
      cp patch/run_jakartaeetck.sh $WORKSPACE/docker/
    fi;
fi

# link VI impl
rm -rf $WORKSPACE/bin/xml/impl/payara
ln -s $SCRIPTPATH/cts-impl $WORKSPACE/bin/xml/impl/payara

# patch ts.jte
echo "Patching ts.jte"

apply_overrides

echo "Comparison with ts.jte of original distribution:"
diff $WORKSPACE/bin/ts.jte $CTS_HOME/ts.jte.dist

# run mailserver container
# (ENV) SKIP_MAIL - do not attempt to start mailserver container
if [ -z "$SKIP_MAIL"]; then 
    JAMES_CONTAINER=`docker ps -f name='james-mail' -q`
    if [ -z "$JAMES_CONTAINER" ]; then
        echo "Starting email server Docker container"
        docker run --name james-mail --rm -d -p 1025:1025 -p 1143:1143 --entrypoint=/bin/bash jakartaee/cts-mailserver:0.1 -c /root/startup.sh
        sleep 10
        echo "Initializing container"
        docker exec -it james-mail /bin/bash -c /root/create_users.sh
    fi
fi

if [ $1=="jaxr" ]; then
    JWSDP_CONTAINER=`docker ps -f name='jwsdp' -q`
    if [ -z "$JWSDP_CONTAINER"]; then
      echo "Starting JWSDP Docker container"
      docker run --name jwsdp --rm -d -p 8280:8080 --entrypoint=/bin/bash jakartaee/cts-base:0.1 /opt/jwsdp-1.3/bin/catalina.sh run
      export UDDI_REGISTRY_URL="http://localhost:8280/RegistryServer/"
    fi
fi


# run testcase

# Set the env to run against payara
export PROFILE=full
export LANG="en_US.UTF-8"
export GF_BUNDLE_URL=$GLASSFISH_URL
export DATABASE=JavaDB
export GF_VI_BUNDLE_URL=$PAYARA_URL
export GF_VI_TOPLEVEL_DIR=payara5

TEST_SUITE=`echo "$1" | tr '/' '_'`

# (ENV) SKIP_TEST - if just testing the script
if [ -z "$SKIP_TEST" ]; then 
  echo "Starting test!"
  time bash $WORKSPACE/docker/run_jakartaeetck.sh "$@" |& tee $CTS_HOME/$TEST_SUITE.log
fi
# collect results

summary=$CTS_HOME/jakartaeetck-report/${TEST_SUITE}/text/summary.txt
ALL=`wc -l $summary`
NOT_PASS=`cat $summary | grep -v Passed. | wc -l`

echo "Not passed: ${NOT_PASS}/${ALL}"

./slim_report.sh $WORKSPACE/$TEST_SUITE-results.tar.gz

TIMESTAMP=`date -Iminutes | tr -d :`
TARGET=$SCRIPTPATH/results/$TEST_SUITE-$TIMESTAMP
mkdir $TARGET
mv $WORKSPACE/$TEST_SUITE-results.slim.tar.gz $TARGET
cp $WORKSPACE/results/junitreports/*.xml $TARGET
cp $summary $TARGET
echo "Not passed: ${NOT_PASS}/${ALL}" > $TARGET/count.txt