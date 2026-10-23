class OllamaCRag < Formula
  desc "Local retrieval-augmented generation in C, with Ollama and SQLite"
  homepage "https://github.com/Topogamer0/ollama-c-rag"
  url "https://github.com/Topogamer0/ollama-c-rag/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "9479e9da8da64313bb490d0ac08266a1cb6b35bbe98c7b75a4cb07ff53a66e8d"
  license "MIT"

  depends_on "cmake" => [:build, :test]
  depends_on "pkgconf" => :test
  depends_on "topogamer0/tap/ollama-c"

  uses_from_macos "sqlite"

  def install
    # Link the installed Ollama-C and SQLite instead of downloading and bundling them.
    args = %w[
      -DBUILD_SHARED_LIBS=ON
      -DRAG_BUILD_CLI=ON
      -DRAG_BUILD_EXAMPLES=OFF
      -DRAG_BUILD_TESTS=OFF
      -DRAG_USE_SYSTEM_OLLAMA_C=ON
      -DRAG_USE_SYSTEM_SQLITE=ON
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    require "digest"
    require "socket"

    # A fake Ollama server: /api/embed hashes the words of each text into a
    # vector, so that texts sharing words are similar.
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server_thread = Thread.new do
      loop do
        client = server.accept
        client.gets
        headers = {}
        while (line = client.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.strip.downcase] = value.strip
        end
        request = JSON.parse(client.read(headers["content-length"].to_i))
        embeddings = Array(request["input"]).map do |text|
          vector = Array.new(64, 0.0)
          text.downcase.scan(/\w+/) { |word| vector[Digest::SHA256.digest(word).unpack1("Q<") % 64] += 1.0 }
          vector
        end
        reply = { model: request["model"], embeddings: }.to_json
        client.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                     "Content-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}"
        client.close
      end
    end

    (testpath/"notes/shopping.txt").write "Milk, eggs, bread and coffee for the week.\n"
    (testpath/"notes/work.md").write "# Work\n\nThe quarterly report is due on Friday.\n"
    (testpath/"notes/trips/holidays.md").write <<~MARKDOWN
      # Holidays

      In August we go to Sicily for a week.
      Book the ferry from Naples before June.
    MARKDOWN

    ENV["OLLAMA_HOST"] = "http://127.0.0.1:#{port}"
    ENV["RAGC_EMBED_MODEL"] = "mock"
    output = shell_output("#{bin}/ragc index notes")
    assert_match "3 indexed, 0 unchanged, 0 removed, 0 skipped (3 chunks added)", output
    output = shell_output("#{bin}/ragc -k 1 search when is the ferry to Sicily")
    assert_match "1. notes/trips/holidays.md:1-4", output
    assert_match "Book the ferry from Naples before June.", output
    assert_match "mock (64 dimensions)", shell_output("#{bin}/ragc stats")

    # The library, through CMake and pkg-config.
    (testpath/"test.c").write <<~C
      #include <ollama_rag.h>
      #include <stdio.h>
      #include <string.h>

      int main(void) {
        rag_t *rag;
        rag_stats_t stats;
        if (strcmp(rag_version(), RAG_VERSION) != 0) return 2;
        if (rag_open("ragc.db", NULL, &rag) != RAG_OK || rag_stats(rag, &stats) != RAG_OK) {
          fprintf(stderr, "error: %s\\n", rag_last_error(rag)->message);
          rag_close(rag);
          return 1;
        }
        printf("ollama-rag-c %s: %s, %zu chunks\\n", rag_version(), stats.embed_model, stats.chunks);
        rag_close(rag);
        return 0;
      }
    C
    expected = "ollama-rag-c #{version}: mock, 3 chunks"

    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 3.14)
      project(ollama_rag_c_test C)
      find_package(ollama-rag-c #{version.major_minor} REQUIRED)
      add_executable(test_cmake test.c)
      target_link_libraries(test_cmake PRIVATE ollama::rag)
    CMAKE
    system "cmake", "-S", ".", "-B", "build"
    system "cmake", "--build", "build"
    assert_equal expected, shell_output("./build/test_cmake").chomp

    flags = shell_output("pkgconf --cflags --libs ollama-rag-c").chomp.split
    system ENV.cc, "test.c", "-o", "test", *flags
    assert_equal expected, shell_output("./test").chomp
  ensure
    server_thread&.kill
    server&.close
  end
end
