#!/bin/sh
#
# Licence: GPL
# Created: 2013-01-15 15:25:52+01:00
# Main authors:
#     - Jérôme Pouiller <[hidden email]>
#     - Vinay Malkani <[hidden email]>
#
# First part of package building.
#
# It launches a daemon to spy write acces to target. Results are written to
# .ipk_list_installed_files in build subdirectory of package.
#

TARGET_DIR=$1
BUILD_DIR=$2
PACKAGES_DIR=$3
#PACKAGES_DIR=/home/eric/pluto032/ipk
PKG_RAWNAME=$3
PKG_VERSION=$4
PKG=$PKG_RAWNAME
#PKG=$(echo "$PKG_RAWNAME" | sed 's/_/-/g' )
PKG_DIR=$PACKAGES_DIR/$PKG_RAWNAME
PKG_BUILD_DIR=$BUILD_DIR/$PKG-$PKG_VERSION
IPK_DIR=$PKG_BUILD_DIR/ipk_build

#PKG=${PKG_RAWNAME//_/-}
#PKG=sed 's/_/\-/g' <<<"$PKG_RAWNAME"
mkdir -p $IPK_DIR

echo "======== [IPK] start for $PKG-$PKG_VERSION package ========="
echo PKG_BUILD_DIR=$PKG_BUILD_DIR 
echo TARGET_DIR=$TARGET_DIR
rm $PKG_BUILD_DIR/.ipk_list_installed_files 2> /dev/null
inotifywait -mr $TARGET_DIR  -q -e create -e modify -e moved_to --format '%e %w%f' -o $PKG_BUILD_DIR/.ipk_list_installed_files &
echo $! > $PKG_BUILD_DIR/.ipk_inotify_pid
# FIXME Be sure inotifywait is started
#sleep 1


 
