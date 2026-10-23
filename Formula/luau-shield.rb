class LuauShield < Formula
  desc "Static taint analysis that finds exploitable bugs in Roblox Luau code"
  homepage "https://github.com/Topogamer0/luau-shield"
  license "MIT"

  # Prebuilt binaries where the release has them, the source everywhere else.
  on_macos do
    on_arm do
      url "https://github.com/Topogamer0/luau-shield/releases/download/v0.2.0/luau-shield-0.2.0-macos-aarch64.zip"
      sha256 "649e21747005f40cfa985c0ddd5f3ec07734bc075c5c9dafbe885e45aa96dfff"
    end
    on_intel do
      url "https://github.com/Topogamer0/luau-shield/releases/download/v0.2.0/luau-shield-0.2.0-macos-x86_64.zip"
      sha256 "027211b75aa253d989432f8d62c2844a81191ab845b1faa083442e03b6a8052d"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/Topogamer0/luau-shield/archive/refs/tags/v0.2.0.tar.gz"
      sha256 "293f7a3f5ebe49a93cacb4d238eb383f8b604f34408de2de0e29b2786ce34376"

      depends_on "rust" => :build
    end
    on_intel do
      url "https://github.com/Topogamer0/luau-shield/releases/download/v0.2.0/luau-shield-0.2.0-linux-x86_64.zip"
      sha256 "31d5913bc6e1c41fb2905588c808f03b9728051bb3d45a19e0be0c4c8b3c095e"
    end
  end

  def install
    if File.exist?("Cargo.toml")
      system "cargo", "install", *std_cargo_args
    else
      bin.install "luau-shield"
    end
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/luau-shield --version")

    # A server script that runs code sent by any client.
    (testpath/"game/server/Admin.server.luau").write <<~LUAU
      local ReplicatedStorage = game:GetService("ReplicatedStorage")
      local remote = ReplicatedStorage:WaitForChild("RunCommand")

      remote.OnServerEvent:Connect(function(player, source)
        loadstring(source)()
      end)
    LUAU
    output = shell_output("#{bin}/luau-shield check --no-config --color never game", 1)
    assert_match "critical[luau-shield004]: Client-controlled value reaches loadstring/require", output
    assert_match "game/server/Admin.server.luau:5:3", output
    assert_match "Found 1 problem (1 critical) in 1 file.", output

    # The same remote, dispatching through an allow-list, is safe.
    (testpath/"fixed/server/Admin.server.luau").write <<~LUAU
      local ReplicatedStorage = game:GetService("ReplicatedStorage")
      local remote = ReplicatedStorage:WaitForChild("RunCommand")

      local Commands = {
        ping = function(player)
          print(player.Name, "pong")
        end,
      }

      remote.OnServerEvent:Connect(function(player, name)
        if typeof(name) ~= "string" then
          return
        end
        local command = Commands[name]
        if command then
          command(player)
        end
      end)
    LUAU
    report = JSON.parse(shell_output("#{bin}/luau-shield check --no-config --format json fixed"))
    assert_equal 0, report["summary"]["findings"]
    assert_equal 1, report["summary"]["files"]
  end
end
