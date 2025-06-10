#!/bin/bash
#
# build_android.sh - build rsync binaries for different mobile architectures using a cross compiler
#
# Florian Dejonckheere <florian@floriandejonckheere.be>
#

# Whether or not to strip binaries (smaller filesize)
set -e

STRIP=1

ARCH=(aarch64 x86_64)
CCPREFIX=(aarch64-linux-musl x86_64-linux-musl)

# 依赖库版本
OPENSSL_VERSION="3.1.4"
XXHASH_VERSION="0.8.2"
ZSTD_VERSION="1.5.5"
LZ4_VERSION="1.9.4"

function create_toolchain() {
	if [ $BUILD_TOOLCHAIN ]; then
		echo "I: Building toolchain"
		for target in $CCPREFIX; do
			# Configure
			echo "TARGET = $target" > musl-cross-make/config.mak
			echo "GCC_VER = 7.2.0" >> musl-cross-make/config.mak
			echo "LINUX_VER = 4.4.10" >> musl-cross-make/config.mak

			# Build
			make -C musl-cross-make

			# Install
			make -C musl-cross-make OUTPUT="/" DESTDIR="$PWD/toolchain" install
		done
	else
		if ! [ -d toolchain ]; then
			mkdir toolchain
			local wgettools="./wget-$(uname -m)"
			chmod +x "$wgettools"
			"$wgettools" --version

			echo "I: Downloading prebuilt toolchain"
			"$wgettools" --no-check-certificate --progress=bar:force --continue https://github.com/pedoc/rsync-static/releases/download/continuous/aarch64-linux-musl-cross.tgz -O /tmp/aarch64-linux-musl.tgz
			"$wgettools" --no-check-certificate --progress=bar:force --continue https://github.com/pedoc/rsync-static/releases/download/continuous/x86_64-linux-musl-cross.tgz -O /tmp/x86_64-linux-musl.tgz

			for tgz in /tmp/*linux-musl*.tgz; do
				tar -xf $tgz -C toolchain
			done
		fi
	fi
}

function find_toolchain() {
	for I in $(seq 0 $((${#ARCH[@]} - 1))); do
		# Use toolchain in following builds
		TOOLCHAIN_PATH="$(readlink -f $(dirname $(find . -name "${CCPREFIX[$I]}-gcc"))/..)"
		export PATH=$PATH:$TOOLCHAIN_PATH/bin
	done
}

function build_dependencies() {
	echo "I: Building dependencies"
	mkdir -p deps
	cd deps

	rm -rf openssl-${OPENSSL_VERSION} || true
	rm -rf xxHash-${XXHASH_VERSION} || true
	rm -rf zstd-${ZSTD_VERSION} || true
	rm -rf lz4-${LZ4_VERSION} || true

	# 下载依赖库源码
	wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
	wget https://github.com/Cyan4973/xxHash/archive/v${XXHASH_VERSION}.tar.gz -O xxhash-${XXHASH_VERSION}.tar.gz
	wget https://github.com/facebook/zstd/archive/v${ZSTD_VERSION}.tar.gz -O zstd-${ZSTD_VERSION}.tar.gz
	wget https://github.com/lz4/lz4/archive/v${LZ4_VERSION}.tar.gz -O lz4-${LZ4_VERSION}.tar.gz

	# 解压源码
	tar xf openssl-${OPENSSL_VERSION}.tar.gz
	tar xf xxhash-${XXHASH_VERSION}.tar.gz
	tar xf zstd-${ZSTD_VERSION}.tar.gz
	tar xf lz4-${LZ4_VERSION}.tar.gz

	# 编译 OpenSSL
	cd openssl-${OPENSSL_VERSION}
	./Configure linux-generic64 no-shared no-dso --prefix=$PWD/install
	make -j$(nproc)
	make install
	cd ..

	# 编译 xxHash
	cd xxHash-${XXHASH_VERSION}
	make -j$(nproc) CC=${CCPREFIX[$I]}-gcc
	make install PREFIX=$PWD/install
	cd ..

	# 编译 zstd
	cd zstd-${ZSTD_VERSION}
	make -j$(nproc) CC=${CCPREFIX[$I]}-gcc
	make install PREFIX=$PWD/install
	cd ..

	# 编译 lz4
	cd lz4-${LZ4_VERSION}
	make -j$(nproc) CC=${CCPREFIX[$I]}-gcc
	make install PREFIX=$PWD/install
	cd ..

	cd ..
}

function build_rsync() {
	echo "I: Building rsync"
	git config --global --add safe.directory $PWD
	git submodule update --init --recursive

	# sudo apt update
	# sudo apt install -y gcc g++ gawk autoconf automake python3-cmarkgfm
	# sudo apt install -y acl libacl1-dev
	# sudo apt install -y attr libattr1-dev
	# sudo apt install -y libxxhash-dev
	# sudo apt install -y libzstd-dev
	# sudo apt install -y liblz4-dev
	# sudo apt install -y libssl-dev

	#pip3 install cmarkgfm
	
	cd rsync/
	for I in $(seq 0 $((${#ARCH[@]} - 1))); do
		echo "****************************************"
		echo Building for ${ARCH[$I]}
		echo "****************************************"

		export CC="${CCPREFIX[$I]}-gcc"
		echo "pwd=$PWD CC=$CC arch:${CCPREFIX[$I]} host:${ARCH[$I]}"
		which $CC
		echo "info:"
		$CC --version

		# 编译依赖库
		build_dependencies
		
		make clean || true
		# 设置依赖库路径
		export CFLAGS="-static -I$PWD/deps/openssl-${OPENSSL_VERSION}/install/include -I$PWD/deps/xxHash-${XXHASH_VERSION}/install/include -I$PWD/deps/zstd-${ZSTD_VERSION}/install/include -I$PWD/deps/lz4-${LZ4_VERSION}/install/include"
		export LDFLAGS="-L$PWD/deps/openssl-${OPENSSL_VERSION}/install/lib -L$PWD/deps/xxHash-${XXHASH_VERSION}/install/lib -L$PWD/deps/zstd-${ZSTD_VERSION}/install/lib -L$PWD/deps/lz4-${LZ4_VERSION}/install/lib"

		./configure --host="${ARCH[$I]}" \
			--enable-openssl \
			--enable-xxhash \
			--enable-zstd \
			--enable-lz4

		make
		[ $STRIP ] && "${CCPREFIX[$I]}-strip" rsync
		mv rsync "../rsync-${ARCH[$I]}"
	done
	cd ..
}

create_toolchain
find_toolchain
build_rsync
