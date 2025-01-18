# Lambda layer compile script

VERSION="0-0-1"
ARCHIVE="chat-lib-${VERSION}.zip"
BUCKET="lambda-layers-583168578067"
DIR="python"

rm -r $DIR

mkdir $DIR
cp -r chatlib $DIR
zip -r $ARCHIVE $DIR

aws s3 cp $ARCHIVE "s3://${BUCKET}/${ARCHIVE}" --profile personal

rm -r $DIR
rm $ARCHIVE
