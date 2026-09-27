# Homebrew cask template for the future Fiavaion/homebrew-tap repo (PRD M5).
# Copy to Casks/switchboard.rb in that repo. On each release, set `version` and
# `sha256` from the last two lines printed by scripts/release.sh.
# The download URL only works once Fiavaion/switchboard is PUBLIC (see docs/DEPLOYMENT.md).
cask "switchboard" do
  version "0.0.1"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_SH"

  url "https://github.com/Fiavaion/switchboard/releases/download/v#{version}/Switchboard-#{version}.zip"
  name "Switchboard"
  desc "Per-window Cmd+Tab switcher and screenshot-to-clipboard utility"
  homepage "https://github.com/Fiavaion/switchboard"

  depends_on macos: ">= :sonoma"

  app "Switchboard.app"

  uninstall quit: "com.fiavaion.switchboard"

  zap trash: "~/Library/Preferences/com.fiavaion.switchboard.plist"
end
