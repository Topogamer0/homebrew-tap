class OllamaC < Formula
  desc "C client library for Ollama, a port of ollama-python"
  homepage "https://github.com/Topogamer0/Ollama-C"
  url "https://github.com/Topogamer0/Ollama-C/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "39b6ad99f61678619f01af094aa17a1257c3594957e3e2bbfb6a35c1b269b91d"
  license "MIT"

  depends_on "cmake" => [:build, :test]
  depends_on "pkgconf" => :test

  uses_from_macos "curl"

  def install
    args = %w[
      -DBUILD_SHARED_LIBS=ON
      -DOLLAMA_BUILD_EXAMPLES=OFF
      -DOLLAMA_BUILD_TESTS=OFF
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    require "socket"

    # A fake Ollama server that answers /api/generate with the prompt it received.
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    requests = []
    server_thread = Thread.new do
      loop do
        client = server.accept
        requests << client.gets.split[0, 2].join(" ")
        headers = {}
        while (line = client.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.strip.downcase] = value.strip
        end
        request = JSON.parse(client.read(headers["content-length"].to_i))
        reply = { model: request["model"], response: "echo: #{request["prompt"]}", done: true }.to_json
        client.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                     "Content-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}"
        client.close
      end
    end

    (testpath/"test.c").write <<~C
      #include <ollama.h>
      #include <stdio.h>
      #include <string.h>

      int main(int argc, char **argv) {
        if (argc != 2 || strcmp(ollama_version(), OLLAMA_C_VERSION) != 0) return 2;
        ollama_client_t *client = ollama_client_new(argv[1]);
        if (client == NULL) return 1;
        ollama_generate_request_t request = {.model = "mock", .prompt = "Why is the sky blue?"};
        ollama_generate_response_t *response = NULL;
        if (ollama_generate(client, &request, &response) != OLLAMA_OK) {
          fprintf(stderr, "error: %s\\n", ollama_last_error(client)->message);
          ollama_client_free(client);
          return 1;
        }
        printf("ollama-c %s, %s: %s\\n", ollama_version(), response->model, response->response);
        ollama_response_free(response);
        ollama_client_free(client);
        ollama_cleanup();
        return 0;
      }
    C
    expected = "ollama-c #{version}, mock: echo: Why is the sky blue?"

    # pkg-config
    flags = shell_output("pkgconf --cflags --libs ollama-c").chomp.split
    system ENV.cc, "test.c", "-o", "test", *flags
    assert_equal expected, shell_output("./test http://127.0.0.1:#{port}").chomp

    # CMake
    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 3.14)
      project(ollama_c_test C)
      find_package(ollama-c #{version} REQUIRED)
      add_executable(test_cmake test.c)
      target_link_libraries(test_cmake PRIVATE ollama::ollama)
    CMAKE
    system "cmake", "-S", ".", "-B", "build", "-DCMAKE_PREFIX_PATH=#{opt_prefix}"
    system "cmake", "--build", "build"
    assert_equal expected, shell_output("./build/test_cmake http://127.0.0.1:#{port}").chomp

    assert_equal ["POST /api/generate"] * 2, requests
  ensure
    server_thread&.kill
    server&.close
  end
end
