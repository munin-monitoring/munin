# A gzipped tarball able to build a source rpm
#
# This should be called from dists/tarball
#
# For an rpm tarbuild, all we need is a tar.gz with the whole code
# base tree with at custom name on it

startdir=`pwd`
case $0 in
	/*)	rundir=`dirname $0` ;;
	*)	rundir="$startdir"/`dirname $0` ;;
esac
cd "$rundir"
tardir=/var/tmp/lrrd-tar-$$

VERSION=`cat ../../RELEASE`
# Use somewhere with plenty of space
mkdir -p $tardir/lrrd-$VERSION
cp -pR ../../* $tardir/lrrd-$VERSION
cd $tardir
find . -depth -name CVS -type d -exec rm -r {} \;
find . -name '*.tar.gz' -type f -exec rm {} \;
tar czf lrrd-$VERSION.tar.gz lrrd-$VERSION
cd "$rundir"
mv $tardir/lrrd-$VERSION.tar.gz .
rm -rf $tardir

echo "Finished building rpmbuildable tar.gz"
ls -ld "$rundir/lrrd-$VERSION.tar.gz"

exit 0
