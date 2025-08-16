# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
inherit git-r3 cmake

DESCRIPTION="Truly independent web browser"
LICENSE="BSD-2"
HOMEPAGE="https://ladybird.org"
EGIT_REPO_URI="https://github.com/ladybirdbrowser/ladybird.git"
EGIT_COMMIT="HEAD"
#https://download.adobe.com/pub/adobe/iccprofiles/win/AdobeICCProfilesCS4Win_end-user.zip
SRC_URI="
https://raw.githubusercontent.com/publicsuffix/list/76dbfcab5c3f0b1ac4e78ebeb6273a8b4db74ab7/public_suffix_list.dat -> suffixes
"
RESTRICT="mirror"

SLOT="0"
KEYWORDS=""

IUSE="vulkan"

# how to version check skia on 9999?
DEPEND="
	>=media-libs/skia-129[vulkan?]
	media-libs/libjxl
	media-libs/libwebp
	media-libs/libavif
	>=media-libs/libpng-1.6.45[apng]
	media-libs/woff2
	media-libs/libglvnd
	virtual/libcrypt
	dev-db/sqlite
	dev-libs/icu
	dev-cpp/simdutf
	dev-qt/qtbase:6[network,widgets,gui]
	app-misc/ca-certificates
"
RDEPEND="${DEPEND}"
BDEPEND="
	virtual/pkgconfig
	llvm-core/lld
"
#badly-written cmake file requires lld

src_prepare() {
	# temporary workaround my last skia install
	#sed -i ${S}/vcpkg.json -e s/129#0/130#0/ || die "unable to patch required skia version"

	# took from a nix issue/pull... idk why the '' thing (seems just broken to me)
	cat > ${S}/Meta/CMake/FindWebP.cmake<<EOF
find_package(PkgConfig)
pkg_check_modules(WEBP libwebp REQUIRED)
include_directories(''${WEBP_INCLUDE_DIRS})
link_directories(''${WEBP_LIBRARY_DIRS})
EOF
	# added some more love
	sed -i ${S}/Libraries/LibGfx/CMakeLists.txt -e "s/find_package(WebP REQUIRED)/pkg_check_modules(WebP REQUIRED IMPORTED_TARGET libwebp)\nfind_package(WebP REQUIRED IMPORTED TARGET)/" || die "unable to patch"
	sed -i ${S}/Libraries/LibGfx/CMakeLists.txt -e s/WebP::webp/webp/g || die "unable to patch"
	sed -i ${S}/Libraries/LibGfx/CMakeLists.txt -e s/WebP::libwebp/webp/g || die "unable to patch"
	# dear cmake understander: see build.ninja patched below. this makes no sense to me
	#sed -i ${S}/AK/CMakeLists.txt -e "s/find_package(simdutf REQUIRED)/find_package(PkgConfig)\npkg_check_modules(simdutf REQUIRED IMPORTED_TARGET GLOBAL)\nfind_package(simdutf REQUIRED SHARED)/g" || die "unable to patch"

	# patch WebGL linking with GLESv2
	sed -i "${S}/Libraries/LibWeb/CMakeLists.txt" \
		-e "s/\(target_link_libraries(LibWeb\)\([^)]*\)/\1\2 GLESv2 GL/" \
		|| die "Unable to add GLESv2 linking"

	# patch cmake copying a file it didn't download
	sed -i ${S}/Meta/CMake/ca_certificates_data.cmake \
		-e 's@^.*configure_file.*$@#&@'
	# patching cmake verify globs
	mkdir -p ${S}/Lagom || die "unable to create directory"

	ln -s /etc/ssl/certs/ca-certificates.crt ${S}/Lagom/cacert.pem || die "unable to copy ca-certificates"

	cmake_src_prepare
	eapply_user
}

src_configure() {
	local mycmakeargs=(
		-DENABLE_NETWORK_DOWNLOADS=OFF
		-DSERENITY_CACHE_DIR=${BUILD_DIR}/downloads
		-DWITH_VULKAN=$(usex vulkan ON OFF)
		-DLAGOM_USE_LINKER
	)
	mkdir -p ${BUILD_DIR}/downloads/CACERT/ || die "unable to mkdir"
	mkdir -p ${BUILD_DIR}/downloads/PublicSuffix/ || die "unable to mkdir"
	mkdir -p ${BUILD_DIR}/Lagom/ || dir "unable to mkdir"
	ln -s /etc/ssl/certs/ca-certificates.crt ${BUILD_DIR}/Lagom/cacert.pem || die "unable to copy ca-certificates"
	ln -s /etc/ssl/certs/ca-certificates.crt ${BUILD_DIR}/downloads/CACERT/cacert-2023-12-12.pem || die "copying CA root"
	cp /var/cache/distfiles/suffixes ${BUILD_DIR}/downloads/PublicSuffix/public_suffix_list.dat || dir "copying suffixes"
	cmake_src_configure

	# i don't get cmake. it's a total waste of time on the docs while patching the generated is easy
	# 1. webp is lib prefixed...
	# 2. it chooses the libsimdutf.a instead .so when everywhere the opposite is stated
	sed -i ${BUILD_DIR}/build.ninja \
		-e 's@/usr/local/\(lib[0-9]*\)/libsimdutf.a@/usr/\1/libsimdutf.so@g' \
		-e 's/-llibwebpmux/-lwebpmux/g' \
		|| die "unable to patch build.ninja"
}
