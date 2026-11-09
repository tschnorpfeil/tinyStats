class Tinystats < Formula
  desc "CPU, GPU, RAM and network activity beside the MacBook notch"
  homepage "https://github.com/tschnorpfeil/tinyStats"
  url "https://github.com/tschnorpfeil/tinyStats.git", tag: "v2.0"
  head "https://github.com/tschnorpfeil/tinyStats.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "./build.sh", "tinyStats #{version}"
    prefix.install "tinyStats.app"
    libexec.install "bin/tinystats"
    # The CLI finds the app in this keg, and older kegs still running after an upgrade.
    (bin/"tinystats").write_env_script libexec/"tinystats",
      TINYSTATS_APP_DIR: prefix, TINYSTATS_KEGS: HOMEBREW_CELLAR/name
  end

  def caveats
    <<~EOS
      Start: tinystats
      Update: tinystats update (upgrades and restarts the app)
    EOS
  end

  test do
    assert_match "tinystats [", shell_output("#{bin}/tinystats help")
  end
end
