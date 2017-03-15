#!/bin/bash
. options.conf
[ ! -d "$tmp_dir" ] && mkdir -p "$tmp_dir"
[ ! -d "$downloads_dir" ] && mkdir -p "$downloads_dir"
J=${J:-$make_j}

usage() {
	echo "Usage: $0 [-f <feeds.conf.default>] [-d <target>] [-b <target>] [-a]"
	echo "	-a		: download all SDK and IB"
	echo "	-f <file>	: download feeds based on feeds.conf file"
	echo "	-b <target>	: build target"
	echo "	-d <target>	: download SDK and IB for target"
	echo ""
	echo "Example of usage for building ar71xx target:"
	echo "  $0 -d ar71xx/generic"
	echo "  $0 -f feeds.conf.default"
	echo "  $0 -b ar71xx/generic"
}

build_packets() {
	target="$1"
	sdk="$release/$target/sdk"
	
	[ ! -d "$sdk" ] && { 
		echo "You must download first SDK"
		usage
		exit 1
	}
	
	[ -f $feeds_file ] && cp $feeds_file $sdk/feeds.conf || {
		echo "Local feeds file not found, using standard remote feeds"
		cp -f $sdk/feeds.conf.default $sdk/feeds.conf
		echo "src-git libremesh $lime_repo;$lime_branch" >> $sdk/feeds.conf
		echo "src-git libremap $limap_repo;$limap_branch" >> $sdk/feeds.conf
		echo "src-git limeui $limeui_repo;$limeui_branch" >> $sdk/feeds.conf
	}
	(cd $sdk && scripts/feeds update -a)
	(cd $sdk && scripts/feeds install -p libremesh -a)
	(cd $sdk && scripts/feeds install -p libremap -a)
	(cd $sdk && scripts/feeds install -p limeui -a)
	cp $sdk_config $sdk/.config
	make -C $sdk defconfig
	make -j$J -C $sdk V=$V
}

download_feeds() {
	feeds_template="$1"
	output="$feeds_dir"
	rm -f $feeds_file
	[ ! -d "$output" ] && mkdir -p "$output"
	echo "Downloading feeds into $output/"

	cat $feeds_template | grep ^src-git | while read feed; do
		name="$(echo $feed | awk '{print $2}')"
		full_url="$(echo $feed | awk '{print $3}')"
		[ -d $output/$name ] && rm -rf $output/$name
		if echo "$full_url" | grep \;; then
			url="$(echo $full_url | awk -F\; '{print $1}')"
			branch="$(echo $full_url | awk -F\; '{print $2}')"
			git clone $url -b $branch $output/$name
		elif echo "$full_url" | grep \^; then
			url="$(echo $full_url | awk -F\^ '{print $1}')"
			commit="$(echo $full_url | awk -F\^ '{print $2}')"
			git clone $url $output/$name
			( cd $output/$name && git checkout $commit )
		fi
		echo "src-link $name $PWD/$output/$name" >> $feeds_file
	done

	[ -d $output/libremesh ] && rm -rf $output/libremesh
	git clone $lime_repo -b $lime_branch $output/libremesh
	echo "src-link libremesh $PWD/$output/libremesh" >> $feeds_file
	
	[ -d $output/libremap ] && rm -rf $output/libremap
	git clone $limap_repo -b $limap_branch $output/libremap
	echo "src-link libremap $PWD/$output/libremap" >> $feeds_file
	
	[ -d $output/limeui ] && rm -rf $output/limeui
	git clone $limeui_repo -b $limeui_branch $output/limeui
	echo "src-link limeui $PWD/$output/limeui" >> $feeds_file
}

download_all() {
	cat $targets_list | while read t; do download $t; done
}

download() {
	target="$1"
	[ -z "$target" ] && {
		echo "Download SDK and ImageBuilder files first"
		usage
		exit 1
	}
	url="$base_url/$target"
	output="$release/$target"
	[ ! -d "$output" ] && mkdir -p "$output"
	
	sdk_file="$(wget -q -O- $url | grep lede-sdk | grep href | awk -F\> '{print $4}' | awk -F\< '{print $1}')"
	echo "Downloading $url/$sdk_file"
	wget -c "$url/$sdk_file" -O "$tmp_dir/$sdk_file"
	tar xf $tmp_dir/$sdk_file -C $output/
	[ $? -eq 0 ] && {
		[ -d $output/sdk ] && rm -rf $output/sdk
		mv $output/lede-sdk* $output/sdk
		rm -rf $output/sdk/dl
		dl=$downloads_dir
		echo $dl | grep -q / || dl="$PWD/$dl"
		ln -s $dl $output/sdk/dl
		#rm -f $TMP/$SDK_FILE
	} || echo "Error installing SDK"
	
	ib_file="$(wget -q -O- $url | grep lede-imagebuilder | grep href | awk -F\> '{print $4}' | awk -F\< '{print $1}')"
	echo "Downloading $url/$ib_file"
	wget -c "$url/$ib_file" -O "$tmp_dir/$ib_file"
	tar xf $tmp_dir/$ib_file -C $output/
	[ $? -eq 0 ] && {
#TODO: link IB with SDK packages
		[ -d $output/ib ] && rm -rf $output/ib
		mv $output/lede-imagebuilder* $output/ib
		#rm -f $TMP/$IB_FILE
	} || echo "Error installing ImageBuilder"
}

[ -z "$1" ] && usage

while getopts "ad:f:b:" opt; do
	case $opt in
	a) 
	  download_all
	;;
	d)
	  download $OPTARG
	;;
	f)
	  download_feeds $OPTARG
	;;
	b)
	  build_packets $OPTARG
	;;
	*)
	  echo "Invalid option: -$OPTARG"
	  usage
	;;
  esac
done
