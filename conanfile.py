from conan import ConanFile


required_conan_version = ">=2.31.2 <2.32"


class RegexUtilsCliConan(ConanFile):
    name = "regex-utils-cli"
    version = "0.1.0"
    package_type = "application"
    settings = "os", "arch", "compiler", "build_type"
    options = {"sanitizers": [True, False]}
    default_options = {"sanitizers": False}

    def requirements(self):
        self.requires("hyperscan/5.4.2.1")

    def configure(self):
        self.options["hyperscan"].sanitizers = self.options.sanitizers

    def generate(self):
        from conan.tools.cmake import CMakeDeps, CMakeToolchain

        CMakeDeps(self).generate()
        CMakeToolchain(self).generate()

    def layout(self):
        build_name = "hyperscan-sanitize" if self.options.sanitizers else "hyperscan"
        self.folders.generators = f"build/{build_name}/conan"
