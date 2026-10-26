class Failstep < Formula
  desc "Systematic allocation-failure testing for C, compatible with AddressSanitizer"
  homepage "https://github.com/Topogamer0/failstep"
  license "MIT"

  depends_on "cmake" => :test
  depends_on "pkgconf" => :test

  # Prebuilt binaries where the release has them, the source everywhere else.
  on_macos do
    on_arm do
      url "https://github.com/Topogamer0/failstep/releases/download/v0.1.2/failstep-v0.1.2-macos-arm64.tar.gz"
      sha256 "d55deef1e4e8137efa48d9e4ea32735738b07fdcc64a5b94059cf6daae52ba0d"
    end
    on_intel do
      url "https://github.com/Topogamer0/failstep/archive/refs/tags/v0.1.2.tar.gz"
      sha256 "e772a9614957d55182b66af6a9978e9d9aa32fba6b9170dc434351d8cf59440b"

      depends_on "cmake" => :build
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/Topogamer0/failstep/archive/refs/tags/v0.1.2.tar.gz"
      sha256 "e772a9614957d55182b66af6a9978e9d9aa32fba6b9170dc434351d8cf59440b"

      depends_on "cmake" => :build
    end
    on_intel do
      url "https://github.com/Topogamer0/failstep/releases/download/v0.1.2/failstep-v0.1.2-linux-x86_64.tar.gz"
      sha256 "276c6c0ab23f7f6f68ce007598dfa77e4c58555d8aac7ce447dca6b7e6f92243"
    end
  end

  def install
    if File.exist?("CMakeLists.txt")
      args = %w[
        -DFAILSTEP_BUILD_CLI=ON
        -DFAILSTEP_BUILD_EXAMPLES=OFF
        -DFAILSTEP_BUILD_TESTS=OFF
      ]
      system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
      system "cmake", "--build", "build"
      system "cmake", "--install", "build"
    else
      # The release archive holds an installed tree (bin, include, lib).
      prefix.install "bin", "include", "lib"
      # Its pkg-config file names the directory it was built in.
      inreplace lib/"pkgconfig/failstep.pc", /^prefix=.*$/, "prefix=#{opt_prefix}"
    end
  end

  test do
    assert_match "failstep #{version}", shell_output("#{bin}/failstep --version")

    # The result of malloc() is used without a NULL check.
    (testpath/"bug.c").write <<~C
      #include <stdlib.h>
      #include <string.h>

      int main(void) {
        char *buffer = malloc(64);
        memset(buffer, 'x', 64);
        free(buffer);
        return 0;
      }
    C
    (testpath/"fixed.c").write <<~C
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      int main(void) {
        char *buffer = malloc(64);
        if (buffer == NULL) {
          fputs("out of memory\\n", stderr);
          return 0;
        }
        memset(buffer, 'x', 64);
        free(buffer);
        return 0;
      }
    C

    # pkg-config: build both programs with the override header and the runtime.
    flags = shell_output("pkgconf --cflags --libs failstep").chomp.split
    %w[bug fixed].each do |name|
      system ENV.cc, "-g", "-include", "failstep/override.h", "#{name}.c", "-o", name, *flags
    end
    output = shell_output("#{bin}/failstep enumerate -o out-bug -- ./bug", 1)
    assert_match "injected failure: allocation #1", output
    assert_match "runs=1  failing=1  problems=1", output
    output = shell_output("#{bin}/failstep enumerate -o out-fixed -- ./fixed")
    assert_match "No problems found", output

    # CMake: find_package() and the failstep_instrument() helper.
    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 3.14)
      project(failstep_test C)
      find_package(failstep #{version} REQUIRED)
      add_executable(bug_cmake bug.c)
      failstep_instrument(bug_cmake NO_ASAN)
    CMAKE
    system "cmake", "-S", ".", "-B", "build", "-DCMAKE_PREFIX_PATH=#{opt_prefix}"
    system "cmake", "--build", "build"
    report = JSON.parse(shell_output("#{bin}/failstep sites -q -f json -o out-cmake -- ./build/bug_cmake", 1))
    assert_equal 1, report["problems"]
    assert_equal 1, report["results"].first["alloc_index"]
  end
end
