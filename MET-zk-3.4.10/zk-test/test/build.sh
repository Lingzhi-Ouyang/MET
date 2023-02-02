SCRIPT_DIR=$(cd $(dirname $0);pwd)
WORKING_DIR=$(cd $SCRIPT_DIR/../..;pwd)

echo $WORKING_DIR

# build HitMC
cd $WORKING_DIR/zk-test && mvn clean install