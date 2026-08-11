# Deploy marker shown in the footer, so you can tell at a glance whether a
# deploy actually landed without opening a shell.
#
# Three independent signals, because each one fails differently:
#   VERSION  — bumped by hand in the VERSION file; says WHICH release this is
#   SHA      — git commit actually checked out; catches "pushed but pull failed"
#   BOOTED_AT— process start time; catches "pulled but never restarted"
#
# All resolved once at class load. deploy.sh restarts the service, so a fresh
# BOOTED_AT is proof the restart happened.
module AppVersion
  VERSION = begin
    file = Rails.root.join("VERSION")
    file.exist? ? file.read.strip : "0.0.0"
  end

  SHA = begin
    sha = `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip
    sha.empty? ? "unknown" : sha
  rescue StandardError
    "unknown"
  end

  BOOTED_AT = Time.current

  def self.to_s
    "v#{VERSION} · #{SHA}"
  end

  # "10/08 23:59" in Sao Paulo time — short enough for a footer line.
  def self.booted_at_label
    BOOTED_AT.in_time_zone("America/Sao_Paulo").strftime("%d/%m %H:%M")
  end
end
