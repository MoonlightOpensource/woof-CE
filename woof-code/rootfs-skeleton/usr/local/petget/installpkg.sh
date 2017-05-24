#!/bin/sh
#(c) Copyright Barry Kauler 2009, puppylinux.com
#2009 Lesser GPL licence v2 (http://www.fsf.org/licensing/licenses/lgpl.html).
#called from /usr/local/petget/downloadpkgs.sh and petget.
#passed param is the path and name of the downloaded package.
#/tmp/petget_missing_dbentries-Packages-* has database entries for the set of pkgs being downloaded.
#w456 warning: petget may write to /tmp/petget_missing_dbentries-Packages-alien with missing fields.
#w478, w482 fix for pkg menu categories.
#w482 detect zero-byte pet.specs, fix typo.
#100110 add support for T2 .tar.bz2 binary packages.
#100426 aufs can now write direct to save layer.
#100616 add support for .txz slackware pkgs.
# 20aug10 shinobar: excute pinstall.sh under original LANG environment
#  6sep10 shinobar: warning to install on /mnt/home # 16sep10 remove test code
# 17sep10 shinobar; fix typo was double '|' at reading DESCRIPTION
# 22sep10 shinobar clean up probable old files for precaution
# 22sep10 shinobar: bugfix was not working clean out whiteout files
#110503 change ownership of some files if non-root.
#110523 support for rpm pkgs.
#110705 fix rpm install.
#110817 rcrsn51: fix find syntax, looking for icons. 110821 improve.
#111013 shinobar: aufs direct-write to layer not working, bypass for now.
#111013 revert above. it works for me, except if file already on top -- that is another problem, needs to be addressed.
#111207 improve search for menu icon.
#111229 /usr/local/petget/removepreview.sh when uninstalling a pkg, may have copied a file from sfs-layer to top, check.
#120102 install may have overwritten a symlink-to-dir.
#120107 rerwin: need quotes around some paths in case of space chars. remove '--unlink-first' from tar (was introduced 120102, don't think necessary).
#120126 noryb009: fix typo.
#120219 was not properly internationalized (there was no TEXTDOMAIN).
#120523 may need to run gio-query-modules and/or glib-compile-schemas. (refer also rc.update and 3builddistro)
#120628 fix Categories= assignment in .desktop files. see also 2createpackages in woof.
#120818 Categories management improved. pkg db now has category[;subcategory] (see 0setup), xdg enhanced (see /etc/xdg and /usr/share/desktop-directories), and generic icons for all subcategories (see /usr/local/lib/X11/mini-icons).
#120901 .desktop files, get rid of param on end of Exec, ex: Exec=gimp-2.8 %U
#120907 post-install hacks.
#120926 apply translation for .desktop file if langpack installed.
#121015 01micko: alternative code to delete %-param off end of Exec line in .desktop file.
#121109 fixing Categories field in .desktop may fail, as DB_category field may not match that in .desktop file, so leave out that $tPATTERN match in $PUPHIERARCHY.
#121109 menu category was not reported correctly in post-install window.
#121119 change in layout of /etc/xdg/menus/hierarchy caused regex pattern bug.
#121119 if only one .desktop file, first check if a match in /usr/local/petget/categories.dat.
#121120 bugfix of 121119.
#121123 having a problem with multiarch symlinks in full-installation, getting replaced by a directory.
#121206 default icon needs .xpm extension. note puppy uses older xdg-utilities, Icon field needs image ext.
#121217 still getting reports multiarch symlinks getting overwritten.
#130112 some deb's have a post-install script (ex: some python debs).
#130112 multiarch symlinks now optional. see also 2createpackages, 3builddistro.
#130114 revert 130112 "multiarch symlinks now optional".
#130126 'categories.dat' format changed.
#130219 grep, ignore case.
#130305 rerwin: ensure tmp directory has all permissions after package expansion.
#130314 install arch linux pkgs. run arch linux pkg post-install script.
#131122 support xz compressed pets (see dir2pet, pet2tgz), changed file test

[ "$(cat /var/local/petget/nt_category 2>/dev/null)" != "true" ] && \
 [ -f /tmp/install_quietly ] && set -x
 #; mkdir -p /tmp/PPM_LOGs ; NAME=$(basename "$0"); exec 1>> /tmp/PPM_LOGs/"$NAME".log 2>&1

export TEXTDOMAIN=petget___installpkg.sh
export OUTPUT_CHARSET=UTF-8

APPDIR=$(dirname $0)
[ -f "$APPDIR/i18n_head" ] && source "$APPDIR/i18n_head"
LANG_USER=$LANG
export LANG=C
. /etc/rc.d/PUPSTATE  #this has PUPMODE and SAVE_LAYER.
. /etc/DISTRO_SPECS #has DISTRO_BINARY_COMPAT, DISTRO_COMPAT_VERSION

. /etc/xdg/menus/hierarchy #w478 has PUPHIERARCHY variable.

[ "$PUPMODE" = "2" ] && [ ! -d /audit ] && mkdir -p /audit

DLPKG="$1"
DLPKG_BASE="`basename "$DLPKG"`" #ex: scite-1.77-i686-2as.tgz
DLPKG_PATH="`dirname "$DLPKG"`"  #ex: /root
DL_SAVE_FLAG=$(cat /var/local/petget/nd_category 2>/dev/null)

clean_and_die () {
  rm -f /root/.packages/${DLPKG_NAME}.files
  exit 1
}

# 6sep10 shinobar: installing files under /mnt is danger
install_path_check() {
  FILELIST="/root/.packages/${DLPKG_NAME}.files"
  [ -s "$FILELIST" ] || return 0 #120126 noryb009: typo
  grep -q '^/mnt' "$FILELIST" || return 0
  MNTDIRS=$(cat "$FILELIST" | grep '^/mnt/.*/$' | cut -d'/' -f1-3  | tail -n 1)
  LANG=$LANG_USER
  MSG1=$(gettext "This package will install files under")
  MSG2=$(gettext "It can be dangerous to install files under '/mnt' because it depends on the profile of installation.")
  MSG3=""
  if grep -q '^/mnt/home' "$FILELIST"; then
    if [ $PUPMODE -eq 5 ]; then
      MSG3=$(gettext "You are running Puppy without 'pupsave', and '/mnt/home' does not exist. In this case, you can use the RAM for this space, but strongly recommended to shutdown now to create 'pupsave' BEFORE installing these packages.")
      MSG3="$MSG3\\n$(gettext "NOTE: You can install this package for a tentative use, then do NOT make 'pupsave' with this package installed.")"
    fi
    DIRECTSAVEPATH=""
  fi
  # dialog
  export DIALOG="<window title=\"$T_title\" icon-name=\"gtk-dialog-warning\">
  <vbox>
  <text use-markup=\"true\"><label>\"$MSG1: <b>$MNTDIRS</b>\"</label></text>
  <text><input>echo -en \"$MSG2 $MSG3\"</input></text>
  <text><label>$(gettext "Click 'Cancel' not to install(recommended). Or click 'Install' if you like to proceed.")</label></text>
  <hbox>
  <button cancel></button>
  <button><input file stock=\"gtk-apply\"></input><label>$(gettext 'Install')</label><action type=\"exit\">INSTALL</action></button>
  </hbox>
  </vbox>
  </window>"
  RETPARAMS=`gtkdialog -p DIALOG` || echo "$DIALOG" >&2
  eval "$RETPARAMS"
  LANG=C
  [ "$EXIT" = "INSTALL" ]  && return 0
  rm -f "$FILELIST" 
  exit 1
}

# 22sep10 shinobar clean up probable old files for precaution
 rm -f /pet.specs /pinstall.sh /puninstall.sh /install/doinst.sh

#get the pkg name ex: scite-1.77 ...
dbPATTERN='|'"$DLPKG_BASE"'|'
DLPKG_NAME="`cat /tmp/petget_missing_dbentries-Packages-* | grep "$dbPATTERN" | head -n 1 | cut -f 1 -d '|'`"

#131222 do not allow duplicate installs...
PTN1='^'"$DLPKG_NAME"'|'
if [ "`grep "$PTN1" /root/.packages/user-installed-packages`" != "" ];then
 if [ ! $DISPLAY ];then
  [ -f /tmp/install_quietly ] && DISPTIME1="--timeout 3" || DISPTIME1=''
  LANG=$LANG_USER
  dialog ${DISPTIME1} --msgbox "$(gettext 'This package is already installed. Cannot install it twice:') ${DLPKG_NAME}" 0 0
 else
  LANG=$LANG_USER
  if [ "$(</var/local/petget/ui_choice)" = "Classic" -o -f /tmp/install_classic ]; then
   /usr/lib/gtkdialog/box_ok "$(gettext 'Puppy package manager')" error "$(gettext 'This package is already installed. Cannot install it twice:')" "<i>${DLPKG_NAME}</i>"
   [ -f /tmp/install_classic ] && echo ${DLPKG_NAME} >> /tmp/pgks_failed_to_install_forced
  else
   /usr/lib/gtkdialog/box_ok "$(gettext 'Puppy package manager')" error "$(gettext 'This package is already installed. Cannot install it twice:')" "<i>${DLPKG_NAME}</i>" & 
   XPID=$!
   sleep 3
   pkill -P $XPID
   echo ${DLPKG_NAME} >> /tmp/pgks_failed_to_install_forced
  fi
 fi
 exit 1
fi

DIRECTSAVEPATH=""
read -r TFS TMAX TUSED TMPK TPERCENT TMNTPT <<<$(df -k | grep -w '^tmpfs') #free space in /tmp
SIZEB=`stat --format=%s "${DLPKG_PATH}"/${DLPKG_BASE}`
SIZEK=`expr $SIZEB \/ 1024`
EXPK=`expr $SIZEK \* 5` #estimated worst-case expanded size.
if [ "$PUPMODE" = "2" ]; then # from BK's quirky6.1
	#131220  131229 detect if not enough room in /tmp...
	DIRECTSAVEPATH="/tmp/petget/directsavepath"
	NEEDK=$EXPK
	if [ $EXPK -ge $TMPK ];then
	  DIRECTSAVEPATH="/audit/directsavepath"
	  NEEDK=`expr $NEEDK \* 2`
	fi
	if [ "$DIRECTSAVEPATH" ];then
	 rm -rf $DIRECTSAVEPATH
	 mkdir -p $DIRECTSAVEPATH
	fi
	# check enough space to install pkg...
	#as the pkg gets expanded to an intermediate dir, maybe in main f.s...
	PARTK=`df -k / | grep '/$' | tr -s ' ' | cut -f 4 -d ' '` #free space in partition.
	if [ $NEEDK -gt $PARTK ];then
	 LANG=$LANG_USER
	 if [ "$DISPLAY" ];then
	  /usr/lib/gtkdialog/box_ok "$(gettext 'Puppy package manager')" error "$(gettext 'Not enough free space in the partition to install this package'):" "<i>${DLPKG_BASE}</i>"
	 else
	  echo -e "$(gettext 'Not enough free space in the partition to install this package'):\n${DLPKG_BASE}"
	 fi
	 [ "$DLPKG_PATH" != "" ] && rm -f "${DLPKG_PATH}"/${DLPKG_BASE}
	 exit 1
	fi

#boot from flash: bypass tmpfs top layer, install direct to pup_save file... #170623 reverse this!
elif [ $PUPMODE -eq 3 -o $PUPMODE -eq 7 -o $PUPMODE -eq 13 ];then
	# SFR: let user chose...
	if [ -f /var/local/petget/install_mode ] ; then
	 IM="`cat /var/local/petget/install_mode`"
	 [ "$IM" = "false" ] && IMODE="tmpfs" || IMODE="savefile"
	else
	 IMODE="tmpfs"
	 if [ -n "$TMPK" ];then
	  if [ $TMPK -lt $EXPK ] ;then # EXPK is 5x package size
	   YMSG1=$(gettext "There is not enough temporary space to install the package: ")
	   YMSG2=$(gettext "Recommendation: Press 'No' to abort the installation and create some swap space. ('swap file' or 'swap partition'). You can press 'Yes' but corruption could occur in the installation.")
	   if [ "$DISPLAY" ];then
	    YTTLE=$(gettext "Puppy Package Manager")
	    /usr/lib/gtkdialog/box_yesno "$YTTLE" "${YMSG1}<i>${DLPKG_BASE}</i>" "$YMSG2"
	    yret=$?
	    case $yret in
	     1|255)exit 0;;
	     0)IMODE=savefile;;
	    esac
	   else
	    echo "$YMSG1 ${DLPKG_BASE}"
	    echo "$(gettext 'Recommendation: Abort this installation and create some swap space. Continue only if you know what you are doing.')"
	    echo "Abort? [y/N]"
	    read ABRT
	    case $ABRT in
	     y|Y)exit 0;;
	     n|N)IMODE=savefile;echo 'installing';;
	     *)exit 0;;
	    esac
	   fi
	  fi
	 fi
	fi
	if [ "$IMODE" != "tmpfs" ]; then
	 FLAGNODIRECT=1
	 #100426 aufs can now write direct to save layer...
	 #note: fsnotify now preferred not inotify, udba=notify uses whichever is enabled in module...
	 busybox mount -t aufs -o remount,udba=notify unionfs / #remount aufs with best evaluation mode.
	 FLAGNODIRECT=$?
	 [ $FLAGNODIRECT -ne 0 ] && logger -s -t "installpkg.sh" "Failed to remount aufs / with udba=notify"
	 if [ $FLAGNODIRECT -eq 0 ];then
	  #note that /sbin/pup_event_frontend_d will not run snapmergepuppy if installpkg.sh or downloadpkgs.sh are running.
	  while [ "`pidof snapmergepuppy`" != "" ];do
	   sleep 1
	  done
	  DIRECTSAVEPATH="/initrd${SAVE_LAYER}" #SAVE_LAYER is in /etc/rc.d/PUPSTATE.
	  #rm -f $DIRECTSAVEPATH/pet.specs $DIRECTSAVEPATH/pinstall.sh $DIRECTSAVEPATH/puninstall.sh $DIRECTSAVEPATH/install/doinst.sh
	  # create the symlinks needed if DISTRO_ARCHDIR is set
	  if [ -n "$DISTRO_ARCHDIR" ];then
		if [ ! -e "$DIRECTSAVEPATH/lib/$DISTRO_ARCHDIR" -o ! -e "$DIRECTSAVEPATH/usr/lib/$DISTRO_ARCHDIR" -o ! -e "$DIRECTSAVEPATH/usr/bin/$DISTRO_ARCHDIR" ];then
		 mkdir -p $DIRECTSAVEPATH/lib
		 mkdir -p $DIRECTSAVEPATH/usr/lib
		 mkdir -p $DIRECTSAVEPATH/usr/bin
		 ln -snf ./ $DIRECTSAVEPATH/lib/$DISTRO_ARCHDIR
		 ln -snf ./ $DIRECTSAVEPATH/usr/lib/$DISTRO_ARCHDIR
		 ln -snf ./ $DIRECTSAVEPATH/usr/bin/$DISTRO_ARCHDIR
		fi
	  fi
	 fi
	fi
fi

if [ $DISPLAY -a ! -f /tmp/install_quietly ];then #131222
 LANG=$LANG_USER
 . /usr/lib/gtkdialog/box_splash -close never -fontsize large -text "$(gettext 'Please wait, processing...')" &
 YAFPID1=$!
 trap 'pupkill $YAFPID1' EXIT #140318
fi

cd "$DLPKG_PATH"

case $DLPKG_BASE in
 *.pet)
  DLPKG_MAIN="`basename $DLPKG_BASE .pet`"
  pet2tgz $DLPKG_BASE || exit 1
  tarball=$(echo ${DLPKG_MAIN}.tar.[gx]z)
  PETFILES="$(tar --list -a -f $tarball)" || exit 1
  #check for renamed pets. Will produce an empty ${DLPKG_NAME}.files file
  PETFOLDER=$(echo "${PETFILES}" | cut -f 2 -d '/' | head -n 1)
  [ "$PETFOLDER" = "" ] && PETFOLDER=$(echo "${PETFILES}" | cut -f 1 -d '/' | head -n 1)
  if [ "${DLPKG_MAIN}" != "${PETFOLDER}" ]; then
   pupkill $YAFPID1
   LANG=$LANG_USER
   if [ "$DISPLAY" ]; then
    . /usr/lib/gtkdialog/box_ok "$(gettext 'Puppy Package Manager')" error "<b>${DLPKG_MAIN}.pet</b> $(gettext 'is named') <b>${PETFOLDER}</b> $(gettext 'inside the pet file. Will not install it!')"
   else
    . dialog --msgbox "$DLPKG_MAIN.pet $(gettext 'is named') $PETFOLDER $(gettext 'inside the pet file. Will not install it!')" 0 0
   fi
   exit 1
  fi
  if [ "`echo "$PETFILES" | grep -m1 '^\\./'`" != "" ];then
   #ttuuxx has created some pets with './' prefix...
   pPATTERN="s%^\\./${DLPKG_NAME}%%"
   echo "$PETFILES" | sed -e "$pPATTERN" > /root/.packages/${DLPKG_NAME}.files
   install_path_check
   tar -a -x --strip=2 --directory=${DIRECTSAVEPATH}/ -f ${tarball} #120102. 120107 remove --unlink-first
  else
   #new2dir and tgz2pet creates them this way...
   pPATTERN="s%^${DLPKG_NAME}%%"
   echo "$PETFILES" | sed -e "$pPATTERN" > /root/.packages/${DLPKG_NAME}.files
   install_path_check
   tar -a -x --strip=1 --directory=${DIRECTSAVEPATH}/ -f ${tarball} #120102. 120107. 131122
  fi
  rm -f "${tarball}"
  [ $? -ne 0 ] && clean_and_die
 ;;
 *.deb)
  DLPKG_MAIN="`basename $DLPKG_BASE .deb`"
  PFILES="`dpkg-deb --contents $DLPKG_BASE | tr -s ' ' | cut -f 6 -d ' '`"
  [ $? -ne 0 ] && exit 1
  echo "$PFILES" > /root/.packages/${DLPKG_NAME}.files
  install_path_check
  # Workaround to avoid overwriting the $DISTRO_ARCHDIR symlink.  
  if [ "$DISTRO_ARCHDIR" != "" -a "$(echo "$PFILES" | grep "$DISTRO_ARCHDIR")" != "" ]; then
	   mkdir -p /tmp/$DLPKG_BASE
	   rm -rf /tmp/$DLPKG_BASE/*
	   dpkg-deb -x $DLPKG_BASE /tmp/$DLPKG_BASE/
	   for f in $(find /tmp/$DLPKG_BASE \( -type f -o -type l \))
    do
       xpath=$(echo $f |  cut  -f 4-30 -d "/" | sed "s/$DISTRO_ARCHDIR\///")
       mkdir -p ${DIRECTSAVEPATH}/$(dirname $xpath)
       cp -a $f ${DIRECTSAVEPATH}/$(dirname $xpath)/
    done
	   rm -rf /tmp/$DLPKG_BASE
  else
	   dpkg-deb -x $DLPKG_BASE ${DIRECTSAVEPATH}/
  fi
  [ $? -ne 0 ] && clean_and_die
  [ -d /DEBIAN ] && rm -rf /DEBIAN #130112 precaution.
  dpkg-deb -e $DLPKG_BASE /DEBIAN #130112 extracts deb control files to dir /DEBIAN. may have a post-install script, see below.
 ;;
 *.tgz|*.txz|*.tar.gz|*.tar.xz|*.tar.bz2) #slackware, arch, etc..
  DLPKG_MAIN="`basename $DLPKG_BASE`" #remove directory - filename only
  DLPKG_MAIN=${DLPKG_MAIN%*.tar.*}    #remove .tar.xx extension
  DLPKG_MAIN=${DLPKG_MAIN%.t[gx]z}    #remove .t[gx]z extension
  PFILES="`tar --list -a -f $DLPKG_BASE`" || exit 1
  echo "$PFILES" > /root/.packages/${DLPKG_NAME}.files
  install_path_check
  tar -a -x --directory=${DIRECTSAVEPATH}/ -f $DLPKG_BASE #120102. 120107
  [ $? -ne 0 ] && clean_and_die
 ;;
 *.rpm) #110523
  DLPKG_MAIN="`basename $DLPKG_BASE .rpm`"
  busybox rpm -qp $DLPKG_BASE > /dev/null 2>&1
  [ $? -ne 0 ] && exit 1
  PFILES="`busybox rpm -qpl $DLPKG_BASE`"
  [ $? -ne 0 ] && exit 1
  echo "$PFILES" > /root/.packages/${DLPKG_NAME}.files
  install_path_check
  #110705 rpm -i does not work for mageia pkgs...
  exploderpm -i $DLPKG_BASE
  [ $? -ne 0 ] && clean_and_die
 ;;
esac

if [ "$PUPMODE" = "2" ]; then #from BK's quirky6.1
	mkdir /audit/${DLPKG_NAME}DEPOSED
	echo -n '' > /tmp/petget/FLAGFND
	find ${DIRECTSAVEPATH}/ -mindepth 1 | sed -e "s%${DIRECTSAVEPATH}%%" |
	while read AFILESPEC
	do
	  if [ -f "$AFILESPEC" ];then
	   ADIR="$(dirname "$AFILESPEC")"
	   mkdir -p /audit/${DLPKG_NAME}DEPOSED/${ADIR}
	   cp -a -f "$AFILESPEC" /audit/${DLPKG_NAME}DEPOSED/${ADIR}/
	   echo -n '1' > /tmp/petget/FLAGFND
	  fi
	done
	sync
	if [ -s /tmp/petget/FLAGFND ];then
	  [ -f /audit/${DLPKG_NAME}DEPOSED.sfs ] && rm -f /audit/${DLPKG_NAME}DEPOSED.sfs #precaution, should not happen, as not allowing duplicate installs of same pkg.
	  mksquashfs /audit/${DLPKG_NAME}DEPOSED /audit/${DLPKG_NAME}DEPOSED.sfs
	fi
	sync
	rm -rf /audit/${DLPKG_NAME}DEPOSED
	#now write temp-location to final destination...
	cp -a -f --remove-destination ${DIRECTSAVEPATH}/* /  2> /tmp/petget/install-cp-errlog
	sync
	#can have a problem if want to replace a folder with a symlink. for example, got this error:
	# cp: cannot overwrite directory '/usr/share/mplayer/skins' with non-directory
	#3builddistro has this fix... which is a vice-versa situation...
	#firstly, the vice-versa, source is a directory, target is a symlink...
	CNT=0
	while [ -s /tmp/petget/install-cp-errlog ];do
	  echo -n '' > /tmp/petget/install-cp-errlog2
	  echo -n '' > /tmp/petget/install-cp-errlog3
	  cat /tmp/petget/install-cp-errlog | grep 'cannot overwrite non-directory' | grep 'with directory' | tr '[`‘’]' "'" | cut -f 2 -d "'" |
	  while read ONEDIRSYMLINK #ex: /usr/share/mplayer/skins
	  do
	   if [ -h "${ONEDIRSYMLINK}" ];then #source is a directory, target is a symlink...
	    #adding that extra trailing / does the trick...
	    cp -a -f --remove-destination ${DIRECTSAVEPATH}"${ONEDIRSYMLINK}"/* "${ONEDIRSYMLINK}"/ 2>> /tmp/petget/install-cp-errlog2
	   else #source is a directory, target is a file...
	    rm -f "${ONEDIRSYMLINK}" #delete the file!
	    DIRPATH="$(dirname "${ONEDIRSYMLINK}")"
	    cp -a -f ${DIRECTSAVEPATH}"${ONEDIRSYMLINK}" "${DIRPATH}"/ 2>> /tmp/petget/install-cp-errlog2 #copy directory (and contents).
	   fi
	  done
	  cat /tmp/petget/install-cp-errlog2 >> /tmp/petget/install-cp-errlog3
	  cat /tmp/petget/install-cp-errlog3 > /tmp/petget/install-cp-errlog
	  sync
	  CNT=`expr $CNT + 1`
	  [ $CNT -gt 10 ] && break #something wrong, get out.
	done
	#end 131220

	rm -rf ${DIRECTSAVEPATH} #131229 131230
	[ "$DL_SAVE_FLAG" != "true" ] && rm -f $DLPKG_BASE 2>/dev/null
	rm -f $DLPKG_MAIN.tar.gz 2>/dev/null
	#pkgname.files may need to be fixed...
	FIXEDFILES="`cat /root/.packages/${DLPKG_NAME}.files | grep -v '^\\./$'| grep -v '^/$' | sed -e 's%^\\.%%' -e 's%^%/%' -e 's%^//%/%'`"
	echo "$FIXEDFILES" > /root/.packages/${DLPKG_NAME}.files 

else #-- anything other than PUPMODE 2 (full install) --

	[ "$DL_SAVE_FLAG" != "true" ] &&  rm -f $DLPKG_BASE 2>/dev/null
	rm -f $DLPKG_MAIN.tar.${EXT} 2>/dev/null #131122

	#pkgname.files may need to be fixed...
	FIXEDFILES="`cat /root/.packages/${DLPKG_NAME}.files | grep -v '^\\./$'| grep -v '^/$' | sed -e 's%^\\.%%' -e 's%^%/%' -e 's%^//%/%'`"
	echo "$FIXEDFILES" > /root/.packages/${DLPKG_NAME}.files

	#120102 install may have overwritten a symlink-to-dir...
	#tar defaults to not following symlinks, for both dirs and files, but i want to follow symlinks
	#for dirs but not for files. so, fix here... (note, dir entries in .files have / on end)
	cat /root/.packages/${DLPKG_NAME}.files | grep '[a-zA-Z0-9]/$' | sed -e 's%/$%%' | grep -v '^/mnt' |
	while read ONESPEC
	do
	 if [ -d "${DIRECTSAVEPATH}${ONESPEC}" ];then
	  if [ ! -h "${DIRECTSAVEPATH}${ONESPEC}" ];then
	   DIRLINK=""
	   if [ -h "/initrd${PUP_LAYER}${ONESPEC}" ];then #120107
	    DIRLINK="`readlink -m "/initrd${PUP_LAYER}${ONESPEC}" | sed -e "s%/initrd${PUP_LAYER}%%"`" #PUP_LAYER: see /etc/rc.d/PUPSTATE. 120107
	    xDIRLINK="`readlink "/initrd${PUP_LAYER}${ONESPEC}"`" #120107
	   fi
	   if [ ! "$DIRLINK" ];then
	    if [ -h "/initrd${SAVE_LAYER}${ONESPEC}" ];then #120107
	     DIRLINK="`readlink -m "/initrd${SAVE_LAYER}${ONESPEC}" | sed -e "s%/initrd${SAVE_LAYER}%%"`" #SAVE_LAYER: see /etc/rc.d/PUPSTATE. 120107
	     xDIRLINK="`readlink "/initrd${SAVE_LAYER}${ONESPEC}"`" #120107
	    fi
	   fi
	   if [ "$DIRLINK" ];then
	    if [ -d "$DIRLINK"  ];then
	     if [ "$DIRLINK" != "${ONESPEC}" ];then #precaution.
	      mkdir -p "${DIRECTSAVEPATH}${DIRLINK}" #120107
	      cp -a -f --remove-destination ${DIRECTSAVEPATH}"${ONESPEC}"/* "${DIRECTSAVEPATH}${DIRLINK}/" #ha! fails if put double-quotes around entire expression.
	      rm -rf "${DIRECTSAVEPATH}${ONESPEC}"
	      if [ "$DIRECTSAVEPATH" = "" ];then
	       ln -s "$xDIRLINK" "${ONESPEC}"
	      else
	       DSOPATH="`dirname "${DIRECTSAVEPATH}${ONESPEC}"`"
	       DSOBASE="`basename "${DIRECTSAVEPATH}${ONESPEC}"`"
	       rm -f "${DSOPATH}/.wh.${DSOBASE}" #allow underlying symlink to become visible on top.
	      fi
	     fi
	    fi
	   fi
	  fi
	 fi
	done

	#121217 it seems that this problem is occurring in other modes (13 reported)...
	#121123 having a problem with multiarch symlinks in full-installation...
	#it seems that the symlink is getting replaced by a directory.
	if [ "$DISTRO_ARCHDIR" ];then #in /etc/rc.d/DISTRO_SPECS. 130112 change test from DISTRO_ARCHDIR. 130114 revert DISTRO_ARCHDIR_SYMLINKS==yes.
	  if [ -d /usr/lib/${DISTRO_ARCHDIR} ];then
	   if [ ! -h /usr/lib/${DISTRO_ARCHDIR} ];then
	    cp -a -f --remove-destination /usr/lib/${DISTRO_ARCHDIR}/* /usr/lib/
	    sync
	    rm -r -f /usr/lib/${DISTRO_ARCHDIR}
	    ln -s ./ /usr/lib/${DISTRO_ARCHDIR}
	   fi
	  fi
	  if [ -d /lib/${DISTRO_ARCHDIR} ];then
	   if [ ! -h /lib/${DISTRO_ARCHDIR} ];then
	    cp -a -f --remove-destination /lib/${DISTRO_ARCHDIR}/* /lib/
	    sync
	    rm -r -f /lib/${DISTRO_ARCHDIR}
	    ln -s ./ /lib/${DISTRO_ARCHDIR}
	   fi
	  fi
	  if [ -d /usr/bin/${DISTRO_ARCHDIR} ];then
	   if [ ! -h /usr/bin/${DISTRO_ARCHDIR} ];then
	    cp -a -f --remove-destination /usr/bin/${DISTRO_ARCHDIR}/* /usr/bin/
	    sync
	    rm -r -f /usr/bin/${DISTRO_ARCHDIR}
	    ln -s ./ /usr/bin/${DISTRO_ARCHDIR}
	   fi
	  fi
	fi

	#flush unionfs cache, so files in pup_save layer will appear "on top"...
	if [ "$DIRECTSAVEPATH" != "" ];then
	 #but first, clean out any bad whiteout files...
	 # 22sep10 shinobar: bugfix was not working clean out whiteout files
	 find /initrd/pup_rw -mount -type f -name .wh.\*  -printf '/%P\n'|
	 while read ONEWHITEOUT
	 do
	  ONEWHITEOUTFILE="`basename "$ONEWHITEOUT"`"
	  ONEWHITEOUTPATH="`dirname "$ONEWHITEOUT"`"
	  if [ "$ONEWHITEOUTFILE" = ".wh.__dir_opaque" ];then
	   [ "`grep "$ONEWHITEOUTPATH" /root/.packages/${DLPKG_NAME}.files`" != "" ] && rm -f "/initrd/pup_rw/$ONEWHITEOUT"
	   continue
	  fi
	  ONEPATTERN="`echo -n "$ONEWHITEOUT" | sed -e 's%/\\.wh\\.%/%'`"'/*'	;#echo "$ONEPATTERN" >&2
	  [ "`grep -x "$ONEPATTERN" /root/.packages/${DLPKG_NAME}.files`" != "" ] && rm -f "/initrd/pup_rw/$ONEWHITEOUT"
	 done
	 #111229 /usr/local/petget/removepreview.sh when uninstalling a pkg, may have copied a file from sfs-layer to top, check...
	 cat /root/.packages/${DLPKG_NAME}.files |
	 while read ONESPEC
	 do
	  [ "$ONESPEC" = "" ] && continue #precaution.
	  if [ ! -d "$ONESPEC" ];then
	   [ -e "/initrd/pup_rw${ONESPEC}" ] && rm -f "/initrd/pup_rw${ONESPEC}"
	  fi
	 done
	 #now re-evaluate all the layers...
	 busybox mount -t aufs -o remount,udba=reval unionfs / #remount with faster evaluation mode.
	 [ $? -ne 0 ] && logger -s -t "installpkg.sh" "Failed to remount aufs / with udba=reval"

	 sync
	fi

fi

#some .pet pkgs have images at '/'...
mv /{*.xpm,*.png} /usr/share/pixmaps/ 2>/dev/null

ls -dl /tmp | grep -q '^drwxrwxrwt' || chmod 1777 /tmp #130305 rerwin.

#post-install script?...
#          puppy         slackware       debian/ubuntu/etc
for i in pinstall.sh install/doinst.sh DEBIAN/postinst
do
	[ ! -e "$DIRECTSAVEPATH/$i" ] && continue
	chmod +x $DIRECTSAVEPATH/${i}
	cd $DIRECTSAVEPATH/
	LANG=$LANG_USER nohup sh ${i} &
	sleep 0.2
	rm -f ${i}
done
rm -rf $DIRECTSAVEPATH/install
rm -rf $DIRECTSAVEPATH/DEBIAN
#130314 run arch linux pkg post-install script...
if [ -f $DIRECTSAVEPATH/.INSTALL ];then #arch post-install script.
 if [ -f /usr/local/petget/ArchRunDotInstalls ];then #precaution. see 3builddistro, script created by noryb009.
  #this code is taken from below...
  dlPATTERN='|'"`echo -n "$DLPKG_BASE" | sed -e 's%\\-%\\\\-%'`"'|'
  archVER="`cat /tmp/petget_missing_dbentries-Packages-* | grep "$dlPATTERN" | head -n 1 | cut -f 3 -d '|'`"
  if [ "$archVER" ];then #precaution.
   cd $DIRECTSAVEPATH/
   mv -f .INSTALL .INSTALL1-${archVER}
   cp -a /usr/local/petget/ArchRunDotInstalls ArchRunDotInstalls
   LANG=$LANG_USER ./ArchRunDotInstalls
   rm -f ArchRunDotInstalls
   rm -f .INSTALL*
  fi
 fi
fi

#v424 .pet pkgs may have a post-uninstall script...
if [ -f $DIRECTSAVEPATH/puninstall.sh ];then
 mv -f $DIRECTSAVEPATH/puninstall.sh /root/.packages/${DLPKG_NAME}.remove
fi

#w465 <pkgname>.pet.specs is in older pet pkgs, just dump it...
#maybe a '$APKGNAME.pet.specs' file created by dir2pet script...
rm -f $DIRECTSAVEPATH/*.pet.specs 2>/dev/null
#...note, this has a setting to prevent .files and entry in user-installed-packages, so install not registered.

#add entry to /root/.packages/user-installed-packages...
#w465 a pet pkg may have /pet.specs which has a db entry...
if [ -f $DIRECTSAVEPATH/pet.specs -a -s $DIRECTSAVEPATH/pet.specs ];then #w482 ignore zero-byte file.
 DB_ENTRY="`cat $DIRECTSAVEPATH/pet.specs | head -n 1`"
 rm -f $DIRECTSAVEPATH/pet.specs
else
 [ -f $DIRECTSAVEPATH/pet.specs ] && rm -f $DIRECTSAVEPATH/pet.specs #w482 remove zero-byte file.
 dlPATTERN='|'"`echo -n "$DLPKG_BASE" | sed -e 's%\\-%\\\\-%'`"'|'
 DB_ENTRY="`cat /tmp/petget_missing_dbentries-Packages-* | grep "$dlPATTERN" | head -n 1`"
fi
##+++2011-12-27 KRG check if $DLPKG_BASE matches DB_ENTRY 1 so uninstallation works :Ooops:
db_pkg_name=`echo "$DB_ENTRY" |cut -f 1 -d '|'`
if [ "$db_pkg_name" != "$DLPKG_NAME" ];then
 DB_ENTRY=`echo "$DB_ENTRY" |sed "s#$db_pkg_name#$DLPKG_NAME#"`
fi
##+++2011-12-27 KRG

#see if a .desktop file was installed, fix category... 120628 improve...
#120818 overhauled. Pkg db now has category[;subcategory] (see 0setup), xdg enhanced (see /etc/xdg and /usr/share/desktop-directories), and generic icons for all subcategories (see /usr/local/lib/X11/mini-icons).
#note, similar code also in Woof 2createpackages.
ONEDOT=""
CATEGORY="`echo -n "$DB_ENTRY" | cut -f 5 -d '|'`" #exs: Document, Document;edit
[ "$CATEGORY" = "" ] && CATEGORY='BuildingBlock' #paranoid precaution.
#xCATEGORY and DEFICON will be the fallbacks if Categories entry in .desktop is invalid...
xCATEGORY="`echo -n "$CATEGORY" | sed -e 's%^%X-%' -e 's%;%-%'`" #ex: X-Document-edit (refer /etc/xdg/menu/*.menu)
DEFICON="`echo -n "$CATEGORY" | sed -e 's%;%-%'`"'.svg' #ex: Document-edit (refer /usr/share/pixmaps/puppy -- these are in jwm search path)
case $CATEGORY in
 Calculate)     CATEGORY='Business'             ; xCATEGORY='X-Business'            ; DEFICON='Business.svg'            ;; #Calculate is old name, now Business.
 Develop)       CATEGORY='Utility;development'  ; xCATEGORY='X-Utility-development' ; DEFICON='Utility-development.svg' ;; #maybe an old pkg has this.
 Help)          CATEGORY='Utility;help'         ; xCATEGORY='X-Utility-help'        ; DEFICON='Help.svg'                ;; #maybe an old pkg has this.
 BuildingBlock) CATEGORY='Utility'              ; xCATEGORY='Utility'               ; DEFICON='BuildingBlock.svg'       ;; #unlikely to have a .desktop file.
esac
topCATEGORY="`echo -n "$CATEGORY" | cut -f 1 -d ';'`"
tPATTERN="^${topCATEGORY} "
cPATTERN="s%^Categories=.*%Categories=${xCATEGORY}%"
iPATTERN="s%^Icon=.*%Icon=${DEFICON}%"

#121119 if only one .desktop file, first check if a match in /usr/local/petget/categories.dat...
CATDONE='no'
if [ -f /usr/local/petget/categories.dat ];then #precaution, but it will be there.
 NUMDESKFILE="$(grep 'share/applications/.*\.desktop$' /root/.packages/${DLPKG_NAME}.files | wc -l)"
 if [ "$NUMDESKFILE" = "1" ];then
  #to lookup categories.dat, we need to know the generic name of the package, which may be different from pkg name...
  #db entry format: pkgname|nameonly|version|pkgrelease|category|size|path|fullfilename|dependencies|description|compileddistro|compiledrelease|repo|
  DBNAMEONLY="$(echo -n "$DB_ENTRY" | cut -f 2 -d '|')"
  DBPATH="$(echo -n "$DB_ENTRY" | cut -f 7 -d '|')"
  DBCOMPILEDDISTRO="$(echo -n "$DB_ENTRY" | cut -f 11 -d '|')"
  [ ! "$DBCOMPILEDDISTRO" ] && DBCOMPILEDDISTRO='puppy' #any name will do here.
  case $DBCOMPILEDDISTRO in
   debian|devuan|ubuntu|raspbian)
    if [ "$DBPATH" ];then #precaution
     xNAMEONLY="$(basename ${DBPATH})"
    else
     xNAMEONLY="$DBNAMEONLY"
    fi
   ;;
   *) xNAMEONLY="$DBNAMEONLY" ;;
  esac
  xnPTN=" ${xNAMEONLY} "
  #130126 categories.dat format changed slightly... 130219 ignore case...
  CATVARIABLE="$(grep -i "$xnPTN" /usr/local/petget/categories.dat | grep '^PKGCAT' | head -n 1 | cut -f 1 -d '=' | cut -f 2,3 -d '_' | tr '_' '-')" #ex: PKGCAT_Graphic_camera=" gphoto2 gtkam "
  if [ "$CATVARIABLE" ];then #ex: Graphic-camera
   xCATEGORY="X-${CATVARIABLE}"
   cPATTERN="s%^Categories=.*%Categories=${xCATEGORY}%" #121120
   CATFOUND="yes"
   CATDONE='yes'
  fi
 fi
fi

for ONEDOT in `grep 'share/applications/.*\.desktop$' /root/.packages/${DLPKG_NAME}.files | tr '\n' ' '` #121119 exclude other strange .desktop files.
do
 #120901 get rid of param on end of Exec, ex: Exec=gimp-2.8 %U
 #sed -i -e 's/\(^Exec=[^%]*\).*/\1/' -e 's/ *$//' $ONEDOT #'s/\(^Exec=[^ ]*\).*/\1/'
 #121015 01micko: alternative that may work better...
 for PARMATER in u U f F #refer:  http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html
 do
  sed -i "s/ %${PARMATER}//" $ONEDOT
 done
 
 #w478 find if category is already valid (see also 2createpackages)..
 if [ "$CATDONE" = "no" ];then #121119
  CATFOUND="no"
  for ONEORIGCAT in `cat $ONEDOT | grep '^Categories=' | head -n 1 | cut -f 2 -d '=' | tr ';' ' ' | rev` #search in reverse order.
  do
   ONEORIGCAT="`echo -n "$ONEORIGCAT" | rev`" #restore rev of one word.
   oocPATTERN=' '"$ONEORIGCAT"' '
   [ "`echo "$PUPHIERARCHY" | tr -s ' ' | grep "$tPATTERN" | cut -f 3 -d ' ' | tr ',' ' ' | sed -e 's%^% %' -e 's%$% %' | grep "$oocPATTERN"`" != "" ] && CATFOUND="yes"
   #got a problem with sylpheed, "Categories=GTK;Network;Email;News;" this displays in both Network and Internet menus...
   if [ "$CATFOUND" = "yes" ];then
    cPATTERN="s%^Categories=.*%Categories=${ONEORIGCAT}%"
    break
   fi
  done
  #121109 above may fail, as DB_category field may not match that in .desktop file, so leave out that $tPATTERN match in $PUPHIERARCHY...
  if [ "$CATFOUND" = "no" ];then
   for ONEORIGCAT in `cat $ONEDOT | grep '^Categories=' | head -n 1 | cut -f 2 -d '=' | tr ';' ' ' | rev` #search in reverse order.
   do
    ONEORIGCAT="`echo -n "$ONEORIGCAT" | rev`" #restore rev of one word.
    oocPATTERN=' '"$ONEORIGCAT"' '
    [ "`echo "$PUPHIERARCHY" | tr -s ' ' | cut -f 3 -d ' ' | tr ',' ' ' | sed -e 's%^% %' -e 's%$% %' | grep "$oocPATTERN"`" != "" ] && CATFOUND="yes"
    #got a problem with sylpheed, "Categories=GTK;Network;Email;News;" this displays in both Network and Internet menus...
    if [ "$CATFOUND" = "yes" ];then
     cPATTERN="s%^Categories=.*%Categories=${ONEORIGCAT}%"
     break
    fi
   done
  fi
 fi
 sed -i -e "$cPATTERN" $ONEDOT #fix Categories= entry.

 #w019 does the icon exist?...
 ICON="`grep '^Icon=' $ONEDOT | cut -f 2 -d '='`"
 if [ "$ICON" != "" ];then
  [ -e "$ICON" ] && continue #it may have a hardcoded path.
  ICONBASE="`basename "$ICON"`"
  #110706 fix icon entry in .desktop... 110821 improve...
  #first search where jwm looks for icons... 111207...
  FNDICON="`find /usr/share/pixmaps -maxdepth 2 -name $ICONBASE -o -name $ICONBASE.png -o -name $ICONBASE.xpm -o -name $ICONBASE.jpg -o -name $ICONBASE.jpeg -o -name $ICONBASE.gif -o -name $ICONBASE.svg | grep -i -E 'png$|xpm$|jpg$|jpeg$|gif$|svg$' | head -n 1`"
  if [ "$FNDICON" ];then
   ICONNAMEONLY="`basename $FNDICON`"
   iPTN="s%^Icon=.*%Icon=${ICONNAMEONLY}%"
   sed -i -e "$iPTN" $ONEDOT
   continue
  else
   #look elsewhere... 111207...
   FNDICON="`find /usr/share/icons /usr/local/share/pixmaps -name $ICONBASE -o -name $ICONBASE.png -o -name $ICONBASE.xpm -o -name $ICONBASE.jpg -o -name $ICONBASE.jpeg -o -name $ICONBASE.gif -o -name $ICONBASE.svg | grep -i -E 'png$|xpm$|jpg$|jpeg$|gif$|svg$' | head -n 1`"
   #111207 look further afield, ex parole pkg has /usr/share/parole/pixmaps/parole.png...
   [ ! "$FNDICON" ] && [ -d /usr/share/$ICONBASE ] && FNDICON="`find /usr/share/${ICONBASE} -name $ICONBASE -o -name $ICONBASE.png -o -name $ICONBASE.xpm -o -name $ICONBASE.jpg -o -name $ICONBASE.jpeg -o -name $ICONBASE.gif -o -name $ICONBASE.svg | grep -i -E 'png$|xpm$|jpg$|jpeg$|gif$|svg$' | head -n 1`"
   #111207 getting desperate...
   [ ! "$FNDICON" ] && FNDICON="`find /usr/share -name $ICONBASE -o -name $ICONBASE.png -o -name $ICONBASE.xpm -o -name $ICONBASE.jpg -o -name $ICONBASE.jpeg -o -name $ICONBASE.gif -o -name $ICONBASE.svg | grep -i -E 'png$|xpm$|jpg$|jpeg$|gif$|svg$' | head -n 1`"
   if [ "$FNDICON" ];then
    ICONNAMEONLY="`basename "$FNDICON"`"
    ln -snf "$FNDICON" /usr/share/pixmaps/${ICONNAMEONLY}
    iPTN="s%^Icon=.*%Icon=${ICONNAMEONLY}%"
    sed -i -e "$iPTN" $ONEDOT
    continue
   fi
  fi
  #substitute a default icon...
  sed -i -e "$iPATTERN" $ONEDOT #note, ONEDOT is name of .desktop file.
 fi
 
 #120926 if a langpack installed, it will have /usr/share/applications.in (see /usr/sbin/momanager, /usr/share/doc/langpack-template/pinstall.sh).
 ABASEDESKTOP="`basename $ONEDOT`"
 ADIRDESKTOP="`dirname $ONEDOT`"
 if [ -f /usr/share/applications.in/${ABASEDESKTOP} ];then
  TARGETLANG="`echo -n $LANG_USER | cut -f 1 -d '_'`" #ex: de
  tlPTN="^Name\[${TARGETLANG}\]"
  if [ "$(grep "$tlPTN" ${ADIRDESKTOP}/${ABASEDESKTOP})" = "" ];then
   if [ "$(grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP})" != "" ];then
    #aaargh, these accursed back-slashes! ....
    INSERTALINE="`grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP} | sed -e 's%\[%\\\\[%' -e 's%\]%\\\\]%'`"
    sed -i -e "s%^Name=%${INSERTALINE}\\nName=%" ${ADIRDESKTOP}/${ABASEDESKTOP}
   fi
  fi
  #do same for Comment field...
  tlPTN="^Comment\[${TARGETLANG}\]"
  if [ "$(grep "$tlPTN" ${ADIRDESKTOP}/${ABASEDESKTOP})" = "" ];then
   if [ "$(grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP})" != "" ];then
    #aaargh, these accursed back-slashes! ....
    INSERTALINE="`grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP} | sed -e 's%\[%\\\\[%' -e 's%\]%\\\\]%'`"
    sed -i -e "s%^Comment=%${INSERTALINE}\\nComment=%" ${ADIRDESKTOP}/${ABASEDESKTOP}
   fi
  fi
  #well, i suppose need this too...
  TARGETLANG="`echo -n $LANG_USER | cut -f 1 -d '.'`" #ex: de_DE
  tlPTN="^Name\[${TARGETLANG}\]"
  if [ "$(grep "$tlPTN" ${ADIRDESKTOP}/${ABASEDESKTOP})" = "" ];then
   if [ "$(grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP})" != "" ];then
    #aaargh, these accursed back-slashes! ....
    INSERTALINE="`grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP} | sed -e 's%\[%\\\\[%' -e 's%\]%\\\\]%'`"
    sed -i -e "s%^Name=%${INSERTALINE}\\nName=%" ${ADIRDESKTOP}/${ABASEDESKTOP}
   fi
  fi
  #do same for Comment field...
  tlPTN="^Comment\[${TARGETLANG}\]"
  if [ "$(grep "$tlPTN" ${ADIRDESKTOP}/${ABASEDESKTOP})" = "" ];then
   if [ "$(grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP})" != "" ];then
    #aaargh, these accursed back-slashes! ....
    INSERTALINE="`grep "$tlPTN" /usr/share/applications.in/${ABASEDESKTOP} | sed -e 's%\[%\\\\[%' -e 's%\]%\\\\]%'`"
    sed -i -e "s%^Comment=%${INSERTALINE}\\nComment=%" ${ADIRDESKTOP}/${ABASEDESKTOP}
   fi
  fi
 fi
 
done

#due to images at / in .pet and post-install script, .files may have some invalid entries...
INSTFILES="`cat /root/.packages/${DLPKG_NAME}.files`"
echo "$INSTFILES" |
while read ONEFILE
do
 if [ ! -e "$ONEFILE" ];then
  ofPATTERN='^'"$ONEFILE"'$'
  grep -v "$ofPATTERN" /root/.packages/${DLPKG_NAME}.files > /tmp/petget_instfiles
  mv -f /tmp/petget_instfiles /root/.packages/${DLPKG_NAME}.files
 fi
done

#w482 DB_ENTRY may be missing DB_category and DB_description fields...
#pkgname|nameonly|version|pkgrelease|category|size|path|fullfilename|dependencies|description|
#optionally on the end: compileddistro|compiledrelease|repo| (fields 11,12,13)
DESKTOPFILE="`grep '\.desktop$' /root/.packages/${DLPKG_NAME}.files | head -n 1`"
if [ "$DESKTOPFILE" != "" ];then
 DB_category="`echo -n "$DB_ENTRY" | cut -f 5 -d '|'`"
 DB_description="`echo -n "$DB_ENTRY" | cut -f 10 -d '|'`"
 CATEGORY="$DB_category"
 DESCRIPTION="$DB_description"
 zCATEGORY="`cat $DESKTOPFILE | grep '^Categories=' | sed -e 's%;$%%' | cut -f 2 -d '=' | rev | cut -f 1 -d ';' | rev`" #121109
 if [ "$zCATEGORY" != "" ];then #121109
  #v424 but want the top-level menu category...
  catPATTERN="[ ,]${zCATEGORY},|[ ,]${zCATEGORY} |[ ,]${zCATEGORY}"'$' #121119 fix bug in pattern.
  CATEGORY="`echo "$PUPHIERARCHY" | cut -f 1 -d '#' | grep -E "$catPATTERN" | grep ':' | cut -f 1 -d ' ' | head -n 1`" #121119 /etc/xdg/menus/hierarchy 
 fi
 if [ "$DB_description" = "" ];then
  DESCRIPTION="`cat $DESKTOPFILE | grep '^Comment=' | cut -f 2 -d '='`"
  [ "$DESCRIPTION" = "" ] && DESCRIPTION="`cat $DESKTOPFILE | grep '^Name=' | cut -f 2 -d '='`"	# shinobar
 fi
 if [ "$DB_category" = "" -o "$DB_description" = "" ];then
  newDB_ENTRY="`echo -n "$DB_ENTRY" | cut -f 1-4 -d '|'`"
  newDB_ENTRY="$newDB_ENTRY"'|'"$CATEGORY"'|'
  newDB_ENTRY="$newDB_ENTRY""`echo -n "$DB_ENTRY" | cut -f 6-9 -d '|'`"
  newDB_ENTRY="$newDB_ENTRY"'|'"$DESCRIPTION"'|'
  newDB_ENTRY="$newDB_ENTRY""`echo -n "$DB_ENTRY" | cut -f 11-14 -d '|'`"
  DB_ENTRY="$newDB_ENTRY"
 fi
fi

echo "$DB_ENTRY" >> /root/.packages/user-installed-packages

#120907 post-install hacks...
/usr/local/petget/hacks-postinstall.sh $DLPKG_MAIN

#announcement of successful install...
#announcement is done after all downloads, in downloadpkgs.sh...
CATEGORY="`echo -n "$CATEGORY" | cut -f 1 -d ';'`"
[ "$CATEGORY" = "" ] && CATEGORY="none"
[ "$CATEGORY" = "BuildingBlock" ] && CATEGORY="none"
echo "PACKAGE: $DLPKG_NAME CATEGORY: $CATEGORY" >> /tmp/petget-installed-pkgs-log

#110503 change ownership of some files if non-root...
#hmmm, i think this will only work if running this script as root...
# (the entry script pkg_chooser.sh has sudo to switch to root)
HOMEUSER="`grep '^tty1' /etc/inittab | tr -s ' ' | cut -f 3 -d ' '`" #root or uzer.
if [ "$HOMEUSER" != "root" ];then
 grep -E '^/var|^/root|^/etc' /root/.packages/${DLPKG_NAME}.files |
 while read FILELINE
 do
  busybox chown ${HOMEUSER}:users "${FILELINE}"
 done
fi

#120523 precise puppy needs this... (refer also rc.update and 3builddistro)
if [ "`grep '/usr/share/glib-2.0/schemas' /root/.packages/${DLPKG_NAME}.files`" != "" ];then
 [ -e /usr/bin/glib-compile-schemas ] && /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas
fi
if [ "`grep '/usr/lib/gio/modules' /root/.packages/${DLPKG_NAME}.files`" != "" ];then
 [ -e /usr/bin/gio-querymodules ] && /usr/bin/gio-querymodules /usr/lib/gio/modules
fi

rm -f $HOME/nohup.out

###END###
