# Lambda layer compile script

VERSION="0-0-1"
ARCHIVE="chat-lib-${VERSION}.zip"
DIR="python"

rm -r $DIR

mkdir $DIR
cp -r chatlib $DIR
zip -r $ARCHIVE $DIR

rm -r $DIR
