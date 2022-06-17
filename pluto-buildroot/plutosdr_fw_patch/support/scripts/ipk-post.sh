#!/bin/bash
#
# Licence: GPL
# Created: 2013-01-15 15:26:45+01:00
# Main authors:
#     - Jérôme Pouiller <[hidden email]>
#     - Vinay Malkani <[hidden email]>
#
# Second part of package building.
#
# Kill previously launched daemon. Using daemon result, create ipk files of
# package.



FIND="$(command -v find)"
FIND="${FIND:-$(command -v gfind)}"
TAR="${TAR:-$(command -v tar)}"

# try to use fixed source epoch
if [ -n "$PKG_SOURCE_DATE_EPOCH" ]; then
	TIMESTAMP=$(date --date="@$PKG_SOURCE_DATE_EPOCH")
elif [ -n "$SOURCE_DATE_EPOCH" ]; then
	TIMESTAMP=$(date --date="@$SOURCE_DATE_EPOCH")
else
	TIMESTAMP=$(date)
fi

TARGET_DIR=$1
BUILD_DIR=$2
PACKAGES_DIR=$3
PKG_RAWNAME=$3
PKG_VERSION=${4}
#PKG_VERSION= $(grep "Version:" <  $BUILD_DIR/$PKG_RAWNAME-${4}/ipk_build_/DEBIAN/control | cut -d' ' -f2)
ARCH=$5
#PKG_DIR=$PACKAGES_DIR/$PKG_RAWNAME-$PKG_VERSION
PKG_DIR=$PACKAGES_DIR/$PKG_RAWNAME
PKG_BUILD_DIR=$BUILD_DIR/$PKG_RAWNAME-$PKG_VERSION
IPK_DIR=$PKG_BUILD_DIR/ipk_build
PKG=$PKG_RAWNAME
echo "======== [IPK] create package for $PKG-$PKG_VERSION ========"
echo "paramètres 1:$1 2:$2 packages_dir:$PACKAGES_DIR 3:$3 4:$4 5:$5"
echo "PKG_BUILD_DIR=$PKG_BUILD_DIR"
echo "IPK_DIR=$IPK_DIR"
echo "PKG_RAWNAME=$PKG_RAWNAME"


# Blacklist packages
if [ $PKG_RAWNAME != "skeleton-init-common" ] \
&& [ $PKG_RAWNAME != "skeleton-init-sysv" ] \
&& [ $PKG_RAWNAME != "gcc" ] \
&& [ $PKG_RAWNAME != "ifupdown-scripts" ] \
&& [ $PKG_RAWNAME != "initscripts" ] \
&& [ $PKG_RAWNAME != "glibc" ]; then

echo "Version : $PKG_VERSION"
if [[ "$PKG_VERSION" = "master" ]] || [[ ! "$PKG_VERSION" ]]; then
PKG_VERSION="0.999-master"
fi
kill $(cat $PKG_BUILD_DIR/.ipk_inotify_pid)

# Create DEBIAN/control files
#for P in $PKG $PKG-i18n $PKG-doc $PKG-dbg $PKG-dev; do
for P in $PKG; do
    rm -fr $IPK_DIR/$P
    #DEBIAN_DIR=$IPK_DIR/$P/DEBIAN
    DEBIAN_DIR=$PACKAGES_DIR/$P
    mkdir -p $IPK_DIR/$P/DEBIAN
    
    if [ ! -f $PACKAGES_DIR/$P/$P.mk ]; then
    echo "**** BR2_EXTERNAL package !"
    DEBIAN_DIR="$BR2_EXTERNAL/package/$P"
	fi

 #   source $TARGET_DIR/../../package/$P/$P.mk
    (
        PKG_VERSION=`echo $PKG_VERSION | sed 's/^[a-Z]//g'`
 echo "Package: $P"
 echo "Version: $PKG_VERSION"
 echo "Architecture: $ARCH"
 
# echo "Maintainer: $(cat $TARGET_DIR/../../package/$P/$P.mk | grep '_SITE' | awk '{printf $3}'  )"
if [ ! $(cat $DEBIAN_DIR/$P.mk | grep '_SITE' | awk '{printf $3}') ]; then
echo "Maintainer: Buildroot Automated  <[no email]>"
else
echo "Maintainer: $(cat $DEBIAN_DIR/$P.mk | grep '_SITE' | awk '{printf $3}'  )"
fi

 [ $P == $PKG-i18n ] && echo "Depends: $PKG"
 [ $P == $PKG-dev  ] && echo "Depends: $PKG"
 [ $P == $PKG-dbg  ] && echo "Depends: $PKG"
 [ $P == $PKG-doc  ] && echo "Recommends: $PKG"
 echo "Description: $P"
 sed '1,/help/d; /^$/Q' $DEBIAN_DIR/Config.in
        echo
    ) >   $IPK_DIR/$P/DEBIAN/control
#echo  $TARGET_DIR/../../package/$P/$P.mk

done



# Files list
# echo $(cat  $PKG_BUILD_DIR/.ipk_list_installed_files)

# Place application files in package trees
#Get one by one

#cut -f 2 $PKG_BUILD_DIR/.files-list.txt | sort | uniq | while read FILE_FULL; do
cut -d' ' -f 2 $PKG_BUILD_DIR/.ipk_list_installed_files | sort | uniq | while read FILE_FULL; do
  FILE=${FILE_FULL##$TARGET_DIR/}
  DIR=${FILE%/*}
  echo "File: $FILE ($FILE_FULL)"
#  [[ -e $FILE_FULL ]] || continue
#  [[ -d $FILE_FULL ]] && continue
  case /$FILE in
#    ./usr/include/*|*.a|*.la|./usr/lib/pkgconfig/*|./usr/share/aclocal/*)

    /usr/lib/pkgconfig/*)
      mkdir -p $IPK_DIR/$PKG-conf/$DIR
      cp -pd $FILE_FULL $IPK_DIR/$PKG-conf/$FILE
      echo "[IPK] copy $FILE_FULL to $IPK_DIR/$PKG-conf/$FILE"
      echo "-----------------------------"
      ;;
    /bin/*|/sbin/*|/lib/*.so*|/usr/bin/*|/usr/sbin/*|/usr/lib/*.so*)
      mkdir -p $IPK_DIR/$PKG/$DIR
     arm-linux-gnueabihf-strip $FILE_FULL -o $IPK_DIR/$PKG/$FILE
    #  if [[ -L $FILE_FULL ]]; then
          echo "[IPK] copy $FILE_FULL to $IPK_DIR/$PKG/$FILE"
          echo "-----------------------------"
       #   cp -pd $FILE_FULL $IPK_DIR/$PKG/$FILE

     # else
      #    mkdir -p $IPK_DIR/$PKG-dbg/$DIR
     #     strip $FILE_FULL -o $IPK_DIR/$PKG-dbg/$FILE.dbg --only-keep-debug
     #     if [[ /$FILE == *thread*.so* ]]; then
     #        strip $FILE_FULL -o $IPK_DIR/$PKG/$FILE --strip-debug
     #     else
     #       strip $FILE_FULL -o $IPK_DIR/$PKG/$FILE
     #     fi
     #     cp -pd $FILE_FULL $IPK_DIR/$PKG/$FILE
      #fi
      ;;
#    /usr/*doc/*|/usr/*man/*|/usr/*info/*|/usr/*gtk-doc/*)
#      mkdir -p $IPK_DIR/$PKG-doc/$DIR
#      cp -pd $FILE_FULL $IPK_DIR/$PKG-doc/$FILE
#      ;;
    /etc/*|/etc/init.d/*)
      mkdir -p $IPK_DIR/$PKG/$DIR
      cp -rpd $FILE_FULL $IPK_DIR/$PKG/$FILE
      echo "[IPK] copy $FILE_FULL to $IPK_DIR/$PKG/$FILE"
      echo "-----------------------------"
      ;;
    /usr/share/locale/*)
      mkdir -p $IPK_DIR/$PKG-i18n/$DIR
      cp -pd $FILE_FULL $IPK_DIR/$PKG-i18n/$FILE
      ;;
    *)
      echo "[IPK] will do nothing for this file"
      echo "-----------------------------------"
      #mkdir -p $IPK_DIR/$PKG/$DIR
      #cp -pd $FILE_FULL $IPK_DIR/$PKG/$FILE
      ;;
  esac
done
echo "****   Create .deb package ..."


# Correct package name  (replace _ by -)
pkg=$(echo "$PKG_RAWNAME" | sed 's/_/-/g' )
newdir=${IPK_DIR}/${pkg}
olddir=${IPK_DIR}/${PKG_RAWNAME}
sed -i '/Package/ s/_/-/g' ${olddir}/DEBIAN/control
if [ "$olddir" != "$newdir" ]; then

	mv $olddir $newdir 
	echo "**** Correct package name, rename : $olddir"
	echo "****                           to : $newdir "
fi
echo "============"
cat ${newdir}/DEBIAN/control
echo "============"

# Create .deb first (same than .ipk) file
IPK_REPOSITORY=$BUILD_DIR/../../images/ipk_repository
mkdir -p $IPK_REPOSITORY
for P in $pkg; do
#for P in $PKG $PKG-i18n $PKG-doc $PKG-dbg $PKG-dev; do

   if [[ $(ls $IPK_DIR/$P | wc -l) -gt 1 ]]; then
#       echo "Package : $P"
       
       
       
       FIND="$(command -v find)"
FIND="${FIND:-$(command -v gfind)}"
TAR="${TAR:-$(command -v tar)}"

# try to use fixed source epoch
if [ -n "$PKG_SOURCE_DATE_EPOCH" ]; then
	TIMESTAMP=$(date --date="@$PKG_SOURCE_DATE_EPOCH")
elif [ -n "$SOURCE_DATE_EPOCH" ]; then
	TIMESTAMP=$(date --date="@$SOURCE_DATE_EPOCH")
else
	TIMESTAMP=$(date '+%d-%m-%Y %X')
fi
pkg=$(echo "$PKG_RAWNAME" | sed 's/_/-/g' )
pkg_file=$IPK_REPOSITORY/${pkg}_${PKG_VERSION}_${ARCH}.ipk

#( cd $IPK_DIR/$P && tar --format=gnu --sort=name -cf -  --mtime="$TIMESTAMP" ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -n - > "$pkg_file" )

#rm $IPK_DIR/debian-binary "$IPK_DIR"/data.tar.gz "$IPK_DIR"/control.tar.gz
#rmdir "$IPK_DIR"

#echo "Packaged contents of $pkg_dir into $pkg_file"
       
       
       
       NEWNAME=$(echo "$P" | sed 's/_/-/g' )
       #mv $IPK_DIR/$P $IPK_DIR/$NEWNAME
	   dpkg-deb -b $newdir $IPK_REPOSITORY
      # dpkg-deb -b $IPK_DIR/$NEWNAME $BUILD_DIR/../images/ipk_repository
#       echo "*** Rename package to : ${PKG}_${PKG_VERSION}_${ARCH}.ipk"
      sleep 2
      PKG_VERSION=`echo $PKG_VERSION | sed 's/^[a-Z]//g'`
      mv ${IPK_REPOSITORY}/${pkg}_${PKG_VERSION}_${ARCH}.deb ${IPK_REPOSITORY}/${pkg}_${PKG_VERSION}_${ARCH}.ipk
      echo "Rename package to : ${pkg}_${PKG_VERSION}_${ARCH}.ipk"   
      ls -l $IPK_REPOSITORY/${pkg}_${PKG_VERSION}_${ARCH}.*
   fi
done 

fi
