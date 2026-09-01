import os

from conan import ConanFile
from conan.errors import ConanInvalidConfiguration
from conan.tools.build import check_min_cppstd
from conan.tools.cmake import CMake, CMakeDeps, CMakeToolchain, cmake_layout
from conan.tools.env import Environment
from conan.tools.files import copy, get


required_conan_version = ">=2.31.2 <2.32"


class HyperscanConan(ConanFile):
    name = "hyperscan"
    version = "5.4.2.1"
    description = "High-performance multiple regular expression matching library"
    license = "BSD-3-Clause"
    homepage = "https://github.com/intel/hyperscan"
    url = "https://github.com/intel/hyperscan"
    topics = ("regex", "matching")
    package_type = "static-library"
    settings = "os", "arch", "compiler", "build_type"
    options = {"fPIC": [True, False], "sanitizers": [True, False]}
    default_options = {
        "fPIC": True,
        "sanitizers": False,
        "boost/*:header_only": True,
        "openssl/*:shared": False,
        "openssl/*:no_apps": True,
        "openssl/*:no_fips": True,
        "openssl/*:no_zlib": True,
    }

    def layout(self):
        cmake_layout(self, src_folder="src")

    def requirements(self):
        self.requires("boost/1.83.0", transitive_headers=True)
        self.requires("openssl/3.5.8")

    def build_requirements(self):
        self.tool_requires("ragel/6.10")

    def validate_build(self):
        if self.settings_build.os == "Linux" and self.settings_build.arch != "x86_64":
            raise ConanInvalidConfiguration(
                "Linux Hyperscan builds require an x86_64 build host"
            )
        if self.settings_build.os not in ("Linux", "Macos"):
            raise ConanInvalidConfiguration(
                "Hyperscan can be built only on Linux or macOS"
            )

    def validate(self):
        check_min_cppstd(self, 11)
        if self.settings.os not in ("Linux", "Macos"):
            raise ConanInvalidConfiguration(
                "this Hyperscan package supports only Linux and macOS"
            )
        if self.settings.arch != "x86_64":
            raise ConanInvalidConfiguration(
                "this Hyperscan package supports only x86_64"
            )
        if str(self.settings.compiler.cppstd) != "11":
            raise ConanInvalidConfiguration(
                "this Hyperscan package requires compiler.cppstd=11 exactly"
            )

    def source(self):
        get(
            self,
            url=(
                "https://github.com/intel/hyperscan/archive/refs/tags/"
                "v5.4.2.1.tar.gz"
            ),
            sha256=(
                "7119ef2db45c98abd816ba789aae82fdfd1a0b240bb40a88bac2d90933a346df"
            ),
            strip_root=True,
        )

    def generate(self):
        deps = CMakeDeps(self)
        # Upstream treats CMAKE_MODULE_PATH as one directory rather than a
        # list. Its own Boost module and CMake's built-in FindOpenSSL consume
        # Conan's toolchain search paths without generated find modules.
        deps.set_property("boost", "cmake_find_mode", "none")
        deps.set_property("openssl", "cmake_find_mode", "none")
        deps.generate()

        flags = ["-march=core2", "-mtune=generic"]
        if self.options.sanitizers:
            flags.extend(
                [
                    "-fsanitize=address,undefined",
                    "-fno-omit-frame-pointer",
                ]
            )

        toolchain = CMakeToolchain(self)
        toolchain.cache_variables["CMAKE_POLICY_VERSION_MINIMUM"] = "3.5"
        toolchain.variables["CMAKE_EXPORT_COMPILE_COMMANDS"] = True
        toolchain.variables["BUILD_AVX512"] = False
        toolchain.variables["BUILD_AVX512VBMI"] = False
        toolchain.variables["BUILD_CHIMERA"] = False
        toolchain.variables["BUILD_EXAMPLES"] = False
        toolchain.variables["DISABLE_ASSERTS"] = not bool(self.options.sanitizers)
        toolchain.variables["DUMP_SUPPORT"] = False
        toolchain.variables["FAT_RUNTIME"] = False
        toolchain.variables["OPTIMISE"] = not bool(self.options.sanitizers)
        toolchain.variables["VALIDATE_PATTERN_INPUT"] = False
        toolchain.extra_cflags = flags
        toolchain.extra_cxxflags = flags
        if self.options.sanitizers:
            toolchain.extra_ldflags = ["-fsanitize=address,undefined"]
        toolchain.generate()

    def _source_date_environment(self):
        environment = Environment()
        environment.define("SOURCE_DATE_EPOCH", "1787718881")
        return environment.vars(self)

    def build(self):
        cmake = CMake(self)
        with self._source_date_environment().apply():
            cmake.configure()
            cmake.build(target="hs")

    def package(self):
        copy(
            self,
            "LICENSE",
            src=self.source_folder,
            dst=os.path.join(self.package_folder, "licenses"),
        )
        for header in ("hs.h", "hs_common.h", "hs_compile.h", "hs_runtime.h"):
            copy(
                self,
                header,
                src=os.path.join(self.source_folder, "src"),
                dst=os.path.join(self.package_folder, "include", "hs"),
            )
        copy(
            self,
            "libhs.a",
            src=os.path.join(self.build_folder, "lib"),
            dst=os.path.join(self.package_folder, "lib"),
        )

    def package_info(self):
        self.cpp_info.set_property("cmake_file_name", "hyperscan")
        self.cpp_info.set_property("cmake_target_name", "hyperscan::hs")
        self.cpp_info.libs = ["hs"]
        self.cpp_info.requires = ["openssl::crypto"]
        self.cpp_info.ignored_requires = ["boost"]
        self.cpp_info.defines = [
            'REGEX_UTILS_HYPERSCAN_PACKAGE_VERSION="5.4.2.1"',
            "REGEX_UTILS_HYPERSCAN_PACKAGE_SANITIZERS={}".format(
                1 if self.options.sanitizers else 0
            )
        ]
        if self.options.sanitizers:
            sanitizer_flags = [
                "-fsanitize=address,undefined",
                "-fno-omit-frame-pointer",
            ]
            self.cpp_info.cflags = sanitizer_flags
            self.cpp_info.cxxflags = sanitizer_flags
            self.cpp_info.sharedlinkflags = ["-fsanitize=address,undefined"]
            self.cpp_info.exelinkflags = ["-fsanitize=address,undefined"]
        if self.settings.os == "Linux":
            self.cpp_info.system_libs = ["m"]
